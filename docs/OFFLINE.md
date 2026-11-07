# Offline check

Goal: show that Apertus answers with **no network at all**, through both the web UI and
the OpenAI-compatible API. Do the online preparation first, then cut the network.

## 1. Prepare while online

```bash
scripts/setup_llamacpp.sh                                  # builds llama-server with the web UI embedded
ls -lh models/apertus-v1.5-8b-Q4_K_M.gguf                  # model file in place (README step 2)
python3 -m venv .venv-client && .venv-client/bin/pip install openai
```

## 2. Disable networking

```bash
nmcli networking off                                       # Wi-Fi and Ethernet off (Ubuntu desktop)
nmcli networking                                           # prints "disabled"
curl -sm 3 https://huggingface.co || echo "no network"     # prints "no network"
```

Alternatively, switch on airplane mode or unplug the cable.

## 3. Serve and use it

```bash
scripts/serve.sh
```

- Web UI: open <http://127.0.0.1:8080/> in a browser and ask a question. The UI is
  compiled into `llama-server`; it loads no external scripts, fonts or CDNs.
- API, from a second terminal:

```bash
.venv-client/bin/python examples/openai_client.py "In two sentences, what is Apertus?"
.venv-client/bin/python examples/openai_client.py --file docs/HARDWARE.md "How much RAM does the laptop have?"
```

- The server only listens on localhost and has no outbound connections:

```bash
ss -tnp | grep llama-server       # only 127.0.0.1:8080 connections from local clients
```

## 4. Stronger proof without touching the system network

Run the server and client inside a network namespace that has nothing but loopback (no
root needed on Ubuntu 24.04 with unprivileged user namespaces; needs `iproute2`):

```bash
unshare -rn bash -c '
  ip link set lo up
  curl -sm 3 https://huggingface.co || echo "no network"
  scripts/serve.sh > /tmp/llama-server.log 2>&1 &
  until curl -sf 127.0.0.1:8080/health; do sleep 1; done; echo
  .venv-client/bin/python examples/openai_client.py "Say hello in French."
  kill %1'
```

If Ubuntu blocks unprivileged namespaces (AppArmor), run
`sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0` for the test, or use step 2.

## 5. Reliability run (before the workshop)

```bash
.venv-client/bin/python examples/openai_client.py --repeat 50 --max-tokens 64 "Give one tip for staying safe online."
```

It exits non-zero if any request fails or times out (300 s per request).

## 6. Re-enable networking

```bash
nmcli networking on
```

## What to show at the workshop

Chat and document Q&A. Native tool calling with Apertus 1.5 is unreliable (see the
reference in [ARCHITECTURE.md](ARCHITECTURE.md#references)), so do not demo agents.
Recorded prompt processing is roughly 18 to 23 tok/s on the laptop: allow about
1.5 to 2 minutes for a 2,000-token document before the first answer token appears.

## Native participant checks

On macOS, use the Wi-Fi menu to turn Wi-Fi off and disconnect Ethernet and other
network adapters. Start the launcher again and reload the local page. Ubuntu's
`nmcli`, `ss` and network namespaces above are Linux-specific; on macOS use
`lsof -nP -iTCP:8080` to inspect local listening connections.

For a prepared package or checkout, use the dependency-free maintainer check:

```bash
scripts/validate_local.sh --repeat 50 --max-tokens 16 --report dist/offline-check.json
```

It checks health, the embedded UI and its assets, document Q&A, streaming and final
usage. It does not turn networking off or claim network isolation. The Nov 7 local
extracted-package run passed all 50 requests at a 4K context; the network-disabled
browser rehearsal remains pending. See [VALIDATION.md](VALIDATION.md).

Linux native CI also starts the server from local weights inside a fresh network
namespace with only loopback enabled. It rejects external connectivity, runs the
UI/API/document checks and renders the real UI in the runner's existing headless
browser. This verifies software behavior in a hosted VM; participant laptop and
physical Mac rehearsals remain separate acceptance checks. It does not disconnect
the CI host or the user's machine.
