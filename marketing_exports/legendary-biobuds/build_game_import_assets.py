from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent
PRION_BASE = ROOT / "prion-sassy" / "prion-sassy-clean-base.png"
PHAGE_BASE = ROOT / "legendary-t4-phage-biobud-clean-base.png"
OUT = ROOT / "game-import"
OUT.mkdir(exist_ok=True)

FRAME_COUNT = 8
CELL = (200, 128)


def trim_alpha(im: Image.Image, pad: int = 14) -> Image.Image:
    im = im.convert("RGBA")
    box = im.getbbox()
    if not box:
        return im
    l, t, r, b = box
    return im.crop((max(0, l - pad), max(0, t - pad), min(im.width, r + pad), min(im.height, b + pad)))


def fit_sprite(path: Path, max_h: int) -> Image.Image:
    im = trim_alpha(Image.open(path), pad=20)
    scale = max_h / im.height
    return im.resize((int(im.width * scale), int(im.height * scale)), Image.Resampling.NEAREST)


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


def star(draw: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int, int], s: int = 1) -> None:
    draw.rectangle((x - s, y, x + s, y), fill=color)
    draw.rectangle((x, y - s, x, y + s), fill=color)


def draw_folding_protein(draw: ImageDraw.ImageDraw, x: int, y: int, frame: int, color: tuple[int, int, int, int]) -> None:
    pts = []
    for i in range(8):
        pts.append((x + i * 6, y + int(math.sin(i * 0.9 + frame * 0.8) * 3)))
    draw.line(pts, fill=color, width=2)
    for px, py in pts[1::3]:
        draw.rectangle((px - 1, py - 1, px + 1, py + 1), fill=(255, 235, 255, color[3]))


