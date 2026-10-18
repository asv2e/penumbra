#!/usr/bin/env python3
"""Renders assets/icon/icon.png and icon_foreground.png (the SVGs' geometry).

flutter_launcher_icons only reads PNG, so these are the raster masters of
icon.svg / icon_foreground.svg. Needs Pillow:  pip install pillow
"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 2048          # supersampled canvas; downscaled to 1024
K = S / 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "icon")


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def linear(size, stops, p0, p1):
    """Linear gradient image; p0/p1 in 0..1 box coordinates."""
    w, h = size
    g = Image.new("RGB", size)
    px = g.load()
    dx, dy = (p1[0] - p0[0]) * w, (p1[1] - p0[1]) * h
    den = dx * dx + dy * dy
    for y in range(h):
        for x in range(w):
            t = ((x - p0[0] * w) * dx + (y - p0[1] * h) * dy) / den
            t = max(0.0, min(1.0, t))
            for i in range(len(stops) - 1):
                (o0, c0), (o1, c1) = stops[i], stops[i + 1]
                if t <= o1:
                    px[x, y] = lerp(c0, c1, (t - o0) / (o1 - o0) if o1 > o0 else 0)
                    break
    return g


def disc(cx, cy, r, scale):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    c = 512 + (cx - 512) * scale, 512 + (cy - 512) * scale
    rr = r * scale
    d.ellipse([(c[0] - rr) * K, (c[1] - rr) * K, (c[0] + rr) * K, (c[1] + rr) * K], fill=255)
    return m


def mark(scale):
    """Returns an RGBA layer of the mark (transparent background)."""
    a = disc(412, 512, 270, scale)
    b = disc(612, 512, 270, scale)
    # Penumbra: the occluder's edge is blurred, then removed from the lit disc.
    shade = b.filter(ImageFilter.GaussianBlur(24 * K * scale))
    alpha = Image.eval(shade, lambda v: 255 - v)
    lit_alpha = Image.composite(a, Image.new("L", (S, S), 0), a)
    lit_alpha = ImageChops_multiply(lit_alpha, alpha)

    # Gradient is defined over the lit disc's bounding box.
    box = int(540 * K * scale)
    grad = linear((box, box),
                  [(0, hexc("#A8F5EA")), (0.55, hexc("#4DB6AC")), (1, hexc("#1F7F76"))],
                  (0.15, 0.1), (0.85, 0.9))
    lit = Image.new("RGB", (S, S), hexc("#1F7F76"))
    ox = int((512 + (412 - 512) * scale - 270 * scale) * K)
    oy = int((512 + (512 - 512) * scale - 270 * scale) * K)
    lit.paste(grad, (ox, oy))

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Soft glow behind the lit disc.
    glow_a = a.filter(ImageFilter.GaussianBlur(70 * K * scale)).point(lambda v: int(v * 0.30))
    layer.paste(Image.new("RGB", (S, S), hexc("#4DB6AC")), (0, 0), glow_a)
    layer.paste(lit, (0, 0), lit_alpha)
    # Faint outline of the occluder.
    ring = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(ring)
    c = 512 + (612 - 512) * scale
    rr, w = 270 * scale, 6 * scale
    d.ellipse([(c - rr) * K, (512 - rr * 1 + 0) * K - 0, (c + rr) * K, (512 + rr) * K], outline=255, width=max(1, round(w * K)))
    ring = ring.point(lambda v: int(v * 0.28))
    layer.paste(Image.new("RGB", (S, S), hexc("#7FE3D6")), (0, 0), ring)
    return layer


def ImageChops_multiply(a, b):
    from PIL import ImageChops
    return ImageChops.multiply(a, b)


def main():
    bg = linear((S, S), [(0, hexc("#14323A")), (1, hexc("#091215"))], (0, 0), (1, 1)).convert("RGBA")
    full = Image.alpha_composite(bg, mark(1.0))
    full.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "icon.png"))
    fg = mark(0.8)
    fg.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, "icon_foreground.png"))
    print("wrote icon.png, icon_foreground.png")


if __name__ == "__main__":
    main()
