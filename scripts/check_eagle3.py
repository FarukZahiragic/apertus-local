#!/usr/bin/env python3
"""Compare the converted EAGLE 3.1 draft with the reference implementation.

Reference: the EAGLE 3.1 math of the TorchSpec trainer the draft was trained with
(github.com/lightseekorg/TorchSpec @ 6c042a8, models/draft/llama3_eagle.py and
models/eagle3.py), which the Swiss AI vLLM fork serves identically
(llama_eagle3.py @ a601a9d). Written out in plain PyTorch because the TorchSpec module
needs flash/flex-attention training kernels:
  - features: fc(concat(fc_norm[i](target layer input i))) for target layers 2, 16, 29;
  - layer: h + attn(concat(input_layernorm(embed), hidden_norm(h))), then + mlp;
  - logits: lm_head(norm(h)); with norm_output the next step reads norm(h).

For one chat prompt (thinking off) the script runs the reference target, takes its
greedy next token as the anchor, drafts --steps tokens autoregressively, and compares
them with llama.cpp's first draft-eagle3 draft on the same prompt (see check_dspark.py).

Usage (reference venv, see docs/IO.md):
  .venv-ref/bin/python scripts/check_eagle3.py --target-hf models/hf/Apertus-v1.5-8B \\
      --draft-hf models/hf/Apertus-v1.5-8B-EAGLE3.1-e10-thinking-off \\
      --target-gguf models/apertus-v1.5-8b-F16.gguf --draft-gguf models/apertus-v1.5-8b-eagle3.1-e10-F16.gguf
"""
import argparse
import json
import sys
from pathlib import Path

import torch
from safetensors import safe_open
from transformers import AutoTokenizer, LlamaConfig
from transformers.models.llama.modeling_llama import LlamaRotaryEmbedding, apply_rotary_pos_emb

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_dspark import run_llamacpp, run_target  # noqa: E402
from check_logits import PREFIX  # noqa: E402


def rms(x, w, eps):
    return x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + eps) * w


@torch.no_grad()
def run_draft(draft_dir: Path, feats, prompt_ids, anchor, tw, steps):
    cfg = json.loads((draft_dir / "config.json").read_text())
    eps, n_head, n_kv, hd = cfg["rms_norm_eps"], cfg["num_attention_heads"], cfg["num_key_value_heads"], cfg["head_dim"]
    d = safe_open(draft_dir / "model.safetensors", "pt")

    def g(name):
        return d.get_tensor(name).float()

    # step-1 rows: target features at prompt position p paired with the embedding of token p+1
    x = torch.cat([rms(f, g(f"fc_norm.{i}.weight"), eps) for i, f in enumerate(feats)], dim=-1)
    hidden = x @ g("fc.weight").T                                 # [n, 4096]
    tokens = prompt_ids[1:] + [anchor]
    rope = LlamaRotaryEmbedding(LlamaConfig(**{k: v for k, v in cfg.items() if k != "architectures"}))
    L = "layers.0."

    def layer(emb, h):
        n = h.shape[0]
        xin = torch.cat([rms(emb, g(L + "input_layernorm.weight"), eps), rms(h, g(L + "hidden_norm.weight"), eps)], -1)
        q = (xin @ g(L + "self_attn.q_proj.weight").T).view(n, n_head, hd).transpose(0, 1)
        k = (xin @ g(L + "self_attn.k_proj.weight").T).view(n, n_kv, hd).transpose(0, 1)
        v = (xin @ g(L + "self_attn.v_proj.weight").T).view(n, n_kv, hd).transpose(0, 1)
        cos, sin = rope(xin, torch.arange(n).unsqueeze(0))
        q, k = apply_rotary_pos_emb(q[None], k[None], cos, sin)
        k, v = k[0].repeat_interleave(n_head // n_kv, 0), v.repeat_interleave(n_head // n_kv, 0)
        att = (q[0] @ k.transpose(1, 2)) / hd ** 0.5 + torch.full((n, n), float("-inf")).triu(1)
        o = (att.softmax(-1) @ v).transpose(0, 1).reshape(n, -1) @ g(L + "self_attn.o_proj.weight").T
        h1 = h + o
        m = rms(h1, g(L + "post_attention_layernorm.weight"), eps)
        m = (torch.nn.functional.silu(m @ g(L + "mlp.gate_proj.weight").T) * (m @ g(L + "mlp.up_proj.weight").T))
        return h1 + m @ g(L + "mlp.down_proj.weight").T

    steps_out = []
    for _ in range(steps):
        emb = tw.rows(PREFIX + "embed_tokens.weight", tokens).float()
        pre = layer(emb, hidden)[-1]
        normed = rms(pre, g("norm.weight"), eps)
        logits = normed @ g("lm_head.weight").T
        top = torch.topk(logits, 10)
        probs = torch.softmax(top.values, 0)
        steps_out.append([(int(t), float(p)) for t, p in zip(top.indices[:3], probs[:3])])
        nxt = int(top.indices[0])
        tokens.append(nxt)
        hidden = torch.cat([hidden, (normed if cfg.get("norm_output") else pre)[None]], 0)
    return steps_out


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--target-hf", type=Path, required=True)
    p.add_argument("--draft-hf", type=Path, required=True)
    p.add_argument("--target-gguf", type=Path, required=True)
    p.add_argument("--draft-gguf", type=Path, required=True)
    p.add_argument("--question", default="Give me three tips for writing a clear project report.")
    p.add_argument("-k", "--steps", type=int, default=5)
    p.add_argument("-t", "--threads", type=int, default=4)
    args = p.parse_args()

    tok = AutoTokenizer.from_pretrained(args.target_hf)
    rendered = tok.apply_chat_template([{"role": "user", "content": args.question}], tokenize=False,
                                       add_generation_prompt=True, enable_thinking=False)
    rendered = rendered.removeprefix(tok.bos_token)
    ids = [tok.bos_token_id] + tok.encode(rendered, add_special_tokens=False)

    cfg = json.loads((args.draft_hf / "config.json").read_text())
    feats, anchor, tw, _ = run_target(args.target_hf, ids, cfg["eagle_aux_hidden_state_layer_ids"])
    extended = rendered + tok.decode([anchor])
    if [tok.bos_token_id] + tok.encode(extended, add_special_tokens=False) != ids + [anchor]:
        raise SystemExit("prompt + anchor does not re-tokenize to the same ids; pick another question")
    print(f"prompt tokens: {len(ids)}, anchor (target greedy next token) {anchor} {tok.decode([anchor])!r}",
          flush=True)
    ref = run_draft(args.draft_hf, feats, ids, anchor, tw, args.steps)
    cpp = run_llamacpp(args.target_gguf, args.draft_gguf, extended, args.steps, args.threads,
                       spec_type="draft-eagle3")

    agree = 0
    for i, (r, c) in enumerate(zip(ref, cpp)):
        same = bool(c) and r[0][0] == c[0][0]
        agree += same
        fmt = lambda s: ", ".join(f"{t} {tok.decode([t])!r} {pr:.3f}" for t, pr in s)  # noqa: E731
        print(f"step {i}: {'same' if same else 'DIFF'}\n  ref   {fmt(r)}\n  llama {fmt(c) if c else '-'}")
    print(json.dumps({"steps": len(ref), "top1_agree": agree,
                      "max_top1_prob_diff": max((abs(r[0][1] - c[0][1]) for r, c in zip(ref, cpp) if c), default=None)}))


if __name__ == "__main__":
    main()
