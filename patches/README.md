# llama.cpp patches

`scripts/setup_llamacpp.sh` resets the llama.cpp checkout to the pinned commit and
applies these patches in order. Keep each one minimal; drop it once the pinned branch
contains the change.

`0005-apertus-image-token-budget.patch` makes Apertus honor `--image-min-tokens`
and `--image-max-tokens`. The unpatched path always used the model's metadata,
allowing a phone photo to use thousands of tokens and excessive CPU memory.
The launcher defaults to 256 image codes (plus row and framing tokens), with
an optional budget up to 1024. The source's resize and normalization remain intact.

`0004-windows-arm-cpu-variants.patch` adds the missing Windows ARM64 build entries
for the pin's existing Windows CPU feature detection. It includes ARMv8.0 and
optional dot-product, FP16 and I8MM variants. The existing runtime scoring checks
the OS-reported features before choosing a variant; no build-host tuning or
Snapdragon model whitelist is used. Tensor math and model loading are unchanged.

| Patch | Why |
| --- | --- |
| `0001-apertus-expose-layer-inputs.patch` | DSpark drafts read the target's hidden states at the inputs of layers 1, 8, 15, 22 and 29. The Apertus graph did not record them (`res->t_layer_inp[il]`), so `--spec-type draft-dspark` aborted with `t_layer_inp[il] != nullptr`. Same one-line hook as `qwen3.cpp` and `llama.cpp`. |
| `0002-dspark-convert-apertus-drafts.patch` | Converts the Speculators `DSparkDraftModel` trained for Apertus v1.5. (1) Identity `d2t` when `draft_vocab_size` (131,072) equals the target's `output_vocab_size`; the runtime then shares the target's 131,072-row output head and 266,752-row embedding instead of storing copies. (2) Emit llama3 `rope_freqs` for the draft, which the Qwen3 path dropped silently. (3) Write `attention.causal = true`: Speculators trains sliding-window layers block-causal unless `sliding_window_non_causal` is set, while llama.cpp defaults to a non-causal block. (4) `Apertus1p5Model.set_vocab` calls `LlamaModel.set_vocab` explicitly, because DFlash/DSpark drafts run it on their own instance and zero-argument `super()` failed. |
| `0003-eagle3-1-apertus.patch` | Runs the EAGLE 3.1 draft trained with TorchSpec for Apertus v1.5. (1) `fc_norm`: one RMSNorm per target hidden state before `fc`, stored as a `[4096, 3]` `enc.output_norm` tensor (llama.cpp only had `norm_before_fc`, a single norm over all 12,288 values). (2) `norm_output`: the next draft step reads the post-norm hidden state, as in training. (3) Converter: identity `d2t` and the target's full vocabulary for tokenization when the draft's 131,072-token vocabulary equals the target's `output_vocab_size`. |
