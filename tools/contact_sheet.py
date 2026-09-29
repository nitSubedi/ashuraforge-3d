"""Tile PNGs into one labelled contact sheet (for reviewing render variants).
Usage: python3 tools/contact_sheet.py out.png a.png b.png ... [--crop x,y,w,h]"""
import sys
from PIL import Image, ImageDraw

args = sys.argv[1:]
crop = None
if "--crop" in args:
	i = args.index("--crop")
	crop = tuple(int(v) for v in args[i + 1].split(","))
	del args[i:i + 2]
out, paths = args[0], args[1:]
ims = [Image.open(p).convert("RGB") for p in paths]
if crop:
	ims = [im.crop((crop[0], crop[1], crop[0] + crop[2], crop[1] + crop[3])) for im in ims]
w, h = ims[0].size
cols = 2 if len(ims) > 1 else 1
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (w * cols, h * rows), (0, 0, 0))
for i, im in enumerate(ims):
	x, y = (i % cols) * w, (i // cols) * h
	sheet.paste(im, (x, y))
	ImageDraw.Draw(sheet).text((x + 10, y + 10), str(i), fill=(255, 255, 0))
sheet.save(out)
print("SHEET", out, sheet.size)
