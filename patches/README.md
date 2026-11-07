# llama.cpp patches

`scripts/setup_llamacpp.sh` resets the llama.cpp checkout to the pinned commit and
applies these patches in order. Keep each one minimal; drop it once the pinned branch
contains the change.

| Patch | Why |
| --- | --- |
| `0001-apertus-expose-layer-inputs.patch` | DSpark drafts read the target's hidden states at the inputs of layers 1, 8, 15, 22 and 29. The Apertus graph did not record them (`res->t_layer_inp[il]`), so `--spec-type draft-dspark` aborted with `t_layer_inp[il] != nullptr`. Same one-line hook as `qwen3.cpp` and `llama.cpp`. |
| `0002-dspark-convert-apertus-drafts.patch` | Converts the Speculators `DSparkDraftModel` trained for Apertus v1.5. (1) Identity `d2t` when `draft_vocab_size` (131,072) equals the target's `output_vocab_size`; the runtime then shares the target's 131,072-row output head and 266,752-row embedding instead of storing copies. (2) Emit llama3 `rope_freqs` for the draft, which the Qwen3 path dropped silently. (3) Write `attention.causal = true`: Speculators trains sliding-window layers block-causal unless `sliding_window_non_causal` is set, while llama.cpp defaults to a non-causal block. (4) `Apertus1p5Model.set_vocab` calls `LlamaModel.set_vocab` explicitly, because DFlash/DSpark drafts run it on their own instance and zero-argument `super()` failed. |
