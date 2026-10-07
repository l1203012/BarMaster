#!/usr/bin/env python3
"""Render the BarMaster app icon and menu-bar glyph.

The icon is a macOS-style squircle (1024x1024, Big Sur grid: 824px tile with a
100px margin) on a green gradient, holding a flat whisky bottle: pale glass,
amber whisky about two-thirds full, a plain cream label and a cork with a
wooden cap. Drawn at 4x and downsampled for smooth edges. Requires Pillow.

    python3 Scripts/make_logo.py

Writes Resources/App/AppIcon-1024.png, Resources/App/AppIcon.icns (needs
iconutil) and the template glyphs Resources/App/MenuBarIcon.png / @2x.png.
"""

import math
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 4                 # supersampling factor
SIZE = 1024            # final icon size
W = SIZE * SS          # working canvas size
APP = os.path.join(os.path.dirname(__file__), "..", "Resources", "App")
PNG = os.path.join(APP, "AppIcon-1024.png")
ICNS = os.path.join(APP, "AppIcon.icns")
MENU = os.path.join(APP, "MenuBarIcon.png")
MENU2X = os.path.join(APP, "MenuBarIcon@2x.png")

# palette
GREEN_TOP = (98, 222, 116)
GREEN_BOTTOM = (8, 112, 66)
GLASS_TINT = (196, 242, 204)   # flat, lighter tint of the tile green
AMBER = (247, 164, 38)
AMBER_DEEP = (222, 128, 24)    # lower half of the whisky
CORK = (226, 190, 136)
WOOD = (122, 72, 38)
LABEL_FILL = (252, 246, 232)

# bottle geometry, in 1024 space
CX = 512
BODY_HW = 192          # half width of the body
NECK_HW = 56           # half width of the neck
NECK_TOP = 300
SHOULDER_TOP = 352
SHOULDER_BOTTOM = 484
BASE = 820
CORNER = 56            # radius of the body's bottom corners
WALL = 18              # glass wall around the whisky
LIQUID_TOP = 490       # about two-thirds full (body starts at SHOULDER_BOTTOM)
CAP = (CX - 72, 204, CX + 72, 280)            # wooden stopper cap
SHANK = (CX - 44, 274, CX + 44, NECK_TOP + 4)  # cork between cap and neck
LABEL = (CX - 148, 590, CX + 148, 728)
SPLIT = 728            # whisky turns a shade deeper below this line


def p(v):
    """1024-space coordinate -> working-canvas pixels."""
    return int(round(v * SS))


def layer():
    return Image.new("RGBA", (W, W), (0, 0, 0, 0))


# ---------------------------------------------------------------- primitives

def squircle_points(cx, cy, half, n=5.0, steps=1440):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = math.copysign(abs(c) ** (2 / n), c) * half
        y = math.copysign(abs(s) ** (2 / n), s) * half
        pts.append((p(cx + x), p(cy + y)))
    return pts


def squircle_mask():
    m = Image.new("L", (W, W), 0)
    ImageDraw.Draw(m).polygon(squircle_points(512, 512, 412), fill=255)
    return m


def gradient(top, bottom, angle=0):
    """Linear gradient filling the canvas; angle in degrees (0 = top->bottom)."""
    d = int(W * 1.5)
    g = Image.linear_gradient("L").resize((d, d))
    if angle:
        g = g.rotate(angle, resample=Image.BICUBIC)
    off = (d - W) // 2
    g = g.crop((off, off, off + W, off + W))
    a = Image.new("RGBA", (W, W), top + (255,))
    b = Image.new("RGBA", (W, W), bottom + (255,))
    return Image.composite(b, a, g)


def radial_glow(cx, cy, r, color, alpha):
    g = Image.radial_gradient("L").resize((p(2 * r), p(2 * r)))
    g = ImageChops.invert(g).point(lambda v: int((v / 255) ** 2.2 * alpha))
    out = layer()
    blob = Image.new("RGBA", g.size, color + (0,))
    blob.putalpha(g)
    out.alpha_composite(blob, (p(cx - r), p(cy - r)))
    return out


def shadow(src, blur, dy, opacity, dx=0):
    a = src.getchannel("A").point(lambda v: int(v * opacity))
    a = a.filter(ImageFilter.GaussianBlur(p(blur)))
    out = layer()
    out.putalpha(a)
    return ImageChops.offset(out, p(dx), p(dy))


def mask_to(img, mask):
    out = img.copy()
    out.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return out


def fill(mask, color):
    out = Image.new("RGBA", (W, W), color + (0,))
    out.putalpha(mask)
    return out


# ---------------------------------------------------------------- bottle shape

def half_width(y, inset=0.0):
    """Half width of the bottle silhouette at height y (1024 space)."""
    if y < SHOULDER_TOP:
        hw = NECK_HW
    elif y < SHOULDER_BOTTOM:
        t = (y - SHOULDER_TOP) / (SHOULDER_BOTTOM - SHOULDER_TOP)
        # rounded shoulder: leaves the neck smoothly, rounds into the body
        e = (1 - math.cos(math.pi * t)) / 2 * 0.45 + math.sin(t * math.pi / 2) ** 1.6 * 0.55
        hw = NECK_HW + (BODY_HW - NECK_HW) * e
    else:
        hw = BODY_HW
    if y > BASE - CORNER:
        dy = y - (BASE - CORNER)
        hw -= CORNER - math.sqrt(max(0, CORNER ** 2 - dy ** 2))
    return hw - inset


