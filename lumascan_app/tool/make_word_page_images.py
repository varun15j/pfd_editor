#!/usr/bin/env python3
"""Makes the OCR test images in sample_photos/word_pages/ from the Word
feature test document (test_docs/Word_Feature_Test.docx, 139 features).

Each page of the document becomes one picture, as if it had been scanned,
so the OCR to Word path (luma_docx WordWriter) can be tried on pages whose
content is known. The text on each page and where every line sits go to
sample_photos/word_pages/expected.json:

    {"pages": [{"file", "page", "size": [w, h] in points, "blocks": [{"box": [l, t, r, b],
                "lines": [{"text", "box": [l, t, r, b]}]}]}]}

Boxes are fractions of the page. test/ocr_word_builder_test.dart turns the
blocks into an OcrLayout (what a perfect OCR engine would report) and
checks the Word file built from it.

Run from lumascan_app/ (needs LibreOffice, poppler-utils and Pillow):

    python3 tool/make_word_page_images.py path/to/Word_Feature_Test.docx
"""

import glob
import json
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image

OUT = 'sample_photos/word_pages'
DPI = 150
NS = '{http://www.w3.org/1999/xhtml}'


def layout(pdf):
    """Blocks and lines of every page, from pdftotext -bbox-layout."""
    xml = subprocess.run(['pdftotext', '-bbox-layout', pdf, '-'], capture_output=True, text=True, check=True).stdout
    pages = []
    for page in ET.fromstring(xml).iter(f'{NS}page'):
        w, h = float(page.get('width')), float(page.get('height'))

        def box(e):
            return [round(float(e.get('xMin')) / w, 4), round(float(e.get('yMin')) / h, 4),
                    round(float(e.get('xMax')) / w, 4), round(float(e.get('yMax')) / h, 4)]

        blocks = []
        size = [round(w, 1), round(h, 1)]
        for b in page.iter(f'{NS}block'):
            lines = []
            for line in b.iter(f'{NS}line'):
                text = ' '.join(word.text or '' for word in line.iter(f'{NS}word')).strip()
                if text:
                    lines.append({'text': text, 'box': box(line)})
            if lines:
                blocks.append({'box': box(b), 'lines': lines})
        pages.append((size, blocks))
    return pages


def main():
    docx = sys.argv[1] if len(sys.argv) > 1 else '../test_docs/Word_Feature_Test.docx'
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(['soffice', '--headless', '--norestore', '--convert-to', 'pdf', '--outdir', tmp, docx],
                       check=True, capture_output=True)
        pdf = glob.glob(f'{tmp}/*.pdf')[0]
        subprocess.run(['pdftoppm', '-r', str(DPI), '-png', pdf, f'{tmp}/p'], check=True)
        pngs = sorted(glob.glob(f'{tmp}/p-*.png'))
        pages = layout(pdf)
        out = []
        for i, png in enumerate(pngs):
            name = f'page_{i + 1:02d}.jpg'
            Image.open(png).convert('RGB').save(f'{OUT}/{name}', quality=80, optimize=True)
            out.append({'file': name, 'page': i + 1, 'size': pages[i][0], 'blocks': pages[i][1]})
    with open(f'{OUT}/expected.json', 'w') as f:
        json.dump({'source': os.path.basename(docx), 'dpi': DPI, 'pages': out}, f, ensure_ascii=False)
        f.write('\n')
    print(f'{len(out)} pages written to {OUT}')


if __name__ == '__main__':
    main()
