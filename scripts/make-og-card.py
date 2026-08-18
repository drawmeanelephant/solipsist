#!/usr/bin/env python3
"""Generate the Solipsist site's Open Graph card (1200x630).

Reproducible social-card generator. Writes
`site/themes/boris/assets/og/og-card.png` from the app's marketing icon
and the site's brand colors, so the image stays in sync with the theme.

Usage:
    python3 scripts/make-og-card.py [--out PATH]
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1200, 630
BG_TOP = (21, 26, 36)      # #151a24
BG_BOTTOM = (29, 37, 52)   # #1d2534
ACCENT = (139, 144, 240)   # --accent in dark mode
INK = (242, 244, 248)      # --header-text
MUTED = (167, 177, 194)    # --header-muted

FONT_CANDIDATES = [
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def load_font(size, bold=True):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="site/themes/boris/assets/og/og-card.png")
    args = parser.parse_args()

    icon_path = os.path.join(
        os.path.dirname(__file__), "..",
        "Solipsist/Assets.xcassets/AppIcon.appiconset/AppIcon-Marketing.png",
    )
    if not os.path.exists(icon_path):
        sys.exit(f"app icon not found: {icon_path}")

    # Vertical gradient background.
    img = Image.new("RGB", (WIDTH, HEIGHT))
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        row = tuple(round(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        ImageDraw.Draw(img).line([(0, y), (WIDTH, y)], fill=row)

    # Soft accent glow behind the icon.
    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((WIDTH // 2 - 340, 60, WIDTH // 2 + 340, 740), fill=(*ACCENT, 34))
    img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")

    draw = ImageDraw.Draw(img)

    # App icon, centered in the upper third.
    icon = Image.open(icon_path).convert("RGBA").resize((240, 240), Image.LANCZOS)
    img.paste(icon, (WIDTH // 2 - 120, 96), icon)

    # Brand.
    name_font = load_font(84)
    tag_font = load_font(34)
    name = "Solipsist"
    tagline = "Native macOS harness for Boris"

    name_box = draw.textbbox((0, 0), name, font=name_font)
    draw.text(
        ((WIDTH - (name_box[2] - name_box[0])) / 2, 380),
        name,
        font=name_font,
        fill=INK,
    )
    tag_box = draw.textbbox((0, 0), tagline, font=tag_font)
    draw.text(
        ((WIDTH - (tag_box[2] - tag_box[0])) / 2, 494),
        tagline,
        font=tag_font,
        fill=MUTED,
    )

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, format="PNG")
    print(f"wrote {out} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    main()
