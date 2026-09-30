"""Frames raw 6.9" screenshots (1320x2868) with a caption on the gastos cream background.
Usage: python3 scripts/frame_screenshots.py <raw dir> <out dir>"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
CREAM, INK, RED = (250, 247, 242), (28, 26, 25), (216, 20, 26)
CAPTIONS = {
    "1-home": ("Know where", "your money goes."),
    "2-add": ("Log an expense", "in seconds."),
    "3-category": ("See which wallet", "paid for it."),
    "4-wallets": ("All your wallets,", "one calm place."),
    "5-insights": ("Simple insights,", "no spreadsheets."),
    "6-pass": ("Cards and passes,", "ready at the counter."),
}

def font(size, weight):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    f.set_variation_by_name(weight)
    return f

def frame(src: Path, dst: Path, lines):
    canvas = Image.new("RGB", (W, H), CREAM)
    draw = ImageDraw.Draw(canvas)
    head = font(104, "Bold")
    y = 170
    for i, line in enumerate(lines):
        w = draw.textlength(line, font=head)
        draw.text(((W - w) / 2, y), line, font=head, fill=RED if i == 1 else INK)
        y += 124
    # Phone screenshot, scaled, with rounded corners and a soft shadow.
    shot = Image.open(src).convert("RGB")
    scale = 0.78
    sw, sh = int(W * scale), int(H * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    radius = 90
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw, sh), radius, fill=255)
    x, top = (W - sw) // 2, y + 70
    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((x, top + 30, x + sw, top + sh + 30), radius, fill=70)
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas.paste(Image.new("RGB", (W, H), (120, 100, 90)), (0, 0), shadow)
    bezel = 16
    ImageDraw.Draw(canvas).rounded_rectangle((x - bezel, top - bezel, x + sw + bezel, top + sh + bezel), radius + bezel, fill=INK)
    canvas.paste(shot, (x, top), mask)
    canvas.save(dst)

raw, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
for name, lines in CAPTIONS.items():
    frame(raw / f"{name}.png", out / f"{name}.png", lines)
    print("framed", name)
