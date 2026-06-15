from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "movement"
OUT.mkdir(exist_ok=True)

BASE_PATH = ROOT / "prion-sassy-clean-base.png"
BATTLE_BG = Path("/Users/yukinabe/Desktop/mitoV3/MitoV3/Assets.xcassets/battle-map-bg.imageset/battle-map-bg.png")

FRAME_COUNT = 8
CELL = (256, 192)
GIF_SIZE = (480, 360)


def trim_alpha(im: Image.Image, pad: int = 16) -> Image.Image:
    im = im.convert("RGBA")
    box = im.getbbox()
    if not box:
        return im
    l, t, r, b = box
    return im.crop((max(0, l - pad), max(0, t - pad), min(im.width, r + pad), min(im.height, b + pad)))


def fit_sprite(path: Path, max_h: int = 116) -> Image.Image:
    im = trim_alpha(Image.open(path), pad=20)
    scale = max_h / im.height
    return im.resize((int(im.width * scale), int(im.height * scale)), Image.Resampling.NEAREST)


def transform_sprite(sprite: Image.Image, frame: int) -> Image.Image:
    # Sassy "fold-strut": tiny squash/stretch, slight turn, no detail regeneration.
    scale_x = [1.00, 1.04, 1.08, 0.98, 0.94, 0.98, 1.03, 1.00][frame]
    scale_y = [1.00, 0.98, 0.94, 1.03, 1.08, 1.03, 0.98, 1.00][frame]
    angle = [0, -2, -4, -2, 0, 2, 4, 2][frame]
    w = max(1, int(sprite.width * scale_x))
    h = max(1, int(sprite.height * scale_y))
    im = sprite.resize((w, h), Image.Resampling.NEAREST)
    return im.rotate(angle, resample=Image.Resampling.NEAREST, expand=True)


def center_bottom(canvas_size: tuple[int, int], sprite: Image.Image, baseline: int, dx: int = 0, dy: int = 0) -> tuple[int, int]:
    return ((canvas_size[0] - sprite.width) // 2 + dx, baseline - sprite.height + dy)


def outside_edge_glow(sprite: Image.Image, color: tuple[int, int, int], alpha: int, spread: int, blur: int, expand: int) -> Image.Image:
    base_alpha = sprite.getchannel("A")
    size = (sprite.width + expand * 2, sprite.height + expand * 2)
    original = Image.new("L", size, 0)
    original.paste(base_alpha, (expand, expand))
    kernel = spread if spread % 2 == 1 else spread + 1
    dilated = original.filter(ImageFilter.MaxFilter(kernel))
    outside = ImageChops.subtract(dilated, original)
    if blur:
        outside = outside.filter(ImageFilter.GaussianBlur(blur))
    glow = Image.new("RGBA", size, (*color, 0))
    glow.putalpha(outside.point(lambda p: min(alpha, int(p * alpha / 255))))
    return glow


def star(draw: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int, int], s: int = 2) -> None:
    draw.rectangle((x - s, y, x + s, y), fill=color)
    draw.rectangle((x, y - s, x, y + s), fill=color)


def draw_folding_protein(draw: ImageDraw.ImageDraw, x: int, y: int, frame: int, color: tuple[int, int, int, int]) -> None:
    # Small separate effect ribbon under the Prion, like it is strutting over folding proteins.
    pts = []
    for i in range(9):
        px = x + i * 8
        py = y + int(math.sin((i * 0.85) + frame * 0.75) * 6)
        pts.append((px, py))
    draw.line(pts, fill=color, width=3, joint="curve")
    for px, py in pts[1::3]:
        draw.rectangle((px - 2, py - 2, px + 2, py + 2), fill=(255, 235, 255, color[3]))


