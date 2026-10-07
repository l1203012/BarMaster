#!/usr/bin/env python3
"""Render the BarMaster app icon and menu-bar glyph.

The icon is a macOS-style squircle (1024x1024, Big Sur grid: 824px tile with a
100px margin) on a green gradient, holding a shouldered whisky bottle with
amber whisky, a wooden bar-top stopper and a cream "BM" label. Drawn at 4x and
downsampled for smooth edges. Requires Pillow.

    python3 Scripts/make_logo.py

Writes Resources/App/AppIcon-1024.png, Resources/App/AppIcon.icns (needs
iconutil) and the template glyphs Resources/App/MenuBarIcon.png / @2x.png.
"""

import math
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

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
AMBER_TOP = (250, 170, 46)
AMBER_BOTTOM = (150, 60, 10)
WOOD_TOP = (150, 92, 50)
WOOD_BOTTOM = (82, 46, 22)
CREAM = (250, 242, 222)
GOLD = (190, 140, 62)
INK = (96, 52, 22)

# bottle geometry, in 1024 space
CX = 512
BODY_HW = 206          # half width of the body
NECK_HW = 60           # half width of the neck
NECK_TOP = 262
SHOULDER_TOP = 326
SHOULDER_BOTTOM = 474
BASE = 846
CORNER = 54            # radius of the body's bottom corners
GLASS = 15             # glass wall thickness
LIQUID_TOP = 506
LIQUID_BOTTOM = 818    # thick glass punt below this
CAP = (CX - 78, 150, CX + 78, 236)   # wooden stopper cap
LABEL = (CX - 162, 594, CX + 162, 754)


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


def vgradient(top, bottom, y0, y1):
    """Vertical gradient that runs from y0 to y1 (1024 space), clamped outside."""
    col = Image.new("L", (1, W))
    col.putdata([int(255 * min(1, max(0, (y / SS - y0) / (y1 - y0)))) for y in range(W)])
    g = col.resize((W, W))
    a = Image.new("RGBA", (W, W), top + (255,))
    b = Image.new("RGBA", (W, W), bottom + (255,))
    return Image.composite(b, a, g)


def column_profile(fn, x0, x1):
    """Full-canvas L mask whose value per column is fn(t), t in 0..1 across x0..x1."""
    row = Image.new("L", (W, 1))
    vals = []
    for x in range(W):
        t = (x / SS - x0) / (x1 - x0)
        vals.append(int(255 * max(0, min(1, fn(max(0, min(1, t)))))))
    row.putdata(vals)
    return row.resize((W, W))


def radial_glow(cx, cy, r, color, alpha, ry=None):
    ry = ry or r
    g = Image.radial_gradient("L").resize((p(2 * r), p(2 * ry)))
    g = ImageChops.invert(g).point(lambda v: int((v / 255) ** 2.2 * alpha))
    out = layer()
    blob = Image.new("RGBA", g.size, color + (0,))
    blob.putalpha(g)
    out.alpha_composite(blob, (p(cx - r), p(cy - ry)))
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


def tint(mask, color, opacity=1.0):
    """Solid colour layer using mask (scaled by opacity) as alpha."""
    out = Image.new("RGBA", (W, W), color + (0,))
    out.putalpha(mask.point(lambda v: int(v * opacity)) if opacity != 1.0 else mask)
    return out


def soft(mask, blur):
    return mask.filter(ImageFilter.GaussianBlur(p(blur)))


# ---------------------------------------------------------------- bottle shape