def save_strip(frames: list[Image.Image], path: Path) -> None:
    strip = Image.new("RGBA", (CELL[0] * len(frames), CELL[1]), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        strip.alpha_composite(frame, (i * CELL[0], 0))
    strip.save(path)


def center_bottom(sprite: Image.Image, baseline: int, dx: int = 0, dy: int = 0) -> tuple[int, int]:
    return ((CELL[0] - sprite.width) // 2 + dx, baseline - sprite.height + dy)


def prion_transform(sprite: Image.Image, frame: int) -> Image.Image:
    sx = [1.00, 1.04, 1.08, 0.98, 0.94, 0.98, 1.03, 1.00][frame]
    sy = [1.00, 0.98, 0.94, 1.03, 1.08, 1.03, 0.98, 1.00][frame]
    angle = [0, -2, -4, -2, 0, 2, 4, 2][frame]
    im = sprite.resize((max(1, int(sprite.width * sx)), max(1, int(sprite.height * sy))), Image.Resampling.NEAREST)
    return im.rotate(angle, resample=Image.Resampling.NEAREST, expand=True)


def phage_transform(sprite: Image.Image, frame: int) -> Image.Image:
    # Tiny skitter/hover cycle: the legs feel alive without redrawing them.
    sx = [1.00, 1.02, 0.99, 1.01, 1.00, 0.98, 1.02, 1.00][frame]
    sy = [1.00, 0.99, 1.02, 0.98, 1.00, 1.02, 0.99, 1.00][frame]
    angle = [0, 2, 0, -2, 0, -2, 0, 2][frame]
    im = sprite.resize((max(1, int(sprite.width * sx)), max(1, int(sprite.height * sy))), Image.Resampling.NEAREST)
    return im.rotate(angle, resample=Image.Resampling.NEAREST, expand=True)


def prion_frames() -> tuple[list[Image.Image], list[Image.Image], list[Image.Image]]:
    sprite_base = fit_sprite(PRION_BASE, max_h=86)
    base_frames: list[Image.Image] = []
    overlay_frames: list[Image.Image] = []
    composed_frames: list[Image.Image] = []
    for frame in range(FRAME_COUNT):
        sprite = prion_transform(sprite_base, frame)
        canvas = Image.new("RGBA", CELL, (0, 0, 0, 0))
        overlay = Image.new("RGBA", CELL, (0, 0, 0, 0))
        composed = Image.new("RGBA", CELL, (0, 0, 0, 0))
        hop_y = [0, -1, 2, -7, -12, -7, 2, -1][frame]
        dx = [-4, -2, 1, 2, 4, 2, -1, -3][frame]
        pos = center_bottom(sprite, baseline=111, dx=dx, dy=hop_y)

        draw = ImageDraw.Draw(overlay)
        alpha = [70, 105, 145, 175, 160, 120, 85, 65][frame]
        draw_folding_protein(draw, 66, 109, frame, (202, 121, 255, alpha))
        draw_folding_protein(draw, 88, 119, frame + 3, (151, 224, 255, max(30, alpha - 55)))
        pulse = math.sin((frame / FRAME_COUNT) * math.tau)
        glow = outside_edge_glow(sprite, (238, 73, 255), int(160 + 38 * (pulse + 1) / 2), spread=13, blur=2, expand=18)
        overlay.alpha_composite(glow, (pos[0] - 18, pos[1] - 18))

        cx = pos[0] + sprite.width // 2
        cy = pos[1] + sprite.height // 2
        for idx, (ox, oy) in enumerate([(-46, -34), (52, -32), (-58, 4), (62, 12), (22, -54)]):
            drift = (frame + idx * 1.6) % FRAME_COUNT
            fade = 1 - drift / FRAME_COUNT
            star(ImageDraw.Draw(overlay), int(cx + ox + math.sin(drift) * 4), int(cy + oy - drift * 2), (255, 220, 255, int(170 * fade)), s=1)

        canvas.alpha_composite(sprite, pos)
        composed.alpha_composite(overlay, (0, 0))
        composed.alpha_composite(sprite, pos)
        base_frames.append(canvas)
        overlay_frames.append(overlay)
        composed_frames.append(composed)
    return base_frames, overlay_frames, composed_frames


def phage_frames() -> tuple[list[Image.Image], list[Image.Image], list[Image.Image]]:
    sprite_base = fit_sprite(PHAGE_BASE, max_h=92)
    base_frames: list[Image.Image] = []
    overlay_frames: list[Image.Image] = []
    composed_frames: list[Image.Image] = []
    for frame in range(FRAME_COUNT):
        sprite = phage_transform(sprite_base, frame)
        canvas = Image.new("RGBA", CELL, (0, 0, 0, 0))
        overlay = Image.new("RGBA", CELL, (0, 0, 0, 0))
        composed = Image.new("RGBA", CELL, (0, 0, 0, 0))
        hover_y = [0, -2, -4, -1, 1, -1, -3, -1][frame]
        dx = [-3, 0, 3, 1, -2, 1, 3, 0][frame]
        pos = center_bottom(sprite, baseline=116, dx=dx, dy=hover_y)
        pulse = math.sin((frame / FRAME_COUNT) * math.tau)
        glow = outside_edge_glow(sprite, (62, 232, 255), int(150 + 34 * (pulse + 1) / 2), spread=11, blur=2, expand=18)
        overlay.alpha_composite(glow, (pos[0] - 18, pos[1] - 18))

        draw = ImageDraw.Draw(overlay)
        cx = pos[0] + sprite.width // 2
        cy = pos[1] + sprite.height // 2
        # Tiny DNA/data-like particles trail around the capsid.
        for idx, (ox, oy, col) in enumerate([
            (-42, -42, (155, 236, 255)),
            (52, -48, (214, 255, 91)),
            (-62, 4, (155, 236, 255)),
            (62, 10, (214, 255, 91)),
            (8, -64, (255, 255, 255)),
        ]):
            drift = (frame + idx * 1.25) % FRAME_COUNT
            fade = 1 - drift / FRAME_COUNT
            star(draw, int(cx + ox + math.sin(drift * 1.2) * 4), int(cy + oy - drift * 2), (*col, int(170 * fade)), s=1)
        # Leg-energy ripple, not a shadow.
        y = pos[1] + sprite.height - 6
        draw.arc((cx - 42, y - 5, cx + 42, y + 12), 195, 345, fill=(112, 242, 255, 90), width=2)

        canvas.alpha_composite(sprite, pos)
        composed.alpha_composite(overlay, (0, 0))
        composed.alpha_composite(sprite, pos)
        base_frames.append(canvas)
        overlay_frames.append(overlay)
        composed_frames.append(composed)
    return base_frames, overlay_frames, composed_frames


def preview_gif(frames: list[Image.Image], path: Path) -> None:
    bg = Image.new("RGBA", (400, 256), (248, 240, 220, 255))
    previews = []
    for frame in frames:
        big = frame.resize((400, 256), Image.Resampling.NEAREST)
        canvas = bg.copy()
        canvas.alpha_composite(big, (0, 0))
        previews.append(canvas)
    previews[0].save(path, save_all=True, append_images=previews[1:], duration=115, loop=0, disposal=2)


def contact(rows: list[list[Image.Image]], path: Path) -> None:
    bg = (250, 247, 239, 255)
    sheet = Image.new("RGBA", (CELL[0] * FRAME_COUNT, CELL[1] * len(rows)), bg)
    for row_idx, frames in enumerate(rows):
        for i, frame in enumerate(frames):
            panel = Image.new("RGBA", CELL, bg)
            panel.alpha_composite(frame, (0, 0))
            sheet.alpha_composite(panel, (i * CELL[0], row_idx * CELL[1]))
    sheet.save(path)


def main() -> None:
    for name, maker in {
        "hero-prion": prion_frames,
        "hero-t4-phage": phage_frames,
    }.items():
        base, overlay, composed = maker()
        save_strip(base, OUT / f"{name}-base-8f.png")
        save_strip(overlay, OUT / f"{name}-overlay-8f.png")
        save_strip(composed, OUT / f"{name}-hop.png")
        contact([base, overlay, composed], OUT / f"{name}-contact.png")
        preview_gif(composed, OUT / f"{name}-battle-preview.gif")


if __name__ == "__main__":
    main()
