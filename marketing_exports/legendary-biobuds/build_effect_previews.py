from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "effects"
OUT.mkdir(exist_ok=True)


SPRITES = {
    "prion": ROOT / "legendary-prion-biobud-clean-base.png",
    "t4-phage": ROOT / "legendary-t4-phage-biobud-clean-base.png",
}


def trim_alpha(im: Image.Image, pad: int = 18) -> Image.Image:
    im = im.convert("RGBA")
    box = im.getbbox()
    if not box:
        return im
    l, t, r, b = box
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(im.width, r + pad)
    b = min(im.height, b + pad)
    return im.crop((l, t, r, b))


def fit_sprite(path: Path, max_h: int = 300) -> Image.Image:
    im = trim_alpha(Image.open(path), pad=22)
    scale = min(1.0, max_h / im.height)
    size = (int(im.width * scale), int(im.height * scale))
    return im.resize(size, Image.Resampling.NEAREST)


def centered(canvas: Image.Image, sprite: Image.Image, dy: int = 0) -> tuple[int, int]:
    return ((canvas.width - sprite.width) // 2, (canvas.height - sprite.height) // 2 + dy)


def draw_pixel_star(draw: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int, int], scale: int = 4) -> None:
    draw.rectangle((x - scale, y, x + scale, y), fill=color)
    draw.rectangle((x, y - scale, x, y + scale), fill=color)
    draw.point((x, y), fill=(255, 255, 255, min(255, color[3] + 40)))


def make_overlay(kind: str, frame: int, size: tuple[int, int] = (420, 420)) -> Image.Image:
    w, h = size
    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    pulse = [0, 1, 2, 1][frame]
    alpha = [80, 120, 170, 115][frame]
    color = (116, 235, 255, alpha) if kind == "t4-phage" else (236, 128, 255, alpha)
    accent = (204, 255, 88, 220) if kind == "t4-phage" else (255, 235, 255, 220)

    # Pixel aura rings. Rectangular arcs keep the effect sprite-like rather than painterly.
    margin = 42 - pulse * 6
    for i in range(3):
        inset = margin + i * 16
        c = (color[0], color[1], color[2], max(20, color[3] - i * 35))
        draw.rounded_rectangle(
            (inset, inset + 18, w - inset, h - inset - 10),
            radius=36,
            outline=c,
            width=4,
        )

    # Small glints move around by frame. This can be used as an overlay-only runtime layer.
    positions = [
        [(84, 116), (326, 94), (112, 330), (300, 304)],
        [(94, 92), (344, 144), (132, 300), (286, 338)],
        [(72, 146), (310, 82), (104, 292), (348, 282)],
        [(108, 108), (342, 118), (82, 322), (306, 318)],
    ][frame]
    for idx, (x, y) in enumerate(positions):
        draw_pixel_star(draw, x, y, accent if idx % 2 else color, scale=5 if idx == 0 else 4)

    # Ground pulse under the character.
    y = 335 + pulse * 3
    draw.line((142, y, 278, y), fill=(color[0], color[1], color[2], max(40, alpha - 20)), width=5)
    draw.line((168, y + 12, 252, y + 12), fill=(color[0], color[1], color[2], max(25, alpha - 45)), width=4)

    return overlay


def make_frames(kind: str, sprite: Image.Image) -> tuple[list[Image.Image], list[Image.Image]]:
    baked_frames: list[Image.Image] = []
    overlay_frames: list[Image.Image] = []
    for i in range(4):
        canvas = Image.new("RGBA", (420, 420), (0, 0, 0, 0))
        overlay = make_overlay(kind, i, canvas.size)
        y_bob = [4, 0, -5, 0][i]
        pos = centered(canvas, sprite, dy=y_bob)
        baked = Image.alpha_composite(canvas, overlay)
        baked.alpha_composite(sprite, pos)
        baked_frames.append(baked)
        overlay_frames.append(overlay)
    return baked_frames, overlay_frames


def save_sheet(frames: list[Image.Image], path: Path) -> None:
    sheet = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        sheet.alpha_composite(frame, (i * frame.width, 0))
    sheet.save(path)


def save_preview_strip(kind: str, sprite: Image.Image, overlay_frames: list[Image.Image], baked_frames: list[Image.Image]) -> None:
    bg = (250, 247, 239, 255)
    preview = Image.new("RGBA", (420 * 4, 420 * 3), bg)
    for i in range(4):
        base_panel = Image.new("RGBA", (420, 420), bg)
        base_panel.alpha_composite(sprite, centered(base_panel, sprite))
        preview.alpha_composite(base_panel, (i * 420, 0))

        overlay_panel = Image.new("RGBA", (420, 420), bg)
        overlay_panel.alpha_composite(overlay_frames[i], (0, 0))
        preview.alpha_composite(overlay_panel, (i * 420, 420))

        baked_panel = Image.new("RGBA", (420, 420), bg)
        baked_panel.alpha_composite(baked_frames[i], (0, 0))
        preview.alpha_composite(baked_panel, (i * 420, 840))
    preview.save(OUT / f"{kind}-base-overlay-baked-preview.png")


def main() -> None:
    for kind, path in SPRITES.items():
        sprite = fit_sprite(path)
        baked_frames, overlay_frames = make_frames(kind, sprite)
        save_sheet(baked_frames, OUT / f"{kind}-legendary-effect-baked-4f.png")
        save_sheet(overlay_frames, OUT / f"{kind}-legendary-effect-overlay-only-4f.png")
        baked_frames[0].save(
            OUT / f"{kind}-legendary-effect-baked-preview.gif",
            save_all=True,
            append_images=baked_frames[1:],
            duration=180,
            loop=0,
            disposal=2,
        )
        overlay_frames[0].save(
            OUT / f"{kind}-legendary-effect-overlay-only-preview.gif",
            save_all=True,
            append_images=overlay_frames[1:],
            duration=180,
            loop=0,
            disposal=2,
        )
        save_preview_strip(kind, sprite, overlay_frames, baked_frames)


if __name__ == "__main__":
    main()