def half_width(y, inset=0.0):
    """Half width of the bottle silhouette at height y (1024 space)."""
    if y < SHOULDER_TOP:
        hw = NECK_HW
    elif y < SHOULDER_BOTTOM:
        t = (y - SHOULDER_TOP) / (SHOULDER_BOTTOM - SHOULDER_TOP)
        # rounded shoulder: rises quickly then eases into the body
        e = math.sin(t * math.pi / 2) ** 1.6 if t < 1 else 1
        e = (1 - math.cos(math.pi * t)) / 2 * 0.45 + e * 0.55
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
    m = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(m)
    pts = outline(LIQUID_TOP, LIQUID_BOTTOM - 20, GLASS)
    d.polygon(pts, fill=255)
    # rounded inner bottom
    hw = half_width(LIQUID_BOTTOM - 40, GLASS)
    d.rounded_rectangle([p(CX - hw), p(LIQUID_BOTTOM - 80), p(CX + hw), p(LIQUID_BOTTOM)],
                        radius=p(36), fill=255)
    return m


def cylinder(mask, x0, x1, light=150, dark=120):
    """Horizontal cylinder shading (lit from upper left) clipped to mask."""
    hi = column_profile(lambda t: max(0, 1 - abs(t - 0.2) / 0.16) ** 1.5, x0, x1)
    lo = column_profile(lambda t: max(0, (t - 0.55) / 0.45) ** 1.6 * 0.85
                        + max(0, (0.12 - t) / 0.12) ** 2 * 0.5, x0, x1)
    out = layer()
    out.alpha_composite(tint(ImageChops.multiply(lo, mask), (40, 16, 0), dark / 255))
    out.alpha_composite(tint(ImageChops.multiply(hi, mask), (255, 255, 255), light / 255))
    return out


# ---------------------------------------------------------------- pieces

def cap_shape(d, fill):
    x0, y0, x1, y1 = CAP
    d.rounded_rectangle([p(x0), p(y0), p(x1), p(y1)], radius=p(34), fill=fill,
                        corners=(True, True, False, False))
    d.rounded_rectangle([p(x0), p(y0 + 40), p(x1), p(y1)], radius=p(12), fill=fill)


def shank_box():
    return [p(CX - 48), p(CAP[3] - 6), p(CX + 48), p(NECK_TOP + 6)]


def stopper():
    """Wooden bar-top stopper: a short cork shank under a turned wooden cap."""
    x0, y0, x1, y1 = CAP
    out = layer()
    # cork shank peeking out above the lip
    shank = layer()
    ImageDraw.Draw(shank).rectangle(shank_box(), fill=(222, 184, 128, 255))
    out.alpha_composite(shank)
    out.alpha_composite(cylinder(shank.getchannel("A"), CX - 48, CX + 48, 90, 120))

    m = Image.new("L", (W, W), 0)
    cap_shape(ImageDraw.Draw(m), 255)
    cap = mask_to(vgradient(WOOD_TOP, WOOD_BOTTOM, y0, y1), m)
    # turned groove near the base of the cap
    groove = Image.new("L", (W, W), 0)
    ImageDraw.Draw(groove).rectangle([p(x0 - 4), p(y1 - 22), p(x1 + 4), p(y1 - 16)], fill=255)
    cap.alpha_composite(tint(ImageChops.multiply(soft(groove, 1.2), m), (36, 18, 6), 0.6))
    cap.alpha_composite(cylinder(m, x0, x1, 120, 120))
    top = Image.new("L", (W, W), 0)
    ImageDraw.Draw(top).rounded_rectangle([p(x0 + 22), p(y0 + 5), p(x1 - 22), p(y0 + 16)], radius=p(6), fill=255)
    cap.alpha_composite(tint(ImageChops.multiply(soft(top, 3), m), (255, 230, 200), 0.45))
    out.alpha_composite(shadow(cap, 4, 5, 0.45))
    out.alpha_composite(cap)
    return out


