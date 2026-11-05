#!/usr/bin/env python3
"""Compare the converted DSpark draft with the reference implementation.

Reference: the Speculators DSpark/DFlash code the draft was trained with
(github.com/vllm-project/speculators @ 7046ac6 plus the checkpoint's speculators.patch),
on top of the Swiss AI transformers fork (Apertus v1.5 target, see check_logits.py).

For one chat prompt (thinking off) the script:
1. runs the reference target layer by layer, records the inputs of the draft's target
   layers (1, 8, 15, 22, 29) for every prompt token and takes the greedy next token;
2. runs the reference draft on [that token, mask x 7] with the training mask (all prompt
   features visible, causal inside the block) and the Markov chain. This is the first
   draft llama-server makes after prefill. llama-speculative-simple gets the same draft
   when the prompt is extended by that token (it anchors on the last prompt token);
3. runs llama.cpp's draft-dspark on the same prompt and parses the logged first draft
   (top-3 candidates per slot, probabilities over the top 10 as llama.cpp's draft sampler);
4. reports per-slot agreement.

Usage (reference venv, see docs/IO.md):
  .venv-ref/bin/python scripts/check_dspark.py --speculators /path/to/speculators/src \\
      --target-hf models/hf/Apertus-v1.5-8B --draft-hf models/hf/Apertus-v1.5-8B-DSpark-e10-thinking-off \\
      --target-gguf models/apertus-v1.5-8b-F16.gguf --draft-gguf models/apertus-v1.5-8b-dspark-e10-F16.gguf
"""
import argparse
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

import torch
from safetensors import safe_open
from transformers import AutoConfig, AutoTokenizer, Qwen3Config
from transformers.models.apertus1p5.modeling_apertus1p5 import (
    Apertus1p5TextDecoderLayer,
    Apertus1p5TextRMSNorm,
    Apertus1p5TextRotaryEmbedding,
)
from transformers.models.qwen3.modeling_qwen3 import Qwen3RMSNorm, Qwen3RotaryEmbedding

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_logits import PREFIX, Weights  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
CANDIDATE = re.compile(r"draft candidate\s+(\d+), pos\s+(\d+):\s+(\d+) \(\s*([\d.]+)\)")


