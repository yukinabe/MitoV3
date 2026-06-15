#!/usr/bin/env python3
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "game-import-clean-hop"
APP_ASSETS = Path("/Users/yukinabe/Desktop/mitoV3/MitoV3/Assets.xcassets")

CELL_W = 200
CELL_H = 128
BASELINE = 118
FRAME_DURATIONS = [120, 95, 95, 90, 115, 90, 95, 120]

POSES = [
    # label, lift, x scale, y scale, baseline offset
    ("neutral", 0, 1.00, 1.00, 0),
    ("anticipate", 0, 1.04, 0.97, 1),
    ("charge-squash", 0, 1.10, 0.91, 2),
    ("launch", 6, 1.02, 1.03, 0),
    ("peak", 12, 0.97, 1.07, 0),
    ("fall", 7, 0.99, 1.03, 0),
    ("land-squash", 1, 1.08, 0.93, 2),
    ("settle", 0, 1.02, 0.98, 1),
]

CHARACTERS = [
    {
        "name": "hero-prion",
        "source": ROOT / "prion-sassy" / "prion-sassy-clean-base.png",
        "target_height": 88,
        "asset_dir": APP_ASSETS / "hero-prion-hop.imageset",
        "asset_file": "hero-prion-hop.png",
    },
    {
        "name": "hero-t4-phage",
        "source": ROOT / "legendary-t4-phage-biobud-clean-base.png",
        "target_height": 104,
        "asset_dir": APP_ASSETS / "hero-t4-phage-hop.imageset",
        "asset_file": "hero-t4-phage-hop.png",
    },
]


def hard_alpha(image: Image.Image) -> Image.Image:
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            pixels[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
    return image


def fitted_sprite(source: Path, target_height: int) -> Image.Image:
    image = hard_alpha(Image.open(source))
    bbox = image.getbbox()
    if bbox is None:
        raise ValueError(f"empty source: {source}")
    crop = image.crop(bbox)
    scale = target_height / crop.height
    width = max(1, round(crop.width * scale))
    height = max(1, round(crop.height * scale))
    return crop.resize((width, height), Image.Resampling.NEAREST)


def compose_frame(sprite: Image.Image, lift: int, scale_x: float, scale_y: float, baseline_offset: int) -> Image.Image:
    width = max(1, round(sprite.width * scale_x))
    height = max(1, round(sprite.height * scale_y))
    if width % 2:
        width += 1
    posed = sprite.resize((width, height), Image.Resampling.NEAREST)
    frame = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    x = (CELL_W - width) // 2
    y = BASELINE + baseline_offset - lift - height
    frame.alpha_composite(posed, (x, y))
    return frame


def write_character(config: dict) -> None:
    name = config["name"]
    char_out = OUT / name
    frames_dir = char_out / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)

    sprite = fitted_sprite(config["source"], config["target_height"])
    sprite.save(char_out / f"{name}-fitted-anchor.png")

    frames = []
    for idx, (_, lift, scale_x, scale_y, baseline_offset) in enumerate(POSES):
        frame = compose_frame(sprite, lift, scale_x, scale_y, baseline_offset)
        frame.save(frames_dir / f"{idx:02d}.png")
        frames.append(frame)

    strip = Image.new("RGBA", (CELL_W * len(frames), CELL_H), (0, 0, 0, 0))
    contact = Image.new("RGBA", (CELL_W * len(frames), CELL_H), (245, 245, 245, 255))
    for idx, frame in enumerate(frames):
        strip.alpha_composite(frame, (idx * CELL_W, 0))
        contact.alpha_composite(frame, (idx * CELL_W, 0))

    strip_path = char_out / f"{name}-hop.png"
    contact_path = char_out / f"{name}-contact.png"
    gif_path = char_out / f"{name}-preview.gif"

    strip.save(strip_path)
    contact.save(contact_path)
    frames[0].save(
        gif_path,
        save_all=True,
        append_images=frames[1:],
        duration=FRAME_DURATIONS,
        loop=0,
        disposal=2,
    )

    app_path = config["asset_dir"] / config["asset_file"]
    config["asset_dir"].mkdir(parents=True, exist_ok=True)
    strip.save(app_path)
    strip.save(ROOT / "game-import" / config["asset_file"])

    alphas = sorted({px[3] for px in strip.getdata()})
    print(f"{name}: {strip_path} -> {app_path} size={strip.size} alpha={alphas}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for config in CHARACTERS:
        write_character(config)


if __name__ == "__main__":
    main()
