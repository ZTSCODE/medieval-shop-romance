from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/art/ui/forest_rebuild"
TARGET = SOURCE / "prepared"


def main() -> None:
    TARGET.mkdir(exist_ok=True)
    for name in ("card-sage-paper.png", "card-gold-outline.png"):
        image = Image.open(SOURCE / name).convert("RGBA")
        pixels = bytearray(image.tobytes())
        for offset in range(0, len(pixels), 4):
            if name == "card-sage-paper.png":
                if pixels[offset + 3] > 204:
                    pixels[offset + 3] = 255
            else:
                pixels[offset] = 240
                pixels[offset + 1] = 201
                pixels[offset + 2] = 115
        output = Image.frombytes("RGBA", image.size, bytes(pixels))
        output.save(TARGET / name, optimize=True)
        print(f"Prepared {name}: {image.width}x{image.height}")


if __name__ == "__main__":
    main()
