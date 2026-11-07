#!/usr/bin/env python3
"""Talk to the local llama-server through the official OpenAI Python client.

Usage:
  python examples/openai_client.py "What is Apertus?"
  python examples/openai_client.py --file report.txt "Summarize this document in 5 bullet points."
  python examples/openai_client.py --repeat 50 "Say hello."    # reliability run

Requires `pip install openai` (do it while online). The server is scripts/serve.sh.
"""
import argparse
import sys
import time

from openai import OpenAI


def ask(client: OpenAI, model: str, messages: list[dict], max_tokens: int, stream: bool) -> tuple[str, int | None]:
    if not stream:
        r = client.chat.completions.create(model=model, messages=messages, max_tokens=max_tokens)
        return r.choices[0].message.content or "", r.usage.completion_tokens if r.usage else None
    parts, n = [], None
    for chunk in client.chat.completions.create(
        model=model, messages=messages, max_tokens=max_tokens, stream=True,
        stream_options={"include_usage": True},
    ):
        delta = chunk.choices[0].delta.content if chunk.choices else None
        if delta:
            parts.append(delta)
            print(delta, end="", flush=True)
        if chunk.usage:
            n = chunk.usage.completion_tokens
    print(flush=True)
    return "".join(parts), n


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("prompt")
    p.add_argument("--file", help="text file to answer questions about")
    p.add_argument("--base-url", default="http://127.0.0.1:8080/v1")
    p.add_argument("--max-tokens", type=int, default=256)
    p.add_argument("--repeat", type=int, default=1, help="send the request N times and report failures")
    p.add_argument("--timeout", type=float, default=300, help="seconds per request")
    args = p.parse_args()

    client = OpenAI(base_url=args.base_url, api_key="local", timeout=args.timeout, max_retries=0)
    model = client.models.list().data[0].id

    user = args.prompt
    if args.file:
        with open(args.file, encoding="utf-8") as f:
            user = f"Document:\n\n{f.read()}\n\nQuestion: {args.prompt}"
    messages = [
        {"role": "system", "content": "You are a helpful assistant. Answer concisely."},
        {"role": "user", "content": user},
    ]

    failures = 0
    for i in range(args.repeat):
        start = time.time()
        try:
            _, n = ask(client, model, messages, args.max_tokens, stream=args.repeat == 1)
        except Exception as e:  # noqa: BLE001 - report and keep going in reliability runs
            failures += 1
            print(f"[{i + 1}/{args.repeat}] error: {e}", file=sys.stderr)
            continue
        dt = time.time() - start
        count = f"{n} tokens" if n is not None else "response"
        print(f"[{i + 1}/{args.repeat}] {model}: {count} in {dt:.1f} s", file=sys.stderr)

    if args.repeat > 1:
        print(f"{args.repeat - failures}/{args.repeat} requests succeeded", file=sys.stderr)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