def outline(y0, y1, inset=0.0, steps=600):
    left, right = [], []
    for i in range(steps + 1):
        y = y0 + (y1 - y0) * i / steps
        hw = half_width(y, inset)
        left.append((p(CX - hw), p(y)))
        right.append((p(CX + hw), p(y)))
    return left + right[::-1]


def bottle_mask():
    m = Image.new("L", (W, W), 0)
    ImageDraw.Draw(m).polygon(outline(NECK_TOP, BASE), fill=255)
    return m


def liquid_mask():
    """The body inset by the glass wall, from the whisky line down."""
    m = Image.new("L", (W, W), 0)
    x0, x1 = CX - BODY_HW + WALL, CX + BODY_HW - WALL
    ImageDraw.Draw(m).rounded_rectangle([p(x0), p(LIQUID_TOP), p(x1), p(BASE - WALL)],
                                        radius=p(CORNER - WALL), fill=255,
                                        corners=(False, False, True, True))
    return m


def cap_shape(d, color):
    x0, y0, x1, y1 = CAP
    d.rounded_rectangle([p(x0), p(y0), p(x1), p(y1)], radius=p(22), fill=color)


def shank_shape(d, color):
    x0, y0, x1, y1 = SHANK
    d.rectangle([p(x0), p(y0), p(x1), p(y1)], fill=color)


# ---------------------------------------------------------------- icon

def bottle():
    """Flat bottle built from a handful of solid shapes."""
    out = layer()
    out.alpha_composite(fill(bottle_mask(), GLASS_TINT))

    liq = liquid_mask()
    out.alpha_composite(fill(liq, AMBER))
    lower = Image.new("L", (W, W), 0)
    ImageDraw.Draw(lower).rectangle([0, p(SPLIT), W, W], fill=255)
    out.alpha_composite(fill(ImageChops.multiply(liq, lower), AMBER_DEEP))

    d = ImageDraw.Draw(out)
    x0, y0, x1, y1 = LABEL
    d.rounded_rectangle([p(x0), p(y0), p(x1), p(y1)], radius=p(18), fill=LABEL_FILL + (255,))

    shank_shape(d, CORK + (255,))
    cap_shape(d, WOOD + (255,))
    return out


def finish(content):
    """Clip to the squircle, add gloss, edge light and the drop shadow."""
    mask = squircle_mask()
    icon = mask_to(content, mask)

    gloss = radial_glow(512, 140, 520, (255, 255, 255), 46)
    icon.alpha_composite(mask_to(gloss, mask))

    edge = layer()
    ImageDraw.Draw(edge).line(squircle_points(512, 512, 410.5) + [squircle_points(512, 512, 410.5)[0]],
                              fill=(255, 255, 255, 60), width=p(2.5))
    icon.alpha_composite(mask_to(edge, mask))

    out = layer()
    sil = layer()
    sil.putalpha(mask)
    out.alpha_composite(shadow(sil, 14, 12, 0.32))
    out.alpha_composite(icon)
    return out.resize((SIZE, SIZE), Image.LANCZOS)


def app_icon():
    bg = gradient(GREEN_TOP, GREEN_BOTTOM)
    bg.alpha_composite(bottle())
    return finish(bg)


# ---------------------------------------------------------------- menu bar

def menu_glyph(px):
    """Black-on-transparent bottle silhouette with the label knocked out."""
    m = bottle_mask()
    d = ImageDraw.Draw(m)
    cap_shape(d, 255)
    shank_shape(d, 255)
    # thin gap between cap and neck so the stopper reads as separate
    d.rectangle([p(CX - 90), p(CAP[3]), p(CX + 90), p(NECK_TOP - 4)], fill=0)
    shank_shape(d, 255)
    d.rectangle([p(CX - 90), p(CAP[3]), p(CX + 90), p(CAP[3] + 8)], fill=0)
    x0, y0, x1, y1 = LABEL
    d.rounded_rectangle([p(x0 + 8), p(y0), p(x1 - 8), p(y1)], radius=p(18), fill=0)
    # fit the glyph's height into a square canvas with a little padding
    top, bottom = CAP[1], BASE
    pad = (bottom - top) * 0.04
    box = (p(CX - (bottom - top) / 2 - pad), p(top - pad), p(CX + (bottom - top) / 2 + pad), p(bottom + pad))
    alpha = m.crop(box).resize((px, px), Image.LANCZOS)
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.putalpha(alpha)
    return out


def write_icns(icon, path):
    """Pack an icon into .icns with every size macOS asks for (needs iconutil)."""
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.mkdir(iconset)
        for pt in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                px_size = pt * scale
                name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
                icon.resize((px_size, px_size), Image.LANCZOS).save(os.path.join(iconset, name))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", path], check=True)


def main():
    os.makedirs(APP, exist_ok=True)
    icon = app_icon()
    icon.save(PNG)
    print("wrote", os.path.normpath(PNG))

    menu_glyph(18).save(MENU)
    menu_glyph(36).save(MENU2X)
    print("wrote", os.path.normpath(MENU))
    print("wrote", os.path.normpath(MENU2X))

    if shutil.which("iconutil"):
        write_icns(icon, ICNS)
        print("wrote", os.path.normpath(ICNS))
    else:
        print("skipped AppIcon.icns: iconutil not found (macOS only)")


if __name__ == "__main__":
    main()