def label():
    x0, y0, x1, y1 = LABEL
    out = layer()
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([p(x0), p(y0), p(x1), p(y1)], radius=p(14), fill=CREAM + (255,))
    a = out.getchannel("A")
    # gold double frame
    d.rounded_rectangle([p(x0 + 14), p(y0 + 14), p(x1 - 14), p(y1 - 14)], radius=p(8),
                        outline=GOLD + (255,), width=p(5))
    d.rounded_rectangle([p(x0 + 24), p(y0 + 24), p(x1 - 24), p(y1 - 24)], radius=p(4),
                        outline=GOLD + (150,), width=p(2))
    # monogram
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Didot.ttc", p(96), index=2)
    except OSError:
        font = ImageFont.truetype("/System/Library/Fonts/NewYork.ttf", p(88))
    text = "BM"
    l, t, r, b = d.textbbox((0, 0), text, font=font)
    d.text((p((x0 + x1) / 2) - (l + r) / 2, p((y0 + y1) / 2) - (t + b) / 2), text, fill=INK + (255,),
           font=font)
    # paper wraps around the bottle
    out.alpha_composite(cylinder(a, CX - BODY_HW, CX + BODY_HW, 70, 90))
    return out


def bottle():
    body = bottle_mask()
    out = layer()

    # empty glass: a pale, slightly warm translucent fill
    glass = mask_to(vgradient((236, 255, 240), (190, 236, 205), NECK_TOP, LIQUID_TOP), body)
    glass.putalpha(glass.getchannel("A").point(lambda v: int(v * 0.36)))
    out.alpha_composite(glass)

    # whisky
    liq = liquid_mask()
    whisky = mask_to(vgradient(AMBER_TOP, AMBER_BOTTOM, LIQUID_TOP, LIQUID_BOTTOM), liq)
    # glow from within
    whisky.alpha_composite(mask_to(radial_glow(CX - 30, 780, 200, (255, 214, 120), 120, 120), liq))
    out.alpha_composite(whisky)
    # meniscus: bright line at the surface
    surf = Image.new("L", (W, W), 0)
    hw = half_width(LIQUID_TOP, GLASS)
    ImageDraw.Draw(surf).ellipse([p(CX - hw), p(LIQUID_TOP - 9), p(CX + hw), p(LIQUID_TOP + 13)], fill=255)
    surf = ImageChops.multiply(surf, body)
    out.alpha_composite(tint(surf, (255, 206, 110), 1.0))
    rim_line = ImageChops.subtract(surf, ImageChops.offset(surf, 0, p(5)))
    out.alpha_composite(tint(rim_line, (255, 240, 200), 0.9))

    # glass walls: a lighter rim along the silhouette
    inner = Image.new("L", (W, W), 0)
    ImageDraw.Draw(inner).polygon(outline(NECK_TOP - 10, BASE - GLASS, GLASS), fill=255)
    rim = ImageChops.subtract(body, inner)
    out.alpha_composite(tint(rim, (220, 255, 230), 0.45))
    # refraction: a soft darker band just inside the walls gives the glass thickness
    deeper = Image.new("L", (W, W), 0)
    ImageDraw.Draw(deeper).polygon(outline(NECK_TOP - 10, BASE - GLASS - 10, GLASS + 10), fill=255)
    ring = ImageChops.subtract(inner, deeper)
    out.alpha_composite(tint(ImageChops.multiply(soft(ring, 6), body), (0, 70, 40), 0.22))
    # heavy glass base
    base = Image.new("L", (W, W), 0)
    ImageDraw.Draw(base).rectangle([p(0), p(LIQUID_BOTTOM + 6), p(1024), p(BASE)], fill=255)
    out.alpha_composite(tint(ImageChops.multiply(base, body), (250, 214, 150), 0.45))

    out.alpha_composite(label())

    # cylinder shading over the whole bottle
    out.alpha_composite(cylinder(body, CX - BODY_HW, CX + BODY_HW, 0, 90))
    neck = Image.new("L", (W, W), 0)
    ImageDraw.Draw(neck).rectangle([0, 0, W, p(SHOULDER_TOP + 30)], fill=255)
    out.alpha_composite(cylinder(ImageChops.multiply(neck, body), CX - NECK_HW, CX + NECK_HW, 0, 70))

    # specular highlights: a long stripe down the left of the body and the neck
    hl = Image.new("L", (W, W), 0)
    hd = ImageDraw.Draw(hl)
    hd.rounded_rectangle([p(CX - BODY_HW + 34), p(SHOULDER_BOTTOM + 10), p(CX - BODY_HW + 58), p(BASE - 70)],
                         radius=p(12), fill=230)
    hd.rounded_rectangle([p(CX - NECK_HW + 14), p(NECK_TOP + 16), p(CX - NECK_HW + 28), p(SHOULDER_TOP + 10)],
                         radius=p(7), fill=220)
    # shoulder glint follows the curve
    pts = []
    for i in range(41):
        y = SHOULDER_TOP + 30 + (SHOULDER_BOTTOM - SHOULDER_TOP - 40) * i / 40
        pts.append((p(CX - half_width(y) + 30), p(y)))
    hd.line(pts, fill=200, width=p(14), joint="curve")
    hl = ImageChops.multiply(soft(hl, 3), body)
    out.alpha_composite(tint(hl, (255, 255, 255)))
    # soft secondary reflection on the right
    hr = Image.new("L", (W, W), 0)
    ImageDraw.Draw(hr).rounded_rectangle([p(CX + BODY_HW - 52), p(SHOULDER_BOTTOM + 30),
                                          p(CX + BODY_HW - 38), p(BASE - 90)], radius=p(7), fill=110)
    out.alpha_composite(tint(ImageChops.multiply(soft(hr, 5), body), (255, 255, 255)))

    # crisp outer edge
    edge = ImageChops.subtract(body, body.filter(ImageFilter.MinFilter(9)))
    out.alpha_composite(tint(edge, (20, 60, 30), 0.35))

    # glass lip ring at the top of the neck
    lip = layer()
    ImageDraw.Draw(lip).rounded_rectangle([p(CX - 68), p(NECK_TOP - 6), p(CX + 68), p(NECK_TOP + 22)],
                                          radius=p(12), fill=(214, 240, 222, 255))
    la = lip.getchannel("A")
    lip.alpha_composite(cylinder(la, CX - 68, CX + 68, 160, 110))
    out.alpha_composite(lip)
    return out


