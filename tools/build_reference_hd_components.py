"""Build sharp runtime textures from the reference-locked component shapes."""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/art/ui/reference_preserved_20260922"
OUT = ROOT / "assets/art/ui/reference_runtime_hd_20260922"
OUT.mkdir(parents=True, exist_ok=True)
SCALE = 4

FILES = [
    "hud-axis-paper.png",
    "hud-recipe-button.png",
    "hud-relationship-button.png",
    "hud-avatar-frame.png",
    "journal-outer.png",
    "journal-title.png",
    "journal-selected-row.png",
    "journal-normal-row.png",
    "journal-thumbnail-paper.png",
    "journal-portrait-paper.png",
    "journal-detail-paper.png",
    "journal-close.png",
    "recipe-outer.png",
    "recipe-title.png",
    "recipe-heading.png",
    "recipe-selected-row.png",
    "recipe-normal-row.png",
    "recipe-close.png",
    "recipe-divider.png",
    "recipe-arrow.png",
]


def upscale_reference(name: str) -> dict:
    source = SOURCE / name
    image = Image.open(source).convert("RGBA")
    logical_size = image.size
    image = image.resize(
        (logical_size[0] * SCALE, logical_size[1] * SCALE),
        Image.Resampling.LANCZOS,
    )
    alpha = image.getchannel("A")
    rgb = image.convert("RGB").filter(
        ImageFilter.UnsharpMask(radius=1.1, percent=55, threshold=3)
    )
    rgb.putalpha(alpha)
    output = OUT / name
    rgb.save(output, optimize=True)
    return {
        "file": name,
        "source": str(source.relative_to(ROOT)),
        "logical_pixels": logical_size,
        "runtime_pixels": rgb.size,
        "scale": SCALE,
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    }


def main() -> None:
    components = [upscale_reference(name) for name in FILES]
    (OUT / "manifest.json").write_text(
        json.dumps({"components": components}, indent=2), encoding="utf8"
    )
    print(json.dumps({"components": len(components), "scale": SCALE}))


if __name__ == "__main__":
    main()
