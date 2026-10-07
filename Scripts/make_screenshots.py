#!/usr/bin/env python3
"""Draws the README's Touch Bar images with made-up tabs, channels and repos,
so no real work shows up in screenshots. Pixel sizes come from real captures
of the Touch Bar (2170 x 60 px on a 15" MacBook Pro).

    python3 Scripts/make_screenshots.py      # needs Pillow; writes Docs/images/

SF Symbols are rendered by Scripts/render_symbols.swift, so they match the app.
"""
import os
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Docs", "images")

WIDTH, HEIGHT = 2170, 60
BUTTON = (54, 54, 54)
TEXT = (255, 255, 255)
RADIUS = 12
GAP = 16              # between items
ICON_WIDTH = 80       # icon-only buttons (40 pt)
ICON_GAP = 32         # icon buttons sit further apart
SMALL_SPACE = 16      # NSTouchBarItem.Identifier.fixedSpaceSmall
FONT = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 30)
# SF lacks Claude Code's "✳" title marker; macOS falls back to another font for it, and so do we.
FALLBACK = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 30)
FALLBACK_CHARACTERS = set("✳✶✻✽")
SYMBOL_SIZE = 30
SYMBOLS = [
    "chevron.left", "chevron.right", "plus", "xmark", "rectangle.split.2x1", "rectangle.split.1x2",
    "arrow.right.square", "arrow.up.left.and.arrow.down.right", "eraser", "arrow.triangle.branch",
    "sparkle", "arrow.left", "arrow.right", "arrow.clockwise", "arrow.uturn.backward", "at.circle.fill",
    "at", "tray.full", "bubble.left.and.bubble.right", "chevron.up", "chevron.down", "magnifyingglass",
    "play.circle",
]


def load_symbols():
    folder = tempfile.mkdtemp(prefix="barmaster-symbols-")
    subprocess.run(["swift", os.path.join(ROOT, "Scripts", "render_symbols.swift"), folder,
                    str(SYMBOL_SIZE)] + SYMBOLS, check=True)
    symbols = {name: Image.open(os.path.join(folder, name + ".png")).convert("RGBA") for name in SYMBOLS}
    # The bottle is the app's own menu bar glyph: black template → white.
    bottle = Image.open(os.path.join(ROOT, "Resources", "App", "MenuBarIcon@2x.png")).convert("RGBA")
    white = Image.new("RGBA", bottle.size, TEXT + (255,))
    white.putalpha(bottle.getchannel("A"))
    symbols["bottle"] = white
    SYMBOL_WIDTHS.update({name: glyph.width for name, glyph in symbols.items()})
    return symbols


SYMBOL_WIDTHS = {}


def runs(text):
    """Splits `text` into (chunk, font) runs, using FALLBACK where SF has no glyph."""
    chunks = []
    for character in text:
        font = FALLBACK if character in FALLBACK_CHARACTERS else FONT
        if chunks and chunks[-1][1] is font:
            chunks[-1][0] += character
        else:
            chunks.append([character, font])
    return chunks


def text_width(text):
    return int(sum(font.getlength(chunk) for chunk, font in runs(text)))


def fit(text, width):
    """Truncates `text` with an ellipsis to fit `width` pixels."""
    if text_width(text) <= width:
        return text
    while text and text_width(text + "…") > width:
        text = text[:-1]
    return text + "…"


# Items: ("icon", symbol) · ("text", label) · ("icon text", symbol, label, max width)
#        ("tabs", [titles], selected, width) · ("space",) · ("flex",)
def item_width(item):
    kind = item[0]
    if kind == "icon":
        return ICON_WIDTH
    if kind == "text":
        return max(112, text_width(item[1]) + 48)
    if kind == "icon text":
        return min(item[3], SYMBOL_WIDTHS[item[1]] + 12 + text_width(item[2]) + 48)
    if kind == "tabs":
        return item[3]
    if kind == "space":
        return SMALL_SPACE
    return 0


def gap_after(item, following):
    if following is None or item[0] in ("space", "flex") or following[0] in ("space", "flex"):
        return 0
    return ICON_GAP if item[0] == "icon" and following[0] == "icon" else GAP


def draw_bar(items, symbols):
    image = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
    draw = ImageDraw.Draw(image)
    fixed = sum(item_width(i) for i in items) + sum(
        gap_after(i, items[n + 1] if n + 1 < len(items) else None) for n, i in enumerate(items))
    flex = max(0, WIDTH - fixed)
    x = 0
    for n, item in enumerate(items):
        width = item_width(item) if item[0] != "flex" else flex
        draw_item(image, draw, item, x, width, symbols)
        x += width + gap_after(item, items[n + 1] if n + 1 < len(items) else None)
    return image


