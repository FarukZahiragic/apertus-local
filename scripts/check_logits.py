#!/usr/bin/env python3
"""Compare a converted Apertus v1.5 GGUF against the reference implementation.

The reference is the Swiss AI transformers fork used by the official vLLM image
(github.com/swiss-ai/transformers @ 3797303, model `apertus1p5`). Decoder layers are
run one at a time with weights streamed from the safetensors files, so the 8B model
fits in about 3 GB of RAM (slow, but only one prompt is evaluated).

Checks: tokenization (HF tokenizer vs llama.cpp), last-token logits over the
131,072-entry output vocabulary (NMSE, top-1, top-10 overlap, KL), and that the
non-text tokens are masked by llama.cpp.

Usage (run with the reference venv, see docs/IO.md):
  .venv-ref/bin/python scripts/check_logits.py --hf-dir models/hf/Apertus-v1.5-8B \
      --gguf models/apertus-v1.5-8b-Q4_K_M.gguf [--prompt TEXT]
"""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import torch
from safetensors import safe_open
from tokenizers import Tokenizer
from transformers import AutoConfig
from transformers.models.apertus1p5.modeling_apertus1p5 import (
    Apertus1p5TextDecoderLayer,
    Apertus1p5TextRMSNorm,
    Apertus1p5TextRotaryEmbedding,
)

REPO_ROOT = Path(__file__).resolve().parent.parent
PREFIX = "model.language_model."


class Weights:
    def __init__(self, hf_dir: Path):
        index = hf_dir / "model.safetensors.index.json"
        if index.exists():
            weight_map = json.loads(index.read_text())["weight_map"]
        else:
            weight_map = {}
            for f in hf_dir.glob("*.safetensors"):
                with safe_open(f, "pt") as h:
                    weight_map.update({k: f.name for k in h.keys()})
        self.files = {k: hf_dir / v for k, v in weight_map.items()}

    def get(self, name: str) -> torch.Tensor:
        with safe_open(self.files[name], "pt") as h:
            return h.get_tensor(name)

    def rows(self, name: str, ids: list[int]) -> torch.Tensor:
        with safe_open(self.files[name], "pt") as h:
            sl = h.get_slice(name)
            return torch.stack([sl[i : i + 1][0] for i in ids])

    def prefixed(self, prefix: str) -> dict[str, torch.Tensor]:
        return {k[len(prefix):]: self.get(k) for k in self.files if k.startswith(prefix)}


def run_llamacpp(gguf: Path, prompt: str, threads: int) -> tuple[np.ndarray, list[int]]:
    build = REPO_ROOT / "vendor/llama.cpp/build"
    debug = build / "bin/llama-debug"
    if not debug.exists():
        subprocess.run(["cmake", "--build", str(build), "--target", "llama-debug", "-j"], check=True)
    with tempfile.TemporaryDirectory() as out:
        subprocess.run(
            [str(debug), "-m", str(gguf), "-p", prompt, "-t", str(threads), "--save-logits",
             "--logits-output-dir", out, "-c", "512"],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        logits = np.fromfile(Path(out) / f"llamacpp-{gguf.stem}.bin", dtype=np.float32)
        tokens = np.fromfile(Path(out) / f"llamacpp-{gguf.stem}-tokens.bin", dtype=np.int32)
    return logits, tokens.tolist()


@torch.no_grad()
def run_reference(hf_dir: Path, ids: list[int]) -> np.ndarray:
    config = AutoConfig.from_pretrained(hf_dir).text_config
    config._attn_implementation = "eager"
    w = Weights(hf_dir)
    n = len(ids)

    h = w.rows(PREFIX + "embed_tokens.weight", ids).float().unsqueeze(0)
    pos = torch.arange(n).unsqueeze(0)
    cos, sin = Apertus1p5TextRotaryEmbedding(config)(h, pos)
    mask = torch.full((n, n), float("-inf")).triu(1)[None, None]

    for i in range(config.num_hidden_layers):
        layer = Apertus1p5TextDecoderLayer(config, i)
        layer.load_state_dict(w.prefixed(f"{PREFIX}layers.{i}."), strict=True)
        layer.float()
        h = layer(h, attention_mask=mask, position_embeddings=(cos, sin), position_ids=pos)
        print(f"  reference layer {i + 1}/{config.num_hidden_layers}", end="\r", flush=True)
    print()

    norm = Apertus1p5TextRMSNorm(config.hidden_size, eps=config.rms_norm_eps)
    norm.load_state_dict({"weight": w.get(PREFIX + "norm.weight")})
    last = norm.float()(h)[0, -1]

    head = w.get("lm_head.weight")
    logits = torch.cat([chunk.float() @ last for chunk in head.split(16384)])
    return logits.numpy()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--hf-dir", type=Path, required=True)
    p.add_argument("--gguf", type=Path, required=True)
    p.add_argument("--prompt", default="The capital of Switzerland is")
    p.add_argument("-t", "--threads", type=int, default=4)
    args = p.parse_args()

    cpp_logits, cpp_ids = run_llamacpp(args.gguf, args.prompt, args.threads)
    hf_ids = Tokenizer.from_file(str(args.hf_dir / "tokenizer.json")).encode(
        args.prompt, add_special_tokens=False).ids
    text_ids = cpp_ids[1:] if cpp_ids[:1] == [1] and hf_ids[:1] != [1] else cpp_ids
    print(f"tokens llama.cpp: {cpp_ids}")
    print(f"tokens HF:        {hf_ids}  match={text_ids == hf_ids}")

    ref = run_reference(args.hf_dir, cpp_ids)
    n_out = ref.shape[0]
    cpp, tail = cpp_logits[:n_out], cpp_logits[n_out:]

    def softmax(x):
        e = np.exp(x - x.max())
        return e / e.sum()

    p_ref, p_cpp = softmax(ref.astype(np.float64)), softmax(cpp.astype(np.float64))
    top_ref, top_cpp = np.argsort(-ref)[:10], np.argsort(-cpp)[:10]
    result = {
        "gguf": args.gguf.name,
        "n_vocab_out": n_out,
        "n_vocab_in": int(cpp_logits.shape[0]),
        "non_text_logits_masked": bool(tail.size == 0 or tail.max() < -1e30),
        "tokens_match": text_ids == hf_ids,
        "nmse": float(np.mean((cpp - ref) ** 2) / np.mean(ref ** 2)),
        "max_abs_diff": float(np.abs(cpp - ref).max()),
        "top1_match": bool(top_ref[0] == top_cpp[0]),
        "top10_overlap": len(set(top_ref) & set(top_cpp)),
        "kl_ref_cpp": float(np.sum(p_ref * (np.log(p_ref + 1e-30) - np.log(p_cpp + 1e-30)))),
        "top5_ref": top_ref[:5].tolist(),
        "top5_cpp": top_cpp[:5].tolist(),
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