def make_frame(sprite_base: Image.Image, frame: int) -> tuple[Image.Image, Image.Image, Image.Image]:
    base_canvas = Image.new("RGBA", CELL, (0, 0, 0, 0))
    overlay = Image.new("RGBA", CELL, (0, 0, 0, 0))
    composed = Image.new("RGBA", CELL, (0, 0, 0, 0))

    sprite = transform_sprite(sprite_base, frame)
    hop_y = [0, -2, 3, -10, -18, -10, 3, -1][frame]
    strut_x = [-5, -2, 1, 3, 5, 2, -1, -3][frame]
    pos = center_bottom(CELL, sprite, baseline=166, dx=strut_x, dy=hop_y)

    draw = ImageDraw.Draw(overlay)
    # Protein folds are effects, not part of the sprite model.
    alpha = [70, 110, 160, 190, 170, 130, 90, 65][frame]
    draw_folding_protein(draw, 82, 160, frame, (202, 121, 255, alpha))
    draw_folding_protein(draw, 108, 172, frame + 3, (151, 224, 255, max(35, alpha - 45)))

    # Edge-only legendary glow follows the transformed sprite.
    pulse = math.sin((frame / FRAME_COUNT) * math.tau)
    glow = outside_edge_glow(sprite, (238, 73, 255), int(150 + 40 * (pulse + 1) / 2), spread=15, blur=2, expand=24)
    overlay.alpha_composite(glow, (pos[0] - 24, pos[1] - 24))

    # A few small particles that trail from the top folds.
    cx = pos[0] + sprite.width // 2
    cy = pos[1] + sprite.height // 2
    for idx, (ox, oy) in enumerate([(-62, -52), (72, -46), (-82, 8), (92, 18), (32, -78)]):
        drift = (frame + idx * 1.6) % FRAME_COUNT
        fade = 1 - drift / FRAME_COUNT
        x = int(cx + ox + math.sin(drift) * 6)
        y = int(cy + oy - drift * 3)
        color = (255, 218, 255, int(190 * fade)) if idx % 2 else (169, 226, 255, int(160 * fade))
        star(draw, x, y, color, s=2 if idx != 4 else 3)

    base_canvas.alpha_composite(sprite, pos)
    composed.alpha_composite(overlay, (0, 0))
    composed.alpha_composite(sprite, pos)
    return base_canvas, overlay, composed


def save_strip(frames: list[Image.Image], path: Path) -> None:
    strip = Image.new("RGBA", (CELL[0] * len(frames), CELL[1]), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        strip.alpha_composite(frame, (i * CELL[0], 0))
    strip.save(path)


def make_battle_preview(frames: list[Image.Image]) -> list[Image.Image]:
    if BATTLE_BG.exists():
        bg = Image.open(BATTLE_BG).convert("RGBA").resize(GIF_SIZE, Image.Resampling.BICUBIC)
    else:
        bg = Image.new("RGBA", GIF_SIZE, (247, 240, 222, 255))
    out: list[Image.Image] = []
    for frame in frames:
        frame_big = frame.resize((CELL[0] * 2, CELL[1] * 2), Image.Resampling.NEAREST)
        canvas = bg.copy()
        canvas.alpha_composite(frame_big, ((GIF_SIZE[0] - frame_big.width) // 2, 4))
        out.append(canvas)
    return out


def main() -> None:
    sprite = fit_sprite(BASE_PATH)
    base_frames: list[Image.Image] = []
    overlay_frames: list[Image.Image] = []
    composed_frames: list[Image.Image] = []
    for frame in range(FRAME_COUNT):
        base, overlay, composed = make_frame(sprite, frame)
        base_frames.append(base)
        overlay_frames.append(overlay)
        composed_frames.append(composed)

    save_strip(base_frames, OUT / "prion-sassy-fold-strut-base-8f.png")
    save_strip(overlay_frames, OUT / "prion-sassy-fold-strut-overlay-8f.png")
    save_strip(composed_frames, OUT / "prion-sassy-fold-strut-composed-8f.png")

    for folder, frames in [
        ("base-frames", base_frames),
        ("overlay-frames", overlay_frames),
        ("composed-frames", composed_frames),
    ]:
        d = OUT / folder
        d.mkdir(exist_ok=True)
        for i, frame in enumerate(frames):
            frame.save(d / f"{i:02d}.png")

    composed_frames[0].save(
        OUT / "prion-sassy-fold-strut-transparent.gif",
        save_all=True,
        append_images=composed_frames[1:],
        duration=115,
        loop=0,
        disposal=2,
    )
    battle_frames = make_battle_preview(composed_frames)
    battle_frames[0].save(
        OUT / "prion-sassy-fold-strut-battle-preview.gif",
        save_all=True,
        append_images=battle_frames[1:],
        duration=115,
        loop=0,
        disposal=2,
    )

    bg = (250, 247, 239, 255)
    contact = Image.new("RGBA", (CELL[0] * FRAME_COUNT, CELL[1] * 3), bg)
    for row, frames in enumerate([base_frames, overlay_frames, composed_frames]):
        for i, frame in enumerate(frames):
            panel = Image.new("RGBA", CELL, bg)
            panel.alpha_composite(frame, (0, 0))
            contact.alpha_composite(panel, (i * CELL[0], row * CELL[1]))
    contact.save(OUT / "prion-sassy-fold-strut-contact.png")


if __name__ == "__main__":
    main()
