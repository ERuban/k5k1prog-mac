#!/usr/bin/env python3
"""Builds Resources/AppIcon.icns (+ AppIcon.iconset) from Resources/logo.svg.

The logo tile fills the canvas almost edge to edge; app icons follow Apple's grid
(824 x 824 body in a 1024 x 1024 canvas), so the tile is scaled down and centred
first. Needs rsvg-convert (brew install librsvg) and iconutil (Xcode tools).
"""
import pathlib, re, shutil, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parent.parent
logo = (root / "Resources/logo.svg").read_text()
iconset = root / "Resources/AppIcon.iconset"

# logo: tile x/y 24..488 in a 512 canvas -> Apple body 412 (= 824/1024 * 512) at 50
tile_x, tile_w, body = 24, 464, 512 * 824 / 1024
scale = body / tile_w
offset = (512 - body) / 2 - tile_x * scale
inner = re.sub(r"^\s*<svg[^>]*>|</svg>\s*$", "", logo.strip())
padded = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">\n'
          f'<g transform="translate({offset:.3f} {offset:.3f}) scale({scale:.5f})">\n{inner}\n</g>\n</svg>\n')

with tempfile.TemporaryDirectory() as tmp:
    src = pathlib.Path(tmp) / "icon.svg"
    src.write_text(padded)
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir()
    for size in (16, 32, 128, 256, 512):
        for factor in (1, 2):
            px = size * factor
            name = f"icon_{size}x{size}{'@2x' if factor == 2 else ''}.png"
            r = subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), str(src), "-o", str(iconset / name)],
                               capture_output=True, text=True)
            if r.returncode or r.stderr:
                sys.exit(f"rsvg-convert {name}: {r.stderr.strip()}")
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(root / "Resources/AppIcon.icns")], check=True)
print("Resources/AppIcon.icns")
