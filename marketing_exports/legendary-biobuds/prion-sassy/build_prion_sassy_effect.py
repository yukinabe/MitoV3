from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent
BASE_PATH = ROOT / "prion-sassy-clean-base.png"
OUT = ROOT / "effects"
OUT.mkdir(exist_ok=True)


def trim_alpha(im: Image.Image, pad: int = 16) -> Image.Image:
    box = im.getbbox()
    if not box:
        return im
    l, t, r, b = box
    return im.crop((max(0, l - pad), max(0, t - pad), min(im.width, r + pad), min(im.height, b + pad)))


def fit_sprite(path: Path, max_h: int = 305) -> Image.Image:
    im = trim_alpha(Image.open(path).convert("RGBA"), pad=18)
    scale = min(1.0, max_h / im.height)
    return im.resize((int(im.width * scale), int(im.height * scale)), Image.Resampling.NEAREST)


def center_pos(canvas: Image.Image, sprite: Image.Image, dy: int = 0) -> tuple[int, int]:
    return ((canvas.width - sprite.width) // 2, (canvas.height - sprite.height) // 2 + dy)


def tinted_glow(sprite: Image.Image, color: tuple[int, int, int], alpha: int, blur: int, expand: int = 10) -> Image.Image:
    alpha_mask = sprite.getchannel("A")
    glow = Image.new("RGBA", (sprite.width + expand * 2, sprite.height + expand * 2), (*color, 0))
    mask = Image.new("L", glow.size, 0)
    mask.paste(alpha_mask, (expand, expand))
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    glow.putalpha(mask.point(lambda p: min(alpha, int(p * alpha / 255))))
    return glow


def outside_edge_glow(
    sprite: Image.Image,
    color: tuple[int, int, int],
    alpha: int,
    spread: int = 18,
    blur: int = 2,
    expand: int = 30,
) -> Image.Image:
    """Create a glow only outside the sprite outline, never filling the sprite body."""
    base_alpha = sprite.getchannel("A")
    canvas_size = (sprite.width + expand * 2, sprite.height + expand * 2)
    original = Image.new("L", canvas_size, 0)
    original.paste(base_alpha, (expand, expand))

    # MaxFilter expands the alpha silhouette. Subtracting the original leaves only
    # the outside halo band, which is easier to read than a filled glow blob.
    kernel = spread if spread % 2 == 1 else spread + 1
    dilated = original.filter(ImageFilter.MaxFilter(kernel))
    outside = ImageChops.subtract(dilated, original)
    if blur:
        outside = outside.filter(ImageFilter.GaussianBlur(blur))

    glow = Image.new("RGBA", canvas_size, (*color, 0))
    glow.putalpha(outside.point(lambda p: min(alpha, int(p * alpha / 255))))
    return glow


def draw_star(draw: ImageDraw.ImageDraw, x: int, y: int, color: tuple[int, int, int, int], s: int = 4) -> None:
    draw.rectangle((x - s, y, x + s, y), fill=color)
    draw.rectangle((x, y - s, x, y + s), fill=color)
    draw.point((x, y), fill=(255, 255, 255, min(255, color[3] + 35)))


def overlay_frame(frame: int, size: tuple[int, int], sprite_box: tuple[int, int, int, int]) -> Image.Image:
    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    l, t, r, b = sprite_box
    cx = (l + r) // 2
    cy = (t + b) // 2
    pulse = math.sin((frame / 8) * math.tau)
    alpha = int(80 + 45 * (pulse + 1) / 2)

    # Thin aura outline, intentionally outside the sprite model.
    ring_color = (232, 108, 255, alpha)
    inset_x = 28 + int(5 * pulse)
    inset_y = 38 + int(4 * pulse)
    draw.rounded_rectangle(
        (l - inset_x, t + 8 - inset_y, r + inset_x, b + inset_y),
        radius=46,
        outline=ring_color,
        width=4,
    )
    draw.rounded_rectangle(
        (l - inset_x + 18, t + 24 - inset_y, r + inset_x - 18, b + inset_y - 18),
        radius=38,
        outline=(255, 206, 255, max(25, alpha - 45)),
        width=3,
    )

    # Floating particles coming out of the sprite. These are separate effect pixels.
    particles = [
        (-122, -92, 0.0, 5),
        (118, -110, 0.22, 4),
        (-142, 28, 0.44, 3),
        (138, 58, 0.66, 4),
        (-62, 142, 0.84, 3),
        (82, 126, 0.32, 3),
    ]
    for i, (ox, oy, phase, s) in enumerate(particles):
        drift = (frame + phase * 8) % 8
        x = int(cx + ox + math.sin((drift / 8) * math.tau) * 8)
        y = int(cy + oy - drift * 3)
        a = int(65 + 150 * (1 - drift / 8))
        color = (255, 202, 255, a) if i % 2 else (157, 222, 255, a)
        draw_star(draw, x, y, color, s=s)

    # Ground shimmer under character.
    gy = b - 6 + int(2 * pulse)
    draw.line((cx - 86, gy, cx + 86, gy), fill=(245, 146, 255, 95), width=4)
    draw.line((cx - 48, gy + 10, cx + 48, gy + 10), fill=(255, 230, 255, 55), width=3)
    return overlay


def aura_overlay_frame(frame: int, size: tuple[int, int], sprite: Image.Image, pos: tuple[int, int]) -> Image.Image:
    overlay = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    x, y = pos
    cx = x + sprite.width // 2
    cy = y + sprite.height // 2
    pulse = math.sin((frame / 8) * math.tau)

    # Strong edge-only glow outside the sprite outline. This does not fill the
    # character body; it reads as an aura/highlight around the actual sprite.
    outer = outside_edge_glow(
        sprite,
        (238, 73, 255),
        int(190 + 35 * (pulse + 1) / 2),
        spread=25,
        blur=3,
        expand=36,
    )
    overlay.alpha_composite(outer, (x - 36, y - 36))
    rim = outside_edge_glow(
        sprite,
        (255, 230, 255),
        int(160 + 45 * (1 - pulse) / 2),
        spread=9,
        blur=0,
        expand=18,
    )
    overlay.alpha_composite(rim, (x - 18, y - 18))

    # Small particles coming off the body, biased upward and outward.
    particle_seed = [
        (-116, -58, -1.0, 0.0, 5, (255, 206, 255, 210)),
        (105, -78, 1.0, 0.2, 4, (170, 230, 255, 190)),
        (-142, 18, -1.0, 0.45, 3, (255, 194, 252, 185)),
        (134, 42, 1.0, 0.68, 4, (255, 246, 255, 210)),
        (-68, 126, -0.4, 0.88, 3, (168, 226, 255, 170)),
        (76, 116, 0.6, 0.34, 3, (255, 210, 255, 180)),
        (-28, -132, -0.2, 0.18, 3, (255, 255, 255, 205)),
        (38, -122, 0.2, 0.58, 3, (205, 240, 255, 190)),
    ]
    for ox, oy, direction, phase, s, color in particle_seed:
        drift = (frame + phase * 8) % 8
        rise = drift * 5
        fade = 1 - drift / 8
        wobble = math.sin((drift / 8) * math.tau) * 7
        px = int(cx + ox + direction * drift * 5 + wobble)
        py = int(cy + oy - rise)
        r, g, b, a = color
        draw_star(draw, px, py, (r, g, b, int(a * fade)), s=s)

    return overlay


def make_animation() -> None:
    sprite = fit_sprite(BASE_PATH)
    size = (480, 480)
    frames: list[Image.Image] = []
    overlay_frames: list[Image.Image] = []

    for i in range(8):
        canvas = Image.new("RGBA", size, (0, 0, 0, 0))
        bob = [2, 0, -2, -4, -3, -1, 1, 2][i]
        pos = center_pos(canvas, sprite, dy=bob)
        x, y = pos
        sprite_box = (x, y, x + sprite.width, y + sprite.height)

        # Glow/highlight behind sprite, still separate from the base model.
        glow_alpha = [62, 76, 92, 118, 98, 78, 66, 58][i]
        glow = tinted_glow(sprite, (230, 95, 255), glow_alpha, blur=9, expand=22)
        canvas.alpha_composite(glow, (x - 22, y - 22))

        overlay = overlay_frame(i, size, sprite_box)
        overlay_frames.append(overlay)
        canvas.alpha_composite(overlay, (0, 0))
        canvas.alpha_composite(sprite, pos)

        # A small moving highlight pass over the body, composited over sprite in preview.
        shine = Image.new("RGBA", size, (0, 0, 0, 0))
        shine_draw = ImageDraw.Draw(shine)
        sx = x + 70 + i * 18
        shine_draw.line((sx, y + 68, sx + 60, y + 216), fill=(255, 255, 255, 50), width=8)
        shine = ImageChops.multiply(shine, canvas.split()[-1].convert("RGBA"))
        canvas.alpha_composite(shine, (0, 0))

        frames.append(canvas)

    frames[0].save(
        OUT / "prion-sassy-in-game-effect-preview.gif",
        save_all=True,
        append_images=frames[1:],
        duration=120,
        loop=0,
        disposal=2,
    )
    overlay_frames[0].save(
        OUT / "prion-sassy-overlay-only-preview.gif",
        save_all=True,
        append_images=overlay_frames[1:],
        duration=120,
        loop=0,
        disposal=2,
    )

    sheet = Image.new("RGBA", (size[0] * len(frames), size[1]), (0, 0, 0, 0))
    overlay_sheet = Image.new("RGBA", (size[0] * len(frames), size[1]), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        sheet.alpha_composite(frame, (i * size[0], 0))
        overlay_sheet.alpha_composite(overlay_frames[i], (i * size[0], 0))
    sheet.save(OUT / "prion-sassy-in-game-effect-8f.png")
    overlay_sheet.save(OUT / "prion-sassy-overlay-only-8f.png")

    # Static comparison strip: clean base, overlay only, composed preview.
    bg = (250, 247, 239, 255)
    compare = Image.new("RGBA", (480 * 3, 480), bg)
    base_panel = Image.new("RGBA", size, bg)
    base_panel.alpha_composite(sprite, center_pos(base_panel, sprite))
    overlay_panel = Image.new("RGBA", size, bg)
    overlay_panel.alpha_composite(overlay_frames[3], (0, 0))
    comp_panel = Image.new("RGBA", size, bg)
    comp_panel.alpha_composite(frames[3], (0, 0))
    compare.alpha_composite(base_panel, (0, 0))
    compare.alpha_composite(overlay_panel, (480, 0))
    compare.alpha_composite(comp_panel, (960, 0))
    compare.save(OUT / "prion-sassy-base-overlay-composed-compare.png")

    # V2: no card frame. Silhouette glow + particles only.
    aura_frames: list[Image.Image] = []
    aura_overlay_frames: list[Image.Image] = []
    for i in range(8):
        canvas = Image.new("RGBA", size, (0, 0, 0, 0))
        pos = center_pos(canvas, sprite, dy=0)
        overlay = aura_overlay_frame(i, size, sprite, pos)
        aura_overlay_frames.append(overlay)
        canvas.alpha_composite(overlay, (0, 0))
        canvas.alpha_composite(sprite, pos)
        aura_frames.append(canvas)

    aura_frames[0].save(
        OUT / "prion-sassy-aura-particles-in-game-preview.gif",
        save_all=True,
        append_images=aura_frames[1:],
        duration=120,
        loop=0,
        disposal=2,
    )
    aura_overlay_frames[0].save(
        OUT / "prion-sassy-aura-particles-overlay-only-preview.gif",
        save_all=True,
        append_images=aura_overlay_frames[1:],
        duration=120,
        loop=0,
        disposal=2,
    )
    aura_sheet = Image.new("RGBA", (size[0] * len(aura_frames), size[1]), (0, 0, 0, 0))
    aura_overlay_sheet = Image.new("RGBA", (size[0] * len(aura_frames), size[1]), (0, 0, 0, 0))
    for i, frame in enumerate(aura_frames):
        aura_sheet.alpha_composite(frame, (i * size[0], 0))
        aura_overlay_sheet.alpha_composite(aura_overlay_frames[i], (i * size[0], 0))
    aura_sheet.save(OUT / "prion-sassy-aura-particles-in-game-8f.png")
    aura_overlay_sheet.save(OUT / "prion-sassy-aura-particles-overlay-only-8f.png")

    compare2 = Image.new("RGBA", (480 * 3, 480), bg)
    overlay_panel2 = Image.new("RGBA", size, bg)
    overlay_panel2.alpha_composite(aura_overlay_frames[3], (0, 0))
    comp_panel2 = Image.new("RGBA", size, bg)
    comp_panel2.alpha_composite(aura_frames[3], (0, 0))
    compare2.alpha_composite(base_panel, (0, 0))
    compare2.alpha_composite(overlay_panel2, (480, 0))
    compare2.alpha_composite(comp_panel2, (960, 0))
    compare2.save(OUT / "prion-sassy-base-aura-composed-compare.png")

    # In-game-ish preview with the real battle-map background baked in.
    battle_bg_path = Path("/Users/yukinabe/Desktop/mitoV3/MitoV3/Assets.xcassets/battle-map-bg.imageset/battle-map-bg.png")
    if battle_bg_path.exists():
        bg_src = Image.open(battle_bg_path).convert("RGBA")
        bg_src = bg_src.resize(size, Image.Resampling.BICUBIC)
    else:
        bg_src = Image.new("RGBA", size, (248, 240, 220, 255))

    game_frames: list[Image.Image] = []
    for frame in aura_frames:
        bg_frame = bg_src.copy()
        bg_frame.alpha_composite(frame, (0, 0))
        game_frames.append(bg_frame)
    game_frames[0].save(
        OUT / "prion-sassy-aura-particles-in-game-battle-bg.gif",
        save_all=True,
        append_images=game_frames[1:],
        duration=120,
        loop=0,
        disposal=2,
    )


if __name__ == "__main__":
    make_animation()