def load_speculators_layers(src: Path):
    path = src / "speculators/models/dflash/model_definitions.py"
    spec = importlib.util.spec_from_file_location("dflash_model_definitions", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.Qwen3DFlashDecoderLayer


@torch.no_grad()
def run_target(hf_dir: Path, ids: list[int], layer_ids: list[int]):
    config = AutoConfig.from_pretrained(hf_dir).text_config
    config._attn_implementation = "eager"
    w = Weights(hf_dir)
    n = len(ids)
    h = w.rows(PREFIX + "embed_tokens.weight", ids).float().unsqueeze(0)
    pos = torch.arange(n).unsqueeze(0)
    cos, sin = Apertus1p5TextRotaryEmbedding(config)(h, pos)
    mask = torch.full((n, n), float("-inf")).triu(1)[None, None]
    captured = {}
    for i in range(config.num_hidden_layers):
        if i in layer_ids:
            captured[i] = h[0].clone()
        layer = Apertus1p5TextDecoderLayer(config, i)
        layer.load_state_dict(w.prefixed(f"{PREFIX}layers.{i}."), strict=True)
        h = layer.float()(h, attention_mask=mask, position_embeddings=(cos, sin), position_ids=pos)
        print(f"  target layer {i + 1}/{config.num_hidden_layers}", end="\r", flush=True)
    print()
    norm = Apertus1p5TextRMSNorm(config.hidden_size, eps=config.rms_norm_eps)
    norm.load_state_dict({"weight": w.get(PREFIX + "norm.weight")})
    last = norm.float()(h)[0, -1]
    head = w.get("lm_head.weight")
    logits = torch.cat([chunk.float() @ last for chunk in head.split(16384)])
    return [captured[i] for i in layer_ids], int(logits.argmax()), w, head


@torch.no_grad()
def run_draft(draft_dir: Path, layer_cls, feats, anchor: int, tw: Weights, head, n_ctx: int, n_slots: int):
    cfg = json.loads((draft_dir / "config.json").read_text())
    tl = dict(cfg["transformer_layer_config"])
    qcfg = Qwen3Config(**tl)
    qcfg._attn_implementation = "eager"
    d = safe_open(draft_dir / "model.safetensors", "pt")

    def get(name):
        return d.get_tensor(name).float()

    hidden_norm = Qwen3RMSNorm(qcfg.hidden_size, eps=qcfg.rms_norm_eps)
    hidden_norm.weight.copy_(get("hidden_norm.weight"))
    ctx = hidden_norm(torch.cat(feats, dim=-1) @ get("fc.weight").T).unsqueeze(0)

    block = [anchor] + [cfg["mask_token_id"]] * (cfg["block_size"] - 1)
    x = tw.rows(PREFIX + "embed_tokens.weight", block).float().unsqueeze(0)
    nb = len(block)
    pos = torch.arange(n_ctx + nb).unsqueeze(0)
    cos, sin = Qwen3RotaryEmbedding(qcfg)(x, pos)
    mask = torch.zeros(nb, n_ctx + nb)
    if not cfg.get("sliding_window_non_causal", False):
        mask[:, n_ctx:] = torch.full((nb, nb), float("-inf")).triu(1)
    mask = mask[None, None]

    for i in range(qcfg.num_hidden_layers):
        layer = layer_cls(qcfg, i)
        prefix = f"layers.{i}."
        layer.load_state_dict({k[len(prefix):]: get(k) for k in d.keys() if k.startswith(prefix)}, strict=True)
        x = layer.float()(target_hidden=ctx, hidden_states=x, attention_mask=mask,
                          position_ids=pos, position_embeddings=(cos, sin))
    norm = Qwen3RMSNorm(qcfg.hidden_size, eps=qcfg.rms_norm_eps)
    norm.weight.copy_(get("norm.weight"))
    hidden = norm(x)[0]
    base = torch.cat([hidden @ chunk.float().T for chunk in head.split(16384)], dim=-1)  # [nb, 131072]

    w1, w2 = get("markov_head.markov_w1.weight"), get("markov_head.markov_w2.weight")
    prev, slots = anchor, []
    for i in range(n_slots):
        logits = base[i] + w2 @ w1[prev]
        top = torch.topk(logits, 10)
        probs = torch.softmax(top.values, dim=0)
        slots.append([(int(t), float(p)) for t, p in zip(top.indices[:3], probs[:3])])
        prev = int(top.indices[0])
    return slots


def run_llamacpp(target_gguf: Path, draft_gguf: Path, prompt: str, n_slots: int, threads: int):
    exe = REPO_ROOT / "vendor/llama.cpp/build/bin/llama-speculative-simple"
    if not exe.exists():
        subprocess.run(["cmake", "--build", str(exe.parent.parent), "--target", "llama-speculative-simple", "-j"],
                       check=True)
    out = subprocess.run(
        [str(exe), "-m", str(target_gguf), "-md", str(draft_gguf), "--spec-type", "draft-dspark",
         "--spec-draft-n-max", str(n_slots), "-p", prompt, "-n", "10", "--temp", "0", "--top-k", "1",
         "-c", "1024", "-t", str(threads), "-lv", "5"],
        capture_output=True, check=True)
    log = (out.stdout + out.stderr).decode("utf-8", errors="replace")
    Path("/tmp/check_dspark_llamacpp.log").write_text(log)
    slots: dict[int, list] = {}
    for line in log.splitlines():
        m = CANDIDATE.search(line)
        if m and int(m.group(2)) not in slots or (m and len(slots[int(m.group(2))]) < 3):
            slots.setdefault(int(m.group(2)), []).append((int(m.group(3)), float(m.group(4))))
        if len(slots) == n_slots and all(len(v) == 3 for v in slots.values()):
            break
    return [slots.get(i, []) for i in range(n_slots)]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--speculators", type=Path, required=True, help="speculators src/ dir at 7046ac6 + patch")
    p.add_argument("--target-hf", type=Path, required=True)
    p.add_argument("--draft-hf", type=Path, required=True)
    p.add_argument("--target-gguf", type=Path, required=True)
    p.add_argument("--draft-gguf", type=Path, required=True)
    p.add_argument("--question", default="Give me three tips for writing a clear project report.")
    p.add_argument("-k", "--slots", type=int, default=8)
    p.add_argument("-t", "--threads", type=int, default=4)
    args = p.parse_args()

    tok = AutoTokenizer.from_pretrained(args.target_hf)
    rendered = tok.apply_chat_template([{"role": "user", "content": args.question}], tokenize=False,
                                       add_generation_prompt=True, enable_thinking=False)
    rendered = rendered.removeprefix(tok.bos_token)
    ids = [tok.bos_token_id] + tok.encode(rendered, add_special_tokens=False)

    cfg = json.loads((args.draft_hf / "config.json").read_text())
    layer_ids = cfg["aux_hidden_state_layer_ids"]
    feats, anchor, tw, head = run_target(args.target_hf, ids, layer_ids)
    extended = rendered + tok.decode([anchor])
    if [tok.bos_token_id] + tok.encode(extended, add_special_tokens=False) != ids + [anchor]:
        raise SystemExit("prompt + anchor does not re-tokenize to the same ids; pick another question")
    print(f"prompt tokens: {len(ids)}, anchor (target greedy next token) {anchor} {tok.decode([anchor])!r}",
          flush=True)
    ref = run_draft(args.draft_hf, load_speculators_layers(args.speculators), feats, anchor, tw, head,
                    len(ids), args.slots)
    cpp = run_llamacpp(args.target_gguf, args.draft_gguf, extended, args.slots, args.threads)

    agree = 0
    for i, (r, c) in enumerate(zip(ref, cpp)):
        same = bool(c) and r[0][0] == c[0][0]
        agree += same
        fmt = lambda s: ", ".join(f"{t} {tok.decode([t])!r} {pr:.3f}" for t, pr in s)  # noqa: E731
        print(f"slot {i}: {'same' if same else 'DIFF'}\n  ref   {fmt(r)}\n  llama {fmt(c) if c else '-'}")
    print(json.dumps({"slots": len(ref), "top1_agree": agree,
                      "max_top1_prob_diff": max((abs(r[0][1] - c[0][1]) for r, c in zip(ref, cpp) if c), default=None)}))


if __name__ == "__main__":
    main()
