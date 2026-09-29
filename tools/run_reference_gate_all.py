from pathlib import Path
import json

import reference_component_gate as gate


ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / "assets/art/ui/reference_preserved_20260922"
MAPPING = {
    "hud_axis": "hud-axis-paper.png",
    "hud_recipe": "hud-recipe-button.png",
    "hud_relationship": "hud-relationship-button.png",
    "hud_portrait": "hud-avatar-frame.png",
    "relation_outer": "journal-outer.png",
    "relation_title": "journal-title.png",
    "relation_selected": "journal-selected-row.png",
    "relation_normal": "journal-normal-row.png",
    "relation_portrait": "journal-portrait-paper.png",
    "relation_detail": "journal-detail-paper.png",
    "relation_close": "journal-close.png",
    "recipe_outer": "recipe-outer.png",
    "recipe_title": "recipe-title.png",
    "recipe_heading": "recipe-heading.png",
    "recipe_selected": "recipe-selected-row.png",
    "recipe_normal": "recipe-normal-row.png",
    "recipe_close": "recipe-close.png",
    "recipe_divider": "recipe-divider.png",
    "recipe_arrow": "recipe-arrow.png",
}


def main() -> None:
    locked = json.loads((gate.OUT / "components.json").read_text(encoding="utf8"))
    results = []
    for part, filename in MAPPING.items():
        results.append(gate.compare(part, ASSET / filename, locked[part]["exclusions"]))
    passed = [result["component"] for result in results if result["numeric_gate"] == "pass"]
    summary = {
        "passed": len(passed),
        "total": len(results),
        "passing_components": passed,
        "failing_components": [result["component"] for result in results if result["numeric_gate"] != "pass"],
    }
    (gate.OUT / "latest-numeric-summary.json").write_text(json.dumps(summary, indent=2), encoding="utf8")
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
