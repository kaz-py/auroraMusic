"""Genera los PNG del plugin (72/144 px en las teclas, @2x incluido).

El Stream Deck dibuja bien los PNG en cualquier versión; con SVG las teclas
pueden quedar en negro. Uso: python scripts/make_icons.py (necesita Pillow).
"""
from pathlib import Path
from PIL import Image, ImageDraw

BG, ACCENT, WHITE = (27, 27, 31, 255), (232, 105, 39, 255), (255, 255, 255, 255)
SS = 8  # supersampling
root = Path(__file__).resolve().parent.parent / "com.aurora.music.sdPlugin" / "imgs"


def canvas(size, base):
    return Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0)), size * SS / base


def finish(img, size):
    return img.resize((size, size), Image.LANCZOS)


def key(shapes, size):
    img, k = canvas(size, 144)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, size * SS - 1, size * SS - 1), radius=18 * k, fill=BG)
    for shape in shapes:
        kind, args = shape
        if kind == "poly":
            d.polygon([(x * k, y * k) for x, y in args], fill=ACCENT)
        elif kind == "rect":
            x, y, w, h, r = args
            d.rounded_rectangle((x * k, y * k, (x + w) * k, (y + h) * k), radius=r * k, fill=ACCENT)
        elif kind == "circle":
            cx, cy, r = args
            d.ellipse(((cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k), fill=ACCENT)
        elif kind == "line":
            pts = [(x * k, y * k) for x, y in args]
            d.line(pts + [pts[0]], fill=ACCENT, width=int(6 * k), joint="curve")
    return finish(img, size)


def glyph(shapes, size, base):
    img, k = canvas(size, base)
    d = ImageDraw.Draw(img)
    for kind, args in shapes:
        if kind == "poly":
            d.polygon([(x * k, y * k) for x, y in args], fill=WHITE)
        elif kind == "circle":
            cx, cy, r = args
            d.ellipse(((cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k), fill=WHITE)
    return finish(img, size)


PLAY = [("poly", [(50, 38), (102, 72), (50, 106)])]
PAUSE = [("rect", (44, 38, 20, 68, 4)), ("rect", (80, 38, 20, 68, 4))]
NEXT = [("poly", [(28, 40), (72, 72), (28, 104)]), ("poly", [(68, 40), (112, 72), (68, 104)])]
PREV = [("poly", [(68, 40), (24, 72), (68, 104)]), ("poly", [(108, 40), (64, 72), (108, 104)])]
JAM = [
    ("circle", (72, 56, 16)),
    ("circle", (40, 96, 16)),
    ("circle", (104, 96, 16)),
    ("line", [(72, 56), (40, 96), (104, 96)]),
]

states = {
    "toggle/paused": PLAY,
    "toggle/playing": PAUSE,
    "next/key": NEXT,
    "previous/key": PREV,
    "jam/key": JAM,
}
for name, shapes in states.items():
    path = root / "actions" / name
    key(shapes, 72).save(f"{path}.png")
    key(shapes, 144).save(f"{path}@2x.png")

icons = {
    "toggle/icon": ([("poly", [(6, 4), (16, 10), (6, 16)])], 20),
    "next/icon": ([("poly", [(3, 4), (10, 10), (3, 16)]), ("poly", [(10, 4), (17, 10), (10, 16)])], 20),
    "previous/icon": ([("poly", [(10, 4), (3, 10), (10, 16)]), ("poly", [(17, 4), (10, 10), (17, 16)])], 20),
    "jam/icon": ([("circle", (10, 5, 2.5)), ("circle", (5, 14, 2.5)), ("circle", (15, 14, 2.5))], 20),
}
for name, (shapes, base) in icons.items():
    path = root / "actions" / name
    glyph(shapes, base, base).save(f"{path}.png")
    glyph(shapes, base * 2, base).save(f"{path}@2x.png")

# Icono de categoría (28/56) y del plugin (256/512).
cat = [("poly", [(10, 7), (21, 14), (10, 21)])]
glyph(cat, 28, 28).save(root / "plugin" / "category-icon.png")
glyph(cat, 56, 28).save(root / "plugin" / "category-icon@2x.png")
for size, suffix in ((256, ""), (512, "@2x")):
    img, k = canvas(size, 256)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, size * SS - 1, size * SS - 1), radius=32 * k, fill=BG)
    d.polygon([(92 * k, 64 * k), (192 * k, 128 * k), (92 * k, 192 * k)], fill=ACCENT)
    finish(img, size).save(root / "plugin" / f"icon{suffix}.png")
