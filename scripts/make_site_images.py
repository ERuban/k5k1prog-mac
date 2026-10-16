# /// script
# dependencies = ["pillow"]
# ///
# K5K1 Prog - images for the website (docs/assets): the link preview card (1200x630, used by
# Telegram, Discord, X, search results) and the PNG icons (Apple touch icon, favicon fallback).
# Needs rsvg-convert (brew install librsvg).   uv run scripts/make_site_images.py
#
# Copyright (C) 2026 Evgeny Ruban. GPL v3 (see LICENSE).

import pathlib
import subprocess
import tempfile
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
A = ROOT / "docs" / "assets"
LOGO = ROOT / "Resources" / "logo.svg"
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
REG = "/System/Library/Fonts/Supplemental/Arial.ttf"


def logo_png(size: int) -> Image.Image:
    with tempfile.NamedTemporaryFile(suffix=".png") as f:
        subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(LOGO), "-o", f.name], check=True)
        return Image.open(f.name).convert("RGBA")


# icons
logo_png(180).save(A / "apple-touch-icon.png", optimize=True)
logo_png(32).save(A / "favicon-32.png", optimize=True)

# preview card: dark navy like the logo, logo + name + line on the left, the editor on the right
W, H = 1200, 630
card = Image.new("RGBA", (W, H), (18, 24, 48, 255))
d = ImageDraw.Draw(card)
for y in range(H):   # vertical gradient #2E3B6E -> #121830, as in the logo
    t = y / H
    d.line([(0, y), (W, y)], fill=(int(46 + (18 - 46) * t), int(59 + (24 - 59) * t), int(110 + (48 - 110) * t), 255))

shot = Image.open(A / "memory-editor.png").convert("RGBA")
sw = 760
shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS)
card.alpha_composite(shot, (W - sw + 150, H - shot.height + 60))

card.alpha_composite(logo_png(150), (64, 70))
d.text((64, 250), "K5K1 Prog", font=ImageFont.truetype(BOLD, 74), fill=(255, 255, 255, 255))
f = ImageFont.truetype(REG, 33)
for i, line in enumerate(["Quansheng UV-K5 / UV-K1", "programmer for Mac"]):
    d.text((66, 350 + i * 44), line, font=f, fill=(214, 220, 240, 255))
d.text((66, 470), "Backup · Firmware · Channels", font=ImageFont.truetype(BOLD, 26), fill=(255, 138, 61, 255))
d.text((66, 520), "Free · Open source · Signed by Apple", font=ImageFont.truetype(REG, 24), fill=(170, 180, 210, 255))

card.convert("RGB").save(A / "og-card.png", optimize=True)
for n in ("apple-touch-icon.png", "favicon-32.png", "og-card.png"):
    p = A / n
    print(n, Image.open(p).size, p.stat().st_size)
