# Models

## lcnet100_h_e_bifpn_256_fp32.onnx

Page corner model from [DocAligner](https://github.com/DocsaidLab/DocAligner) by DocsaidLab, licensed under the Apache License 2.0 (unchanged; downloaded from the project's published model links on 2026-10-27).

- Input `img`: 1 x 3 x 256 x 256, RGB, 0..1.
- Output `heatmap`: 1 x 4 x 128 x 128, one heatmap per page corner.
- 4,767,987 bytes, SHA-256 `f4117b786e3a18470f3865c93f3c2bd69d9b998edd60f385574a5c665e79594e`.

Used by `lib/imaging/onnx_corner_model.dart` in the camera preview; see `docs/auto-crop.md`.
