"""Validate independently generated UI components before Godot integration."""
from pathlib import Path
import json

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets/art/ui/independent_components_20260922"
REPORT = ROOT / "outputs/ui-independent-components-20260922/asset-gate.json"

COMPONENTS = {
    "hud/day-night-axis-paper-v2.png": (102, 285),
    "hud/recipe-button-paper-v1.png": (101, 103),
    "hud/relationship-button-paper-v2.png": (100, 91),
    "hud/portrait-frame-paper-v1.png": (112, 190),
    "hud/portrait-name-tag-v1.png": (112, 35),
    "hud/sun-glyph-v1.png": (128, 128),
    "hud/moon-glyph-v1.png": (128, 128),
    "hud/recipe-glyph-v1.png": (128, 128),
    "hud/relationship-glyph-v1.png": (128, 128),
    "relation/relation-window-outer-v2.png": (1112, 573),
    "relation/relation-title-plaque-v2.png": (222, 60),
    "relation/relation-row-selected-v2.png": (262, 136),
    "relation/relation-row-normal-v2.png": (262, 139),
    "relation/relation-portrait-backing.png": (139, 119),
    "relation/relation-fullbody-backing.png": (320, 465),
    "relation/relation-detail-paper.png": (425, 484),
    "relation/relation-close-strip.png": (103, 55),
    "recipe/recipe-window-outer.png": (1135, 571),
    "recipe/recipe-title-tag.png": (222, 62),
    "recipe/recipe-discovered-header.png": (261, 54),
    "recipe/recipe-row-selected.png": (278, 111),
    "recipe/recipe-row-normal.png": (278, 115),
    "recipe/recipe-close-strip.png": (117, 56),
    "recipe/recipe-divider.png": (50, 490),
    "recipe/recipe-arrow-right.png": (49, 43),
}


def inspect(relative: str, logical: tuple[int, int]) -> dict:
    path = ASSET_ROOT / relative
    result = {"file": relative, "logical": logical, "checks": {}}
    result["checks"]["exists"] = path.is_file()
    if not path.is_file():
        result["passed"] = False
        return result
    image = Image.open(path).convert("RGBA")
    pixels = np.asarray(image)
    alpha = pixels[:, :, 3]
    perimeter = np.concatenate((alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]))
    bbox = image.getchannel("A").getbbox()
    opaque = alpha >= 32
    luminance = (
        pixels[:, :, 0].astype(float) * 0.2126
        + pixels[:, :, 1].astype(float) * 0.7152
        + pixels[:, :, 2].astype(float) * 0.0722
    )
    gx = np.abs(np.diff(luminance, axis=1))
    gy = np.abs(np.diff(luminance, axis=0))
    detail = float((gx.mean() + gy.mean()) * 0.5)
    detail_minimum = 0.20 if "glyph" in relative else 0.35
    minimum = (logical[0] * 4, logical[1] * 4)
    result.update({"pixels": image.size, "alpha_bbox": bbox, "detail_energy": detail})
    result["checks"].update(
        {
            "rgba": image.mode == "RGBA",
            "at_least_4x": image.width >= minimum[0] and image.height >= minimum[1],
            "transparent_perimeter": int(perimeter.max()) == 0,
            "has_visible_content": bool(opaque.any()),
            "not_clipped": bbox is not None
            and bbox[0] > 0
            and bbox[1] > 0
            and bbox[2] < image.width
            and bbox[3] < image.height,
            "has_painted_detail": detail >= detail_minimum,
        }
    )
    result["passed"] = all(result["checks"].values())
    return result


def main() -> None:
    results = [inspect(name, logical) for name, logical in COMPONENTS.items()]
    banned_roots = (
        "reference_runtime_hd_20260922",
        "reference_preserved_20260922",
        "reference_parts_20260922",
    )
    active_crop_references = []
    for script in (ROOT / "scripts/ui").glob("*.gd"):
        text = script.read_text(encoding="utf8")
        if any(token in text for token in banned_roots):
            active_crop_references.append(str(script.relative_to(ROOT)))
    summary = {
        "passed": sum(1 for item in results if item["passed"]),
        "total": len(results),
        "failed": [item["file"] for item in results if not item["passed"]],
        "active_crop_references": active_crop_references,
        "components": results,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf8")
    print(json.dumps({key: summary[key] for key in ("passed", "total", "failed", "active_crop_references")}, ensure_ascii=False))
    raise SystemExit(0 if not summary["failed"] and not active_crop_references else 1)


if __name__ == "__main__":
    main()
