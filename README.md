# apertus-local

Run [Apertus-v1.5-8B](https://huggingface.co/swiss-ai/Apertus-v1.5-8B) on a regular
laptop with no GPU and no internet during inference, using
[llama.cpp](https://github.com/ggml-org/llama.cpp). Built for the hands-on deployment
session of the Nov 10 NGO workshop: private data never leaves the machine, and it keeps
working with poor connectivity.

Reference machine: Intel i5-1135G7, 16 GB RAM, Ubuntu 24.04 (see
[docs/HARDWARE.md](docs/HARDWARE.md)). Expect about 6 to 8 tokens/s generation.

## Quickstart

Prerequisites (Ubuntu 24.04):

```bash
sudo apt install -y git cmake build-essential python3 curl
git clone https://github.com/FarukZahiragic/apertus-local && cd apertus-local
```

### 1. Build llama.cpp and run a smoke test

```bash
scripts/setup_llamacpp.sh        # pinned llama.cpp, CPU build with -march=native (~10 min)
scripts/get_model.sh             # Qwen2.5-1.5B-Instruct Q4_K_M (1.1 GB), sha256-checked
vendor/llama.cpp/build/bin/llama-cli -m models/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  -t 4 -n 64 -st -p "In one sentence, why does running a model locally help privacy?"
scripts/bench.sh -m models/qwen2.5-1.5b-instruct-q4_k_m.gguf -t 4 --notes "baseline"
```

`bench.sh` appends a row to [benchmarks/results.md](benchmarks/results.md); on the
laptop the Hardware column is filled in as `laptop i5-1135G7` automatically.

### 2. Get Apertus-v1.5-8B as a 4-bit GGUF

The conversion runs on a cloud VM, not the laptop (it needs about 40 GB of disk); see
[docs/IO.md](docs/IO.md#conversion-cloud-vm). On the laptop, put only the Q4_K_M file
(5.3 GiB) into `models/`, by `scp`, USB stick, or from a private Hugging Face repo:

```bash
HF_TOKEN=... scripts/get_model.sh <hf-user>/apertus-v1.5-8b-GGUF apertus-v1.5-8b-Q4_K_M.gguf
sha256sum models/apertus-v1.5-8b-Q4_K_M.gguf     # e8ddf308...0a90eb8c (full value in docs/IO.md)
vendor/llama.cpp/build/bin/llama-cli -m models/apertus-v1.5-8b-Q4_K_M.gguf \
  -t 4 -c 4096 -n 128 -st -p "Explain in two sentences what Apertus is."
scripts/bench.sh -m models/apertus-v1.5-8b-Q4_K_M.gguf -t 4 --name Apertus-v1.5-8B
```

### 3. Serve it offline (the workshop demo)

```bash
scripts/serve.sh                      # http://127.0.0.1:8080/ web UI, /v1 OpenAI API
python3 -m venv .venv-client && .venv-client/bin/pip install openai   # once, while online
.venv-client/bin/python examples/openai_client.py "What is Apertus?"
```

Defaults: 4 threads, 4,096-token context (`CTX=8192 scripts/serve.sh` for longer
documents), one slot. How to prove it works with networking disabled:
[docs/OFFLINE.md](docs/OFFLINE.md).

Further steps are added as each phase lands (see [docs/ROADMAP.md](docs/ROADMAP.md)).

## Docs

- [AGENTS.md](AGENTS.md): working rules for contributors and agents
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): components, data flow, why llama.cpp
- [docs/IO.md](docs/IO.md): model files, server endpoint, benchmark format
- [docs/ROADMAP.md](docs/ROADMAP.md): phases and status
- [docs/HARDWARE.md](docs/HARDWARE.md): laptop specs and speed expectations
- [docs/OFFLINE.md](docs/OFFLINE.md): verifying the demo with networking disabled
- [benchmarks/results.md](benchmarks/results.md): all benchmark runs
