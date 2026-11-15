# Models

## lcnet100_256_lumascan_v2.onnx

Page corner model. It is DocAligner's `lcnet100_h_e_bifpn_256_fp32.onnx` from [DocAligner](https://github.com/DocsaidLab/DocAligner) by DocsaidLab, licensed under the Apache License 2.0, **modified by LumaScan**: its last layer widened from four output maps to five, and fine-tuned on 2026-11-14 on the app's own marked photos (books, colour books, made edge test pages, handwritten notebook pages), plus made ID cards and empty frames. Training scripts and steps: `tool/corner_model_training/`; what changed from v1 and how it was measured: `docs/edge-model.md`.

- Input `img`: 1 x 3 x 256 x 256, RGB, 0..1 (the photo squeezed to a square).
- Output `heatmap`: 1 x 5 x 128 x 128, values 0..1. Maps 1 to 4: one heatmap per page corner, top left, top right, bottom right, bottom left; with an open book in view a corner can show in two places (one page, or both). Map 5: the page's area, 1 inside the page.
- ONNX opset 16, 4,792,176 bytes, SHA-256 `1a89d683d25ff7e25d67a1e8c11c4606237757f53567ecf660b3378032eb34aa`.

v1 (2026-11-05, four corner heatmaps, 4,780,759 bytes, SHA-256 `1202635004867d6ae98a87bf339c5cddc5dcdb1f5ceab08f2c15da14a490b1f4`) is in git history. The app's reading code still reads a four-map model.

The original model (4,767,987 bytes, SHA-256 `f4117b786e3a18470f3865c93f3c2bd69d9b998edd60f385574a5c665e79594e`, downloaded from the project's published model links on 2026-10-27) is the starting point for training; it is in git history (removed in the change that added this file).

Used by `lib/imaging/onnx_corner_model.dart` for every page outline (camera preview, photo just taken, imports, Auto crop, crop screen, Book mode, ID cards); see `docs/auto-crop.md`.
