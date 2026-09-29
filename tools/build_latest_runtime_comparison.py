from pathlib import Path
import argparse

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    image = image.convert("RGB")
    image.thumbnail(size, Image.Resampling.LANCZOS)
    result = Image.new("RGB", size, (20, 17, 15))
    result.paste(image, ((size[0] - image.width) // 2, (size[1] - image.height) // 2))
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", default="runtime16")
    parser.add_argument("--output", default="latest-comparison-v2.png")
    parser.add_argument("--sample", default="1920-auto")
    args = parser.parse_args()
    runtime = ROOT / "outputs" / "ui-reference-preserved-20260922" / args.runtime
    output = ROOT / "outputs" / "ui-reference-preserved-20260922" / args.output
    pairs = [
        ("TABLE / HUD", ROOT / "outputs/ui-smoke-brown-suite-20260919/02-table.png", runtime / ("board-"+args.sample+".png")),
        ("RECIPES", ROOT / "outputs/ui-smoke-brown-suite-20260919/05-recipes.png", runtime / ("recipes-"+args.sample+".png")),
        ("RELATIONSHIPS", ROOT / "outputs/ui-smoke-brown-suite-20260919/04-relations.png", runtime / ("relations-"+args.sample+".png")),
    ]
    cell = (1120, 630)
    gutter = 24
    top = 64
    row_label = 34
    width = cell[0] * 2 + gutter * 3
    height = top + len(pairs) * (cell[1] + row_label + gutter)
    canvas = Image.new("RGB", (width, height), (16, 14, 13))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default(size=24)
    small = ImageFont.load_default(size=18)

    draw.text((gutter, 18), "REFERENCE", fill=(235, 225, 202), font=font)
    draw.text((gutter * 2 + cell[0], 18), "LATEST RUNTIME", fill=(235, 225, 202), font=font)

    y = top
    for label, reference_path, runtime_path in pairs:
        draw.text((gutter, y), label, fill=(183, 167, 140), font=small)
        y += row_label
        reference = fit(Image.open(reference_path), cell)
        runtime = fit(Image.open(runtime_path), cell)
        canvas.paste(reference, (gutter, y))
        canvas.paste(runtime, (gutter * 2 + cell[0], y))
        draw.rectangle((gutter, y, gutter + cell[0] - 1, y + cell[1] - 1), outline=(92, 79, 65), width=2)
        draw.rectangle(
            (gutter * 2 + cell[0], y, gutter * 2 + cell[0] * 2 - 1, y + cell[1] - 1),
            outline=(92, 79, 65),
            width=2,
        )
        y += cell[1] + gutter

    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, optimize=True)
    print(output)


if __name__ == "__main__":
    main()
