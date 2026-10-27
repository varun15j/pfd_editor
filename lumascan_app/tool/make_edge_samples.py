#!/usr/bin/env python3
"""Makes the edge detection test pages in sample_photos/edge/.

Each picture is a page photographed on a surface, built from real page
content (the KV question papers in sample_docs/, the odds book and book
photos), so the four page corners are known exactly. They go to
sample_photos/edge/corners.json, which test/edge_samples_test.dart reads.

Run from lumascan_app/ (needs Python 3 with Pillow and numpy, and pdftoppm):

    python3 tool/make_edge_samples.py

The output is the same on every run (fixed seeds), so re-running it only
changes the files when this script changes.
"""

import json
import math
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1080, 1440
OUT = 'sample_photos/edge'


# ---------------------------------------------------------------- geometry

def _coeffs(dst, src):
    """Perspective coefficients for Image.transform, mapping each output
    point in [dst] back to the input point in [src]."""
    rows = []
    for (x, y), (u, v) in zip(dst, src):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    a = np.array(rows, dtype=float)
    b = np.array([c for p in src for c in p], dtype=float)
    return np.linalg.solve(a, b).tolist()


def warp(img, dst, size=(W, H)):
    """Draws [img] with its corners at [dst] (TL, TR, BR, BL, in pixels).
    Returns the warped picture and its coverage mask."""
    w, h = img.size
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    c = _coeffs(dst, src)
    out = img.convert('RGB').transform(size, Image.PERSPECTIVE, c, Image.BICUBIC)
    mask = Image.new('L', img.size, 255).transform(size, Image.PERSPECTIVE, c, Image.BILINEAR)
    return out, mask


def unwarp(photo, quad, size):
    """Cuts the page at normalised [quad] out of [photo], straightened."""
    pw, ph = photo.size
    src = [(x * pw, y * ph) for x, y in quad]
    w, h = size
    return photo.transform(size, Image.PERSPECTIVE, _coeffs([(0, 0), (w, 0), (w, h), (0, h)], src), Image.BICUBIC)


