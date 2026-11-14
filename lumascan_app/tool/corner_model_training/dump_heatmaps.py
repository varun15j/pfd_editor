"""Writes a model's raw output maps for every marked photo, as a test fixture.

The ONNX model cannot run inside `flutter test` (no native library there),
so the Dart tests that score the page outline read the model's maps from
these files instead and run the app's own reading code on them.

Usage: python3 dump_heatmaps.py MODEL OUT_STEM [ABOUT]
  MODEL     an .onnx file, or a .pt module saved by train.py
  OUT_STEM  writes OUT_STEM.json (index, marks) and OUT_STEM.bin.gz (maps)

Each photo is decoded at 640 px on its longest side, as the app does for a
photo, and squeezed to the model's 256 x 256 input. The maps are stored as
bytes (0..255 for 0..1), channel by channel, row by row, photo by photo in
the order of the index.
"""
import gzip, json, os, sys
import cv2, numpy as np
from data import all_samples, odds_samples, is_val, prep, R

def runner(path):
    if path.endswith('.onnx'):
        import onnxruntime as ort
        so = ort.SessionOptions(); so.intra_op_num_threads = 2
        s = ort.InferenceSession(path, so)
        return lambda x: s.run(None, {'img': x[None]})[0][0]
    import torch
    net = torch.load(path, weights_only=False).eval()
    def f(x):
        with torch.no_grad(): return net(torch.from_numpy(x)[None])[0].numpy()
    return f

def main():
    model, stem = sys.argv[1], sys.argv[2]
    about = sys.argv[3] if len(sys.argv) > 3 else os.path.basename(model)
    run = runner(model)
    marked = all_samples()
    samples = [(f, qs, g, is_val(i)) for i, (f, qs, g) in enumerate(marked)]
    samples += [(f, qs, 'odds', True) for f, qs, _ in odds_samples()]
    photos, blob, shape = [], bytearray(), None
    for f, qs, g, held in samples:
        im = cv2.cvtColor(cv2.imread(f), cv2.COLOR_BGR2RGB)
        s = 640 / max(im.shape[:2])
        if s < 1: im = cv2.resize(im, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
        maps = run(prep(im))
        shape = maps.shape
        blob += np.clip(np.round(maps * 255), 0, 255).astype(np.uint8).tobytes()
        photos.append({
            'file': os.path.relpath(f, R).replace(os.sep, '/'),
            'group': g,
            # Every 4th marked photo, and the odds book photos: a fair test
            # only for a model trained without them (train.py ALL=0).
            'heldBack': bool(held),
            'marks': [np.round(np.asarray(q, float), 4).tolist() for q in qs],
        })
    # One photo a line, so a change shows up as a small diff.
    head = json.dumps({'about': about, 'channels': int(shape[0]), 'size': int(shape[1])})
    rows = ',\n'.join('  ' + json.dumps(p, separators=(',', ':')) for p in photos)
    open(stem + '.json', 'w').write(head[:-1] + ', "photos": [\n' + rows + '\n]}\n')
    with gzip.GzipFile(stem + '.bin.gz', 'wb', mtime=0) as z: z.write(bytes(blob))
    print(len(photos), 'photos', shape, os.path.getsize(stem + '.bin.gz'), 'bytes')

if __name__ == '__main__':
    main()