# ---------------------------------------------------------------- finishing

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
    # soft backlight behind the bottle, darker vignette at the foot
    bg.alpha_composite(radial_glow(512, 470, 380, (200, 255, 190), 70))
    bg.alpha_composite(radial_glow(512, 980, 460, (0, 60, 30), 110, 260))

    b = bottle()
    # contact shadow on the "table" plus a soft cast shadow
    floor = layer()
    ImageDraw.Draw(floor).ellipse([p(CX - 200), p(BASE - 14), p(CX + 200), p(BASE + 22)], fill=(0, 0, 0, 255))
    bg.alpha_composite(shadow(floor, 10, 6, 0.45))
    bg.alpha_composite(shadow(b, 22, 22, 0.30, 8))
    bg.alpha_composite(b)
    bg.alpha_composite(stopper())
    return finish(bg)


def menu_glyph(px):
    """Black-on-transparent bottle silhouette with the label knocked out."""
    m = bottle_mask()
    d = ImageDraw.Draw(m)
    cap_shape(d, 255)
    # gap between cap and neck so the stopper reads as separate
    d.rectangle([p(CX - 90), p(CAP[3]), p(CX + 90), p(NECK_TOP - 2)], fill=0)
    d.rectangle(shank_box(), fill=255)
    x0, y0, x1, y1 = LABEL
    d.rounded_rectangle([p(x0 + 4), p(y0), p(x1 - 4), p(y1)], radius=p(18), fill=0)
    # crop to the glyph's height and fit it into a square canvas
    top, bottom = CAP[1], BASE
    h = bottom - top
    side = h * 1.0
    box = (p(CX - side / 2), p(top), p(CX + side / 2), p(bottom))
    m = m.crop(box)
    pad = int(m.size[0] * 0.03)
    canvas = Image.new("L", (m.size[0] + 2 * pad, m.size[1] + 2 * pad), 0)
    canvas.paste(m, (pad, pad))
    alpha = canvas.resize((px, px), Image.LANCZOS)
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
