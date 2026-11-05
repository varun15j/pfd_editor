# Models

## lcnet100_256_lumascan_v1.onnx

Page corner model. It is DocAligner's `lcnet100_h_e_bifpn_256_fp32.onnx` from [DocAligner](https://github.com/DocsaidLab/DocAligner) by DocsaidLab, licensed under the Apache License 2.0, **modified by LumaScan**: fine-tuned on 2026-11-05 on the app's own marked photos (books, colour books, made edge test pages, handwritten notebook pages), plus made ID cards and empty frames. Training scripts and steps: `tool/corner_model_training/`.

- Input `img`: 1 x 3 x 256 x 256, RGB, 0..1 (the photo squeezed to a square).
- Output `heatmap`: 1 x 4 x 128 x 128, one heatmap per page corner: top left, top right, bottom right, bottom left.
- ONNX opset 16, 4,780,759 bytes, SHA-256 `1202635004867d6ae98a87bf339c5cddc5dcdb1f5ceab08f2c15da14a490b1f4`.

The original model (4,767,987 bytes, SHA-256 `f4117b786e3a18470f3865c93f3c2bd69d9b998edd60f385574a5c665e79594e`, downloaded from the project's published model links on 2026-10-27) is the starting point for training; it is in git history (removed in the change that added this file).

Used by `lib/imaging/onnx_corner_model.dart` for every page outline (camera preview, photo just taken, imports, Auto crop, crop screen, Book mode, ID cards); see `docs/auto-crop.md`.
