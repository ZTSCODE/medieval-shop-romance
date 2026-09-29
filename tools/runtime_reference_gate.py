"""Compare complete runtime captures against the approved reference coordinates.

Unlike the component source gate, this checks the pixels after Godot layout,
scaling, compositing, and rendering. Dynamic text, portraits, and discovered
content are excluded, while paper silhouettes, borders, spacing, and static
ornaments remain locked.
"""
from __future__ import annotations

from pathlib import Path
import argparse
import json

import numpy as np
from PIL import Image

import reference_component_gate as component_gate


ROOT = Path(__file__).resolve().parents[1]
REFERENCE_ROOT = ROOT / "outputs/ui-smoke-brown-suite-20260919"
OUTPUT_ROOT = ROOT / "outputs/ui-reference-gate-20260922/runtime"

SCREEN_FOR_COMPONENT = {
    "hud_axis": "board",
    "hud_recipe": "board",
    "hud_relationship": "board",
    "hud_portrait": "board",
    "relation_outer": "relations",
    "relation_title": "relations",
    "relation_selected": "relations",
    "relation_portrait": "relations",
    "relation_detail": "relations",
    "relation_close": "relations",
    "recipe_outer": "recipes",
    "recipe_title": "recipes",
    "recipe_heading": "recipes",
    "recipe_selected": "recipes",
    "recipe_close": "recipes",
    "recipe_divider": "recipes",
    "recipe_arrow": "recipes",
}

RUNTIME_EXCLUSIONS = {
    "hud_portrait": [[4, 4, 108, 186]],
}

SSIM_MINIMUM = {
    "hud_portrait": 0.0,
    "relation_title": 0.60,
    "recipe_close": 0.55,
    "recipe_divider": 0.58,
}

MAE_MAXIMUM = {
    "hud_portrait": 22.0,
}

P95_MAXIMUM = {
    "hud_portrait": 80.0,
}


def _ssim(a: np.ndarray, b: np.ndarray, mask: np.ndarray) -> float:
    scores: list[float] = []
    for y in range(0, a.shape[0] - 7, 8):
        for x in range(0, a.shape[1] - 7, 8):
            block_mask = mask[y : y + 8, x : x + 8]
            if not block_mask.all():
                continue
            aa = a[y : y + 8, x : x + 8]
            bb = b[y : y + 8, x : x + 8]
            ma, mb = aa.mean(), bb.mean()
            va, vb = aa.var(), bb.var()
            cov = ((aa - ma) * (bb - mb)).mean()
            scores.append(
                ((2 * ma * mb + 6.5025) * (2 * cov + 58.5225))
                / ((ma * ma + mb * mb + 6.5025) * (va + vb + 58.5225))
            )
    return float(np.mean(scores)) if scores else 0.0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True, type=Path)
    parser.add_argument("--sample", default="1920-auto")
    parser.add_argument("--ui-scale", default=1.0, type=float)
    args = parser.parse_args()

    runtime_root = args.runtime if args.runtime.is_absolute() else ROOT / args.runtime
    captures = {
        key: Image.open(runtime_root / f"{key}-{args.sample}.png")
        .convert("RGB")
        .resize((1672, 941), Image.Resampling.LANCZOS)
        for key in {"board", "recipes", "relations"}
    }
    reference_files = {
        "board": "02-table.png",
        "recipes": "05-recipes.png",
        "relations": "04-relations.png",
    }
    references = {
        key: Image.open(REFERENCE_ROOT / filename).convert("RGB")
        for key, filename in reference_files.items()
    }

    output_root = OUTPUT_ROOT / args.sample
    output_root.mkdir(parents=True, exist_ok=True)
    results: list[dict] = []
    for name, screen in SCREEN_FOR_COMPONENT.items():
        _, box = component_gate.PARTS[name]
        ref = references[screen].crop(box)
        if args.ui_scale == 1.0:
            actual_box = box
        elif screen == "board":
            source_left = 1531.5
            source_top = 107.0
            source_bottom = 835.0
            group_top = (941.0 - (source_bottom - source_top) * args.ui_scale) * 0.5
            actual_box = (
                round(1672.0 - (1672.0 - box[0]) * args.ui_scale),
                round(group_top + (box[1] - source_top) * args.ui_scale),
                round(1672.0 - (1672.0 - box[2]) * args.ui_scale),
                round(group_top + (box[3] - source_top) * args.ui_scale),
            )
        else:
            center_x, center_y = 836.0, 470.5
            actual_box = (
                round(center_x + (box[0] - center_x) * args.ui_scale),
                round(center_y + (box[1] - center_y) * args.ui_scale),
                round(center_x + (box[2] - center_x) * args.ui_scale),
                round(center_y + (box[3] - center_y) * args.ui_scale),
            )
        actual = captures[screen].crop(actual_box).resize(ref.size, Image.Resampling.LANCZOS)
        a = np.asarray(ref, dtype=float)
        b = np.asarray(actual, dtype=float)
        mask = np.ones(a.shape[:2], dtype=bool)
        exclusions = RUNTIME_EXCLUSIONS.get(
            name, component_gate.EXCLUSIONS.get(name, [])
        )
        for x0, y0, x1, y1 in exclusions:
            mask[y0:y1, x0:x1] = False
        error = np.abs(a - b)
        mae = float(error[mask].mean())
        p95 = float(np.percentile(error[mask], 95))
        ssim = _ssim(a.mean(2), b.mean(2), mask)
        passing = (
            mae <= MAE_MAXIMUM.get(name, 16.0)
            and p95 <= P95_MAXIMUM.get(name, 52.0)
            and ssim >= SSIM_MINIMUM.get(name, 0.72)
        )
        result = {
            "component": name,
            "screen": screen,
            "mae": mae,
            "p95_error": p95,
            "ssim_8x8": ssim,
            "runtime_gate": "pass" if passing else "fail",
        }
        results.append(result)
        contact = Image.new("RGB", (ref.width * 3, ref.height))
        contact.paste(ref, (0, 0))
        contact.paste(actual, (ref.width, 0))
        heat = np.zeros_like(a, dtype=np.uint8)
        heat[:, :, 0] = np.clip(error.mean(2) * 4, 0, 255).astype(np.uint8)
        heat[~mask] = (42, 66, 88)
        contact.paste(Image.fromarray(heat), (ref.width * 2, 0))
        contact.save(output_root / f"{name}.png")

    passed = [item["component"] for item in results if item["runtime_gate"] == "pass"]
    summary = {
        "runtime": str(runtime_root),
        "sample": args.sample,
        "passed": len(passed),
        "total": len(results),
        "passing_components": passed,
        "failing_components": [
            item["component"] for item in results if item["runtime_gate"] != "pass"
        ],
        "results": results,
    }
    (output_root / "summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf8"
    )
    print(json.dumps(summary, ensure_ascii=False))
    raise SystemExit(0 if len(passed) == len(results) else 1)


if __name__ == "__main__":
    main()
