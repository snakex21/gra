# Local AI research dependencies

The Bekko ONNX rendering adapter follows the documented public algorithm from [hotchpotch/bekko-system-one](https://github.com/hotchpotch/bekko-system-one/tree/0fccbb8568b67d47745d820319fe9a4a04e7fa95/browser), whose source repository is MIT licensed. Bekko released weights do not currently have an assigned licence; they are not distributed by this repository.

Runtime packages are downloaded into ignored `data/ai`. Their original wheel licence files remain in the installation: ONNX Runtime MIT, Hugging Face Tokenizers Apache-2.0, NumPy BSD-3-Clause with bundled dependency notices. The installers retain downloaded llama.cpp MIT and model licence texts. Qwen models use Apache-2.0; LFM2.5 uses Liquid AI LFM Open License 1.0. Exact revisions, files, sizes and SHA256 digests are in the pin JSON files. No weights or binaries belong in commits.