def rect(cx, cy, w, h, angle=0.0, squeeze=0.0):
    """Corners of a w x h page centred at (cx, cy), turned by [angle]
    degrees, with the top edge [squeeze] times shorter (camera tilt)."""
    a = math.radians(angle)
    pts = [(-w / 2 * (1 - squeeze), -h / 2), (w / 2 * (1 - squeeze), -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    return [(cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)) for x, y in pts]


def norm(quad):
    return [[round(x / W, 4), round(y / H, 4)] for x, y in quad]


# ------------------------------------------------------------- backgrounds

def _noise(rng, w, h, scale):
    small = rng.random((max(2, h // scale), max(2, w // scale)))
    return np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), dtype=float) / 255


def surface(kind, rng):
    y, x = np.mgrid[0:H, 0:W].astype(float)
    if kind == 'dark_wood' or kind == 'light_wood':
        grain = np.sin((x * 0.03 + 6 * _noise(rng, W, H, 90) + 0.4 * np.sin(y * 0.004)) * 3) * 0.5 + 0.5
        fine = _noise(rng, W, H, 3)
        t = 0.7 * grain + 0.3 * fine
        lo, hi = ((60, 36, 20), (110, 70, 40)) if kind == 'dark_wood' else ((170, 128, 82), (214, 172, 120))
        rgb = [lo[i] + (hi[i] - lo[i]) * t for i in range(3)]
    elif kind == 'concrete':
        t = 0.6 * _noise(rng, W, H, 40) + 0.4 * _noise(rng, W, H, 2)
        rgb = [110 + 50 * t] * 3
    elif kind == 'bedsheet':
        folds = np.sin((x * 0.6 + y) * 0.012 + 3 * _noise(rng, W, H, 200)) * 0.5 + 0.5
        t = 0.8 * folds + 0.2 * _noise(rng, W, H, 2)
        rgb = [212 + 30 * t, 214 + 30 * t, 222 + 28 * t]
    elif kind == 'carpet':
        t = _noise(rng, W, H, 2) * 0.6 + _noise(rng, W, H, 25) * 0.4
        rgb = [120 + 60 * t, 40 + 30 * t, 45 + 30 * t]
    elif kind == 'blue_cloth':
        weave = (np.sin(x * 0.8) * np.sin(y * 0.8)) * 0.5 + 0.5
        t = 0.3 * weave + 0.7 * _noise(rng, W, H, 30)
        rgb = [120 + 40 * t, 160 + 40 * t, 205 + 35 * t]
    elif kind == 'black_desk':
        t = _noise(rng, W, H, 60) * 0.7 + _noise(rng, W, H, 2) * 0.3
        rgb = [22 + 25 * t, 23 + 25 * t, 26 + 25 * t]
    elif kind == 'beige_table':
        t = _noise(rng, W, H, 70) * 0.7 + _noise(rng, W, H, 2) * 0.3
        rgb = [214 + 22 * t, 200 + 22 * t, 176 + 22 * t]
    else:
        raise ValueError(kind)
    return np.stack(rgb, axis=-1)


# ------------------------------------------------------------------ pages

def tint(page, colour, strength=1.0):
    """Prints [page] (dark ink on white) on paper of [colour]."""
    a = np.asarray(page.convert('RGB'), dtype=float) / 255
    c = np.array(colour, dtype=float) / 255
    paper = 1 - strength * (1 - c)
    return Image.fromarray(np.clip(a * paper * 255, 0, 255).astype(np.uint8))


def pdf_page(path, page, tmp):
    stem = os.path.join(tmp, f'p{abs(hash((path, page)))}')
    subprocess.run(['pdftoppm', '-r', '110', '-f', str(page), '-l', str(page), '-png', '-singlefile', path, stem], check=True)
    return Image.open(stem + '.png').convert('RGB')


def odds_page(n, quad):
    names = ['01_post_box', '02_ink_pad_stamp', '03_camera_photos', '04_binoculars', '05_rocket_control_panel', '06_moon_rocket']
    photo = Image.open(f'sample_scan_img/odds_book/{names[n - 1]}.jpg').convert('RGB')
    return unwarp(photo, quad, (760, 1000))


def book_page(name, quad):
    photo = Image.open(f'sample_photos/book/{name}.jpg').convert('RGB')
    page = unwarp(photo, quad, (720, 1000))
    # The book photos are dim; lift the paper to white as a print would be.
    a = np.asarray(page, dtype=float)
    white = np.percentile(a, 92, axis=(0, 1))
    return Image.fromarray(np.clip(a / white * 240, 0, 255).astype(np.uint8))


# --------------------------------------------------------------- the photo

class Photo:
    def __init__(self, kind, seed):
        self.rng = np.random.default_rng(seed)
        self.a = surface(kind, self.rng)

    def shadow(self, quad, dx=14, dy=18, blur=22, depth=0.45):
        m = Image.new('L', (W, H), 0)
        ImageDraw.Draw(m).polygon([(x + dx, y + dy) for x, y in quad], fill=255)
        s = np.asarray(m.filter(ImageFilter.GaussianBlur(blur)), dtype=float) / 255
        self.a *= (1 - depth * s)[..., None]

    def paste(self, img, quad, shadow=True):
        if shadow:
            self.shadow(quad)
        out, mask = warp(img, quad)
        m = np.asarray(mask, dtype=float)[..., None] / 255
        self.a = self.a * (1 - m) + np.asarray(out, dtype=float) * m

    def paste_spread(self, left, right, outer, bulge=0.035, gutter_dark=0.45):
        """An open book: [left] and [right] pages between the [outer]
        corners (TL, TR, BR, BL of the spread), the gutter down the middle,
        each page bowed up towards the gutter by [bulge] of the height."""
        tl, tr, br, bl = outer
        top_mid = ((tl[0] + tr[0]) / 2, (tl[1] + tr[1]) / 2)
        bot_mid = ((bl[0] + br[0]) / 2, (bl[1] + br[1]) / 2)
        self.shadow(outer, dx=10, dy=24, blur=26, depth=0.5)
        # Page stack under the spread: a few thin edges below the bottom.
        d = ImageDraw.Draw(img := Image.fromarray(np.clip(self.a, 0, 255).astype(np.uint8)))
        for k in range(1, 5):
            d.line([(bl[0] + 2 * k, bl[1] + 3 * k), (bot_mid[0], bot_mid[1] + 2 * k), (br[0] - 2 * k, br[1] + 3 * k)], fill=(200 - 12 * k,) * 3, width=2)
        self.a = np.asarray(img, dtype=float)
        h = (bl[1] - tl[1])
        strips = 24
        for page, a0, a1, b1, b0, toward_gutter in [
            (left, tl, top_mid, bot_mid, bl, 1), (right, top_mid, tr, br, bot_mid, -1)
        ]:
            pw, ph = page.size
            for s in range(strips):
                f0, f1 = s / strips, (s + 1) / strips
                g0 = f0 if toward_gutter == 1 else 1 - f0
                g1 = f1 if toward_gutter == 1 else 1 - f1
                lift0 = bulge * h * math.sin(g0 * math.pi / 2) ** 3
                lift1 = bulge * h * math.sin(g1 * math.pi / 2) ** 3

                def lerp(p, q, t):
                    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)

                t0, t1 = lerp(a0, a1, f0), lerp(a0, a1, f1)
                u0, u1 = lerp(b0, b1, f0), lerp(b0, b1, f1)
                # The gutter end of each page curves down at the top and up
                # at the bottom less than the outer end: bow the strip.
                quad = [(t0[0], t0[1] + lift0), (t1[0], t1[1] + lift1), (u1[0], u1[1] - lift1 * 0.4), (u0[0], u0[1] - lift0 * 0.4)]
                strip = page.crop((int(f0 * pw), 0, max(int(f0 * pw) + 1, int(math.ceil(f1 * pw)) + 1), ph))
                out, mask = warp(strip, quad)
                m = np.asarray(mask, dtype=float)[..., None] / 255
                shade = 1 - gutter_dark * (max(g0, g1) ** 8)
                self.a = self.a * (1 - m) + np.asarray(out, dtype=float) * shade * m

    def finger(self, cx, cy, angle, length=260, width=90):
        """A finger or thumb over an edge of the page."""
        m = Image.new('L', (W, H), 0)
        a = math.radians(angle)
        ex, ey = cx + length * math.cos(a), cy + length * math.sin(a)
        d = ImageDraw.Draw(m)
        d.line([(cx, cy), (ex, ey)], fill=255, width=width)
        d.ellipse([cx - width / 2, cy - width / 2, cx + width / 2, cy + width / 2], fill=255)
        mm = np.asarray(m.filter(ImageFilter.GaussianBlur(3)), dtype=float)[..., None] / 255
        y, x = np.mgrid[0:H, 0:W].astype(float)
        shade = 0.85 + 0.15 * np.cos((x - cx) * 0.02)[..., None]
        skin = np.array([196, 140, 112], dtype=float) * shade
        self.a = self.a * (1 - mm) + skin * mm

    def light(self, from_x=0.3, from_y=0.2, falloff=0.35, band=None):
        y, x = np.mgrid[0:H, 0:W].astype(float)
        d = np.hypot(x / W - from_x, y / H - from_y)
        g = 1.05 - falloff * d
        if band is not None:
            # A soft shadow band across the scene (an arm or a phone).
            x0, x1, depth = band
            t = np.clip(((x + 0.4 * y) / W - x0) / (x1 - x0), 0, 1)
            g = g * (1 - depth * np.sin(t * math.pi) ** 2)
        self.a *= g[..., None]

    def save(self, path, grey=False, rng_noise=5.0):
        a = self.a + self.rng.normal(0, rng_noise, self.a.shape)
        img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
        if grey:
            img = img.convert('L').convert('RGB')
        img.save(path, quality=84, optimize=True)


# ----------------------------------------------------------------- samples

def main():
    os.makedirs(OUT, exist_ok=True)
    tmp = tempfile.mkdtemp()
    kv22 = 'sample_docs/KV_6th_Std_Half_Yearly_Exam_2022_Question_paper_Maths.pdf'
    kv23 = 'sample_docs/KV_6th_Std_Half_Yearly_Exam_2023_Maths_Question_paper.pdf'
    eng = 'sample_docs/KV_6th_std_Half_Yearly_Question_Paper_2024_ENGLISH.pdf'
    hindi = 'sample_docs/KV_6th_std_Half_Yearly_Question_Paper_2024_HINDI.pdf'

    post_box = odds_page(1, [(0, 0.165), (0.81, 0.145), (0.82, 0.83), (0, 0.77)])
    stamp = odds_page(2, [(0.075, 0.235), (0.79, 0.21), (0.93, 0.725), (0.05, 0.765)])
    binoculars = odds_page(4, [(0.01, 0.35), (0.67, 0.30), (0.885, 0.785), (0, 0.87)])
    rocket = odds_page(5, [(0.01, 0.235), (0.735, 0.21), (0.925, 0.735), (0, 0.8)])
    pipette = book_page('03_straw_pipette', [(0.11, 0.26), (0.8, 0.2), (0.92, 0.86), (0.13, 0.93)])
    dropper = book_page('04_medicine_dropper', [(0, 0.13), (0.63, 0.13), (0.66, 0.82), (0.02, 0.83)])
    lemon = book_page('12_lemon_soda', [(0.25, 0.24), (0.89, 0.12), (1, 0.76), (0.36, 0.87)])
    clock = book_page('20_grandfather_clock', [(0.47, 0.25), (0.91, 0.18), (0.92, 0.86), (0.53, 0.9)])

    samples = []

    def add(name, group, about, photo, pages, grey=False):
        photo.save(f'{OUT}/{name}.jpg', grey=grey)
        samples.append({'file': f'{name}.jpg', 'group': group, 'about': about, 'pages': [norm(q) for q in pages]})

    # Colour pages.
    p = Photo('dark_wood', 1)
    q = rect(540, 730, 700, 920, angle=-4, squeeze=0.06)
    p.paste(post_box, q); p.light()
    add('c01_colour_page_dark_wood', 'colour', 'Colour book page on dark wood, slight tilt', p, [q])

    p = Photo('beige_table', 2)
    q = rect(520, 700, 760, 1000, angle=6, squeeze=0.1)
    p.paste(binoculars, q); p.light(0.8, 0.1, 0.25)
    add('c02_colour_page_beige_table', 'colour', 'Colour page with a white margin on a light beige table (low contrast)', p, [q])

    p = Photo('concrete', 3)
    q = rect(560, 760, 680, 940, angle=11, squeeze=0.05)
    p.paste(tint(pdf_page(eng, 1, tmp), (250, 196, 214)), q); p.light()
    add('c03_pink_paper_concrete', 'colour', 'Printed notice on pink paper, on grey concrete', p, [q])

    p = Photo('light_wood', 4)
    q = rect(540, 720, 740, 1020, angle=-8, squeeze=0.12)
    p.paste(tint(pdf_page(kv22, 2, tmp), (252, 236, 120)), q); p.light(0.2, 0.9, 0.3)
    add('c04_yellow_paper_light_wood', 'colour', 'Yellow paper on light wood of a similar colour', p, [q])

    p = Photo('blue_cloth', 5)
    q = rect(530, 740, 720, 980, angle=3, squeeze=0.08)
    p.paste(tint(pdf_page(kv23, 1, tmp), (196, 222, 248)), q); p.light()
    add('c05_blue_form_blue_cloth', 'colour', 'Light blue form on blue cloth (page and background the same hue)', p, [q])

    p = Photo('carpet', 6)
    q = [(250, 300), (900, 350), (1000, 1250), (110, 1180)]
    p.paste(rocket, q); p.light(0.5, 0.0, 0.3)
    add('c06_colour_page_carpet_perspective', 'colour', 'Colour page on red carpet, strong perspective', p, [q])

    p = Photo('black_desk', 7)
    q = rect(540, 730, 640, 900, angle=-14)
    p.paste(stamp, q, shadow=False); p.light(0.5, 0.5, 0.2)
    add('c07_colour_page_black_desk_turned', 'colour', 'Colour page turned 14 degrees on a black desk', p, [q])

    # Black and white pages.
    p = Photo('black_desk', 8)
    q = rect(540, 720, 760, 1060, angle=0, squeeze=0.03)
    p.paste(pdf_page(kv22, 1, tmp), q, shadow=False); p.light()
    add('b01_bw_paper_black_desk', 'bw', 'Black and white question paper straight on a black desk (easy)', p, [q])

    p = Photo('concrete', 9)
    q = rect(560, 720, 700, 960, angle=15, squeeze=0.06)
    p.paste(pdf_page(kv23, 2, tmp), q); p.light(band=(0.35, 0.95, 0.45))
    add('b02_bw_paper_concrete_shadow', 'bw', 'Black and white page turned 15 degrees on concrete, a shadow across it', p, [q])

    p = Photo('bedsheet', 10)
    q = rect(540, 730, 720, 980, angle=-5, squeeze=0.07)
    p.paste(pdf_page(eng, 2, tmp), q); p.light(0.7, 0.2, 0.2)
    add('b03_bw_paper_white_bedsheet', 'bw', 'White page on a white bedsheet (very low contrast)', p, [q])

    p = Photo('dark_wood', 11)
    q = rect(540, 720, 720, 1000, angle=4, squeeze=0.1)
    p.paste(pdf_page(hindi, 1, tmp), q); p.light()
    p.finger(q[3][0] - 150, q[3][1] - 300, -10)
    p.finger(q[2][0] + 160, q[2][1] - 120, 190, length=240, width=100)
    add('b04_bw_paper_fingers_wood', 'bw', 'Hindi page held by fingers on the left and right edges, on dark wood', p, [q])

    p = Photo('black_desk', 12)
    q = rect(540, 720, 300, 1240, angle=-6, squeeze=0.04)
    p.paste(pdf_page(kv22, 1, tmp).crop((60, 300, 420, 1250)), q); p.light()
    add('b05_bw_narrow_slip_black_desk', 'bw', 'Narrow slip (like a receipt) on a black desk', p, [q])

    p = Photo('carpet', 13)
    q = rect(540, 740, 720, 1000, angle=-9, squeeze=0.08)
    p.paste(pdf_page(eng, 3, tmp), q); p.light()
    add('b06_bw_paper_carpet_grey_photo', 'bw', 'Black and white page on carpet, photo taken in greyscale', p, [q], grey=True)

    p = Photo('light_wood', 14)
    q = rect(540, 720, 720, 980, angle=7, squeeze=0.1)
    p.paste(post_box, q); p.light()
    add('b07_colour_page_wood_grey_photo', 'bw', 'Colour page on light wood, photo taken in greyscale (page and wood nearly the same grey)', p, [q], grey=True)

    # Books.
    def spread(outer):
        tl, tr, br, bl = outer
        tm = ((tl[0] + tr[0]) / 2, (tl[1] + tr[1]) / 2)
        bm = ((bl[0] + br[0]) / 2, (bl[1] + br[1]) / 2)
        return [outer, [tl, tm, bm, bl], [tm, tr, br, bm]]

    p = Photo('dark_wood', 15)
    outer = [(60, 330), (1020, 330), (1040, 1060), (40, 1060)]
    p.paste_spread(binoculars, rocket, outer); p.light()
    add('k01_colour_book_spread_wood', 'book', 'Open colour book, both pages in view, curved gutter, on dark wood', p, spread(outer))

    p = Photo('blue_cloth', 16)
    outer = [(30, 380), (1050, 400), (1060, 1010), (20, 990)]
    p.paste_spread(pipette, dropper, outer, bulge=0.05); p.light(0.6, 0.1, 0.3)
    add('k02_bw_book_spread_cloth', 'book', 'Open black and white book, both pages in view, curved gutter, on blue cloth', p, spread(outer))

    p = Photo('beige_table', 17)
    outer = [(-560, 230), (1000, 260), (1020, 1240), (-540, 1210)]
    p.paste_spread(stamp, post_box, outer, bulge=0.03)
    p.finger(1060, 1000, 170, length=200, width=110)
    p.light()
    right = spread(outer)[2]
    add('k03_colour_book_one_page_thumb', 'book', 'Right page of an open colour book fills the frame, left page cut off, thumb on the right edge', p, [right])

    p = Photo('black_desk', 18)
    outer = [(-470, 300), (1010, 250), (1040, 1180), (-440, 1210)]
    p.paste_spread(lemon, clock, outer, bulge=0.045, gutter_dark=0.6); p.light()
    add('k04_bw_book_one_page_dark', 'book', 'Right page of an open black and white book on a black desk, deep gutter shadow', p, [spread(outer)[2]])

    p = Photo('concrete', 19)
    outer = [(80, 300), (1000, 240), (1060, 1120), (30, 1180)]
    p.paste_spread(dropper, pipette, outer, bulge=0.04); p.light()
    add('k05_bw_book_spread_grey_photo', 'book', 'Open black and white book on concrete, photo taken in greyscale', p, spread(outer), grey=True)

    with open(f'{OUT}/corners.json', 'w') as f:
        json.dump({
            'about': 'Made by tool/make_edge_samples.py. Corners are TL, TR, BR, BL of the page, as a fraction of '
                     'the photo width and height. Where more than one outline counts as the page (an open '
                     'book: the spread or either page), each is listed.',
            'size': [W, H],
            'samples': samples,
        }, f, indent=1)


if __name__ == '__main__':
    main()
