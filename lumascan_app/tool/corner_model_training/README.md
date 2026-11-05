# Corner model training

Fine-tunes DocAligner's LCNet corner model (`assets/models/`) on the app's own marked photos. Runs on a CPU: no GPU needed. About 45 minutes for 1500 steps on a 4-core cloud machine.

## Data

66 photos with page corners marked by hand:

| Set | Photos | Corners from |
| --- | --- | --- |
| Books (`sample_photos/book/`) | 20 | `test/book_detection_test.dart` |
| Colour book (`sample_photos/colour_book/`) | 22 | `test/colour_book_detection_test.dart` |
| Made edge test pages (`sample_photos/edge/`) | 19 | `sample_photos/edge/corners.json` |
| Handwritten notebook (`sample_photos/0*.jpg`) | 5 | `NOTEBOOK` in `data.py` |

Where a photo lists more than one right outline, the first is trained on. The 6 odds book photos (`sample_scan_img/odds_book/`, marks in `test/edge_samples_test.dart`) are never trained on and serve as a fair test.

Each training photo is also bent, turned, zoomed, flipped, recoloured, blurred and noised at random. A quarter of the samples are pages (and made ID cards) pasted on other backgrounds, and about one in eight is an empty frame with no page, so the model learns to stay quiet when there is nothing to find (without these it drew a page on a blank wall and moved ID card edges).

## Steps

```bash
pip install torch onnx onnx2torch onnxruntime opencv-python-headless
cd tool/corner_model_training
python3 convert.py <the original DocAligner ONNX> base.pt   # from git history, see assets/models/README.md
python3 train.py 0 1500 test.pt      # keeps every 4th photo back, prints scores on them every 250 steps
python3 train.py 1 1500 final.pt     # trains on all 66
python3 export.py final.pt ../../assets/models/lcnet100_256_lumascan_v1.onnx
```

`pipeline.py` scores the whole crop as the app does it (the model when every corner peak is at least `minCornerConfidence`, else the hand-made detector). It needs the hand-made detector's outlines in `detector.json`, written by a throwaway flutter test that runs `detectPageQuad(photo, smart: true/false)` on each photo decoded at 640 px.

## Results (2026-11-05)

Overlap with the hand-marked page, as a whole crop. "Today" is the stock model at 0.8 with the hand-made detector as fallback (Pro); Basic never used the model.

| Photos | Today Pro | Today Basic | Trained, Pro | Trained, Basic |
| --- | --- | --- | --- | --- |
| 16 held back (model trained on the other 50) | 0.85 | 0.68 | 0.89 | 0.88 |
| 6 odds book photos (never trained on) | 0.82 | 0.70 | 0.85 | 0.85 |
| All 66 (final model, seen in training) | 0.88 | 0.66 | 0.95 | 0.93 |

The model alone on held-back photos: 0.34 → 0.88. ID cards (`id_mask_test` sample cards): 0.98 before and after. More real photos, especially handwritten notebook pages and open books, are the best way to improve it further.
