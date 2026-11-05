# llama.cpp patches

`scripts/setup_llamacpp.sh` resets the llama.cpp checkout to the pinned commit and
applies these patches in order. Keep each one minimal; drop it once the pinned branch
contains the change.

| Patch | Why |
| --- | --- |
| `0001-apertus-expose-layer-inputs.patch` | DSpark drafts read the target's hidden states at the inputs of layers 1, 8, 15, 22 and 29. The Apertus graph did not record them (`res->t_layer_inp[il]`), so `--spec-type draft-dspark` aborted with `t_layer_inp[il] != nullptr`. Same one-line hook as `qwen3.cpp` and `llama.cpp`. |
