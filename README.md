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

The steps are added as each phase lands (see [docs/ROADMAP.md](docs/ROADMAP.md)).

## Docs

- [AGENTS.md](AGENTS.md): working rules for contributors and agents
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): components, data flow, why llama.cpp
- [docs/IO.md](docs/IO.md): model files, server endpoint, benchmark format
- [docs/ROADMAP.md](docs/ROADMAP.md): phases and status
- [docs/HARDWARE.md](docs/HARDWARE.md): laptop specs and speed expectations
- [benchmarks/results.md](benchmarks/results.md): all benchmark runs
