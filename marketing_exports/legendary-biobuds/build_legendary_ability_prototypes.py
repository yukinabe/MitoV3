#!/usr/bin/env python3
from __future__ import annotations

import math
from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "ability-prototypes"
APP_ASSETS = Path("/Users/yukinabe/Desktop/mitoV3/MitoV3/Assets.xcassets")

CELL_W = 200
CELL_H = 128
FRAMES = 8
FRAME_MS = 70

PRION_SRC = ROOT / "prion-sassy" / "prion-sassy-clean-base.png"
T4_SRC = ROOT / "legendary-t4-phage-biobud-clean-base.png"

PRION = (199, 140, 255, 255)
PRION_DARK = (95, 34, 168, 255)
PRION_HOT = (255, 235, 255, 255)
T4 = (79, 223, 242, 255)
T4_DARK = (27, 75, 176, 255)
T4_GREEN = (176, 255, 91, 255)
WHITE = (255, 255, 255, 255)
GOLD = (255, 226, 104, 255)


def hard_alpha(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pix = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pix[x, y]
            pix[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
    return image


def fitted_sprite(source: Path, target_height: int) -> Image.Image:
    image = hard_alpha(Image.open(source))
    bbox = image.getbbox()
    if bbox is None:
        raise ValueError(f"empty source: {source}")
    crop = image.crop(bbox)
    scale = target_height / crop.height
    return crop.resize((round(crop.width * scale), target_height), Image.Resampling.NEAREST)


def glow_layer(base: Image.Image, radius: int, color: tuple[int, int, int, int], alpha: int = 150) -> Image.Image:
    mask = base.getchannel("A").filter(ImageFilter.GaussianBlur(radius))
    layer = Image.new("RGBA", base.size, color)
    layer.putalpha(mask.point(lambda a: min(alpha, a)))
    return layer


def draw_line(draw: ImageDraw.ImageDraw, pts, color, width=3):
    draw.line(pts, fill=color, width=width, joint="curve")


def draw_star(draw: ImageDraw.ImageDraw, x: float, y: float, r: float, color):
    pts = [(x, y - r), (x + r * 0.35, y - r * 0.35), (x + r, y),
           (x + r * 0.35, y + r * 0.35), (x, y + r),
           (x - r * 0.35, y + r * 0.35), (x - r, y), (x - r * 0.35, y - r * 0.35)]
    draw.polygon(pts, fill=color)


def effect_frame() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def prion_flick(i: int) -> Image.Image:
    im, d = effect_frame()
    t = i / (FRAMES - 1)
    x = 30 + t * 138
    y = 69 - math.sin(t * math.pi) * 14
    for off, col, w in [(6, PRION_DARK, 5), (0, PRION, 4), (-4, PRION_HOT, 2)]:
        pts = []
        for k in range(6):
            u = k / 5
            pts.append((x - 58 + u * 70, y + off + math.sin(u * math.pi * 2 + t * 5) * 9))
        draw_line(d, pts, col, w)
    if i >= 4:
        for a in range(5):
            draw_star(d, 150 + a * 6, 62 + ((a % 2) * 13), 3 + (i - 4), PRION_HOT)
    return im


def prion_chain(i: int) -> Image.Image:
    im, d = effect_frame()
    t = i / (FRAMES - 1)
    cx, cy = 110, 64
    for band in range(3):
        phase = max(0, min(1, t * 1.35 - band * 0.18))
        if phase <= 0:
            continue
        rx = 18 + phase * (34 + band * 8)
        ry = 8 + phase * (18 + band * 4)
        col = [PRION_DARK, PRION, PRION_HOT][band]
        d.ellipse((cx - rx, cy - ry + band * 4, cx + rx, cy + ry + band * 4), outline=col, width=3)
        draw_line(d, [(cx - rx, cy + band * 4), (cx + rx, cy + band * 4)], col, 2)
    for k in range(7):
        u = (k / 6 + t * 0.5) % 1
        draw_star(d, 62 + u * 96, 42 + math.sin(u * math.pi * 2) * 25, 2.5, PRION_HOT)
    return im


def prion_cascade(i: int) -> Image.Image:
    im, d = effect_frame()
    t = i / (FRAMES - 1)
    cx, cy = 100, 64
    pulse = math.sin(t * math.pi)
    radius = 18 + t * 76
    d.ellipse((cx - radius, cy - radius * 0.65, cx + radius, cy + radius * 0.65), outline=PRION_DARK, width=5)
    d.ellipse((cx - radius * 0.72, cy - radius * 0.46, cx + radius * 0.72, cy + radius * 0.46), outline=PRION, width=4)
    d.ellipse((cx - radius * 0.38, cy - radius * 0.24, cx + radius * 0.38, cy + radius * 0.24), outline=PRION_HOT, width=3)
    for k in range(11):
        a = k * math.tau / 11 + t * 3
        r0 = 18 + t * 32
        r1 = 64 + pulse * 24
        p0 = (cx + math.cos(a) * r0, cy + math.sin(a) * r0 * 0.68)
        p1 = (cx + math.cos(a + 0.8) * r1, cy + math.sin(a + 0.8) * r1 * 0.68)
        draw_line(d, [p0, p1], PRION_HOT if k % 3 == 0 else PRION, 3 if k % 3 == 0 else 2)
    if i >= 5:
        d.rectangle((0, 0, CELL_W, CELL_H), fill=(255, 230, 255, 45 + (i - 5) * 35))
    return im


def t4_tail_pierce(i: int) -> Image.Image:
    im, d = effect_frame()
    t = i / (FRAMES - 1)
    x = 100
    y0 = 18
    y1 = 24 + t * 88
    draw_line(d, [(x, y0), (x, y1)], T4_DARK, 8)
    draw_line(d, [(x, y0), (x, y1)], T4, 5)
    draw_line(d, [(x, y0), (x, y1)], WHITE, 2)
    if i >= 4:
        for dx in (-22, -11, 11, 22):
            draw_line(d, [(x, y1), (x + dx, y1 + 13)], T4_GREEN, 3)
    return im


def draw_dna(d: ImageDraw.ImageDraw, x0: float, x1: float, y: float, t: float, color1=T4, color2=T4_GREEN):
    steps = 12
    top = []
    bot = []
    for k in range(steps):
        u = k / (steps - 1)
        x = x0 + (x1 - x0) * u
        wave = math.sin(u * math.tau * 2 + t * math.tau)
        top.append((x, y + wave * 10))
        bot.append((x, y - wave * 10))
    draw_line(d, top, color1, 3)
    draw_line(d, bot, color2, 3)
    for k in range(0, steps, 2):
        draw_line(d, [top[k], bot[k]], WHITE, 1)


def t4_genome_injection(i: int) -> Image.Image:
    im, d = effect_frame()
    t = i / (FRAMES - 1)
    start = 34
    end = 34 + t * 132
    draw_line(d, [(24, 64), (end, 64)], T4_DARK, 7)
    draw_line(d, [(24, 64), (end, 64)], T4, 4)
    draw_dna(d, start, max(start + 4, end), 64, t)
    if i >= 5:
        d.ellipse((142, 40, 184, 88), outline=T4_GREEN, width=4)
        d.ellipse((150, 48, 176, 80), outline=WHITE, width=2)
    return im


def t4_lytic_burst(i: int) -> Image.Image:
    im, d = effect_frame()
    t = i / (FRAMES - 1)
    cx, cy = 100, 64
    sides = 6
    r = 16 + t * 42
    pts = []
    for k in range(sides):
        a = -math.pi / 2 + k * math.tau / sides
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    d.polygon(pts, outline=T4, fill=(20, 55, 170, 40 + int(80 * t)))
    draw_dna(d, 70, 130, 64, t)
    if i >= 3:
        for k in range(14):
            a = k * math.tau / 14 + t
            dist = (i - 2) * 9 + (k % 3) * 5
            x = cx + math.cos(a) * dist
            y = cy + math.sin(a) * dist * 0.75
            if k % 2 == 0:
                d.polygon([(x, y - 5), (x + 5, y), (x, y + 5), (x - 5, y)], fill=T4 if k % 4 else T4_GREEN)
            else:
                draw_star(d, x, y, 3.5, WHITE)
    if i >= 6:
        d.rectangle((0, 0, CELL_W, CELL_H), fill=(150, 245, 255, 45 + (i - 6) * 45))
    return im


EFFECTS: list[tuple[str, Callable[[int], Image.Image], tuple[int, int, int, int]]] = [
    ("prion-misfold-flick", prion_flick, PRION),
    ("prion-chain-conformation", prion_chain, PRION),
    ("prion-cascade", prion_cascade, PRION),
    ("t4-tail-pierce", t4_tail_pierce, T4),
    ("t4-genome-injection", t4_genome_injection, T4),
    ("t4-lytic-burst", t4_lytic_burst, T4),
]


def write_imageset(name: str, strip: Image.Image) -> None:
    imageset = APP_ASSETS / f"{name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    strip.save(imageset / f"{name}.png")
    (imageset / "Contents.json").write_text(
        '{\n'
        '  "images" : [\n'
        f'    {{ "filename" : "{name}.png", "idiom" : "universal", "scale" : "1x" }}\n'
        '  ],\n'
        '  "info" : { "author" : "xcode", "version" : 1 }\n'
        '}\n'
    )


def save_gif(frames: list[Image.Image], path: Path, bg=(30, 22, 40, 255)) -> None:
    canvas_frames = []
    for f in frames:
        bg_im = Image.new("RGBA", f.size, bg)
        bg_im.alpha_composite(glow_layer(f, 5, (255, 255, 255, 255), 110))
        bg_im.alpha_composite(f)
        canvas_frames.append(bg_im.convert("P", palette=Image.Palette.ADAPTIVE))
    canvas_frames[0].save(path, save_all=True, append_images=canvas_frames[1:], duration=FRAME_MS, loop=0, disposal=2)


def battle_preview(name: str, frames: list[Image.Image], caster: Image.Image, caster_side: str) -> list[Image.Image]:
    enemy = fitted_sprite(ROOT / "legendary-biobuds-prion-phage-expressive-shiny-sheet.png", 60) if False else None
    previews = []
    for idx, effect in enumerate(frames):
        im = Image.new("RGBA", (280, 180), (22, 18, 34, 255))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle((18, 16, 262, 164), radius=4, fill=(31, 24, 45, 255), outline=(70, 58, 96, 255), width=2)
        d.ellipse((168, 58, 238, 126), fill=(64, 54, 82, 255), outline=(16, 12, 24, 255), width=4)
        d.rectangle((185, 75, 221, 109), fill=(112, 86, 160, 255))
        # Keep the BioBud static; only the ability layer changes.
        x = 34 if caster_side == "left" else 22
        y = 82
        im.alpha_composite(caster, (x, y))
        fx = effect.resize((220, 141), Image.Resampling.NEAREST)
        im.alpha_composite(glow_layer(fx, 7, (255, 255, 255, 255), 120), (46, 20))
        im.alpha_composite(fx, (46, 20))
        d.text((20, 12), name.upper(), fill=(244, 230, 192, 255))
        previews.append(im)
    return previews


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    prion_caster = fitted_sprite(PRION_SRC, 64)
    t4_caster = fitted_sprite(T4_SRC, 78)

    for name, fn, _ in EFFECTS:
        effect_dir = OUT / name
        frames_dir = effect_dir / "frames"
        frames_dir.mkdir(parents=True, exist_ok=True)
        frames = [hard_alpha(fn(i)) for i in range(FRAMES)]
        for i, frame in enumerate(frames):
            frame.save(frames_dir / f"{i:02d}.png")

        strip = Image.new("RGBA", (CELL_W * FRAMES, CELL_H), (0, 0, 0, 0))
        contact = Image.new("RGBA", (CELL_W * FRAMES, CELL_H), (245, 245, 245, 255))
        for i, frame in enumerate(frames):
            strip.alpha_composite(frame, (i * CELL_W, 0))
            contact.alpha_composite(frame, (i * CELL_W, 0))

        strip_path = effect_dir / f"{name}-8f.png"
        strip.save(strip_path)
        contact.save(effect_dir / f"{name}-contact.png")
        save_gif(frames, effect_dir / f"{name}-overlay-preview.gif")
        caster = prion_caster if name.startswith("prion") else t4_caster
        preview_frames = battle_preview(name, frames, caster, "left")
        preview_frames[0].save(
            effect_dir / f"{name}-battle-preview.gif",
            save_all=True,
            append_images=preview_frames[1:],
            duration=FRAME_MS,
            loop=0,
            disposal=2,
        )
        write_imageset(name, strip)
        print(f"{name}: {strip_path} alpha={sorted({px[3] for px in strip.getdata()})}")


if __name__ == "__main__":
    main()