def paste_centered(image, glyph, cx):
    image.paste(glyph, (int(cx - glyph.width / 2), int((HEIGHT - glyph.height) / 2)), glyph)


def draw_text(draw, text, x, center=True, width=0):
    tx = x + (width - text_width(text)) / 2 if center else x
    for chunk, font in runs(text):
        draw.text((tx, HEIGHT / 2), chunk, font=font, fill=TEXT, anchor="lm")
        tx += font.getlength(chunk)


def draw_item(image, draw, item, x, width, symbols):
    kind = item[0]
    if kind in ("space", "flex"):
        return
    if kind == "tabs":
        # Like NSScrubber: the selected tab scrolled to the middle, neighbours clipped at the edges.
        titles, selected, cell = item[1], item[2], 220
        strip = Image.new("RGB", (width, HEIGHT), (0, 0, 0))
        strip_draw = ImageDraw.Draw(strip)
        offset = width / 2 - (selected * (cell + 8) + cell / 2)
        offset = min(0, max(offset, width - (len(titles) * (cell + 8) - 8)))
        for index, title in enumerate(titles):
            left = offset + index * (cell + 8)
            if index == selected:
                strip_draw.rounded_rectangle((left, 1, left + cell, HEIGHT - 2), RADIUS, outline=TEXT, width=3)
            draw_text(strip_draw, fit(title, cell - 24), left, width=cell)
        image.paste(strip, (int(x), 0))
        return
    draw.rounded_rectangle((x, 0, x + width - 1, HEIGHT - 1), RADIUS, fill=BUTTON)
    if kind == "icon":
        paste_centered(image, symbols[item[1]], x + width / 2)
    elif kind == "text":
        draw_text(draw, item[1], x, width=width)
    elif kind == "icon text":
        glyph = symbols[item[1]]
        label = fit(item[2], width - glyph.width - 12 - 48)
        content = glyph.width + 12 + text_width(label)
        left = x + (width - content) / 2
        image.paste(glyph, (int(left), int((HEIGHT - glyph.height) / 2)), glyph)
        draw_text(draw, label, left + glyph.width + 12, center=False)


def framed(bar):
    """Puts the bar on a dark rounded panel, like the strip above the keyboard."""
    pad = 24
    panel = Image.new("RGBA", (bar.width + pad * 2, bar.height + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(panel).rounded_rectangle((0, 0, panel.width - 1, panel.height - 1), 28, fill=(10, 10, 10, 255))
    panel.paste(bar, (pad, pad))
    return panel


def ghostty():
    return [
        ("text", "esc"), ("space",),
        ("icon", "chevron.left"),
        ("tabs", ["~/projects/rocket", "✳ Refactor auth flow", "npm run dev"], 1, 400),
        ("icon", "chevron.right"), ("space",),
        ("icon", "plus"), ("icon", "xmark"), ("space",),
        ("icon", "rectangle.split.2x1"), ("icon", "rectangle.split.1x2"), ("icon", "arrow.right.square"),
        ("icon", "arrow.up.left.and.arrow.down.right"), ("icon", "eraser"),
        ("flex",),
        ("icon text", "arrow.triangle.branch", "main · 128", 380),
        ("icon text", "sparkle", "84k", 200),
        ("icon", "bottle"),
    ]


def chrome():
    return [
        ("text", "esc"), ("space",),
        ("icon", "arrow.left"), ("icon", "arrow.right"), ("icon", "arrow.clockwise"), ("space",),
        ("icon", "chevron.left"),
        ("tabs", ["acme/rocket: Launch day", "Swift docs"], 0, 400),
        ("icon", "chevron.right"), ("space",),
        ("icon", "plus"), ("icon", "xmark"), ("space",),
        ("text", "Code"), ("text", "Issues"), ("text", "PRs"), ("icon", "play.circle"), ("text", "GitHub"),
        ("flex",),
        ("icon", "bottle"),
    ]


def slack():
    return [
        ("text", "esc"), ("space",),
        ("icon", "arrow.left"), ("icon", "arrow.right"), ("space",),
        ("icon", "at"),
        ("tabs", ["#general", "#launch", "#design", "Sam Rivera"], 1, 660),
        ("space",),
        ("icon", "tray.full"), ("icon", "bubble.left.and.bubble.right"),
        ("icon", "chevron.up"), ("icon", "chevron.down"), ("icon", "magnifyingglass"),
        ("flex",),
        ("icon text", "at.circle.fill", "Sam Rivera: can you review the launch PR?", 440),
        ("icon", "bottle"),
    ]


def main():
    os.makedirs(OUT, exist_ok=True)
    symbols = load_symbols()
    for name, items in [("ghostty", ghostty()), ("chrome", chrome()), ("slack", slack())]:
        path = os.path.join(OUT, f"touchbar-{name}.png")
        framed(draw_bar(items, symbols)).save(path, optimize=True)
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
