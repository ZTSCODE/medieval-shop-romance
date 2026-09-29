"""运行内容模块与旧基础回归，保留日志并拒绝 Godot 的零退出码脚本错误。"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[2]
SUITES = [
    "content/module_registry_suite.gd",
    "content/catalog_context_suite.gd",
    "content/module_bundle_suite.gd",
    "content/module_story_suite.gd",
    "content/module_recipe_suite.gd",
    "content/module_sigil_suite.gd",
    "content/module_checkpoint_suite.gd",
    "content/checkpoint_cosmetic_compat_suite.gd",
    "content/module_event_effects_suite.gd",
    "content/module_event_checkpoint_suite.gd",
    "content/module_scene_scheduler_suite.gd",
    "content/module_world_factory_suite.gd",
    "content/module_action_bridge_suite.gd",
    "content/module_market_suite.gd",
    "content/module_dialogue_suite.gd",
    "content/module_dialogue_ui_suite.gd",
    "content/module_art_view_suite.gd",
    "content/parcel_story_integration_suite.gd",
    "content/chapter_operation_suite.gd",
    "content/chapter_snapshot_suite.gd",
    "content/chapter_action_operation_suite.gd",
    "content/chapter_runtime_suite.gd",
    "content/chapter_package_cache_suite.gd",
    "content/chapter_service_suite.gd",
    "content/chapter_service_snapshot_suite.gd",
    "content/chapter_relationship_suite.gd",
    "content/chapter_relationship_save_guard_suite.gd",
    "content/chapter_appointment_suite.gd",
    "content/chapter_parallel_contacts_suite.gd",
    "content/fractional_market_checkpoint_suite.gd",
    "content/workbench_service_suite.gd",
    "model_suite.gd",
    "snapshot_suite.gd",
    "opening_model_suite.gd",
    "dialogue_model_suite.gd",
    "content_progress_suite.gd",
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="C:/Users/ZTCUS/Desktop/Godot.exe")
    parser.add_argument("--output", type=Path, default=ROOT / "outputs/content-production/runtime-verification")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    for suite in SUITES:
        command = [args.godot, "--headless", "--path", str(ROOT), "--script", "res://tests/" + suite]
        started = time.monotonic()
        try:
            result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
            log = result.stdout + result.stderr
            passed = result.returncode == 0 and not re.search(r"SCRIPT ERROR|ERROR:|FAIL(?:ED)?:", log)
            code = result.returncode
        except subprocess.TimeoutExpired as error:
            log = str(error)
            passed, code = False, None
        output = args.output / (Path(suite).stem + ".log")
        output.write_text(log, encoding="utf-8")
        summaries = [line for line in log.splitlines() if re.search(r"checks|passed|failures|Passed|RESULT", line)]
        record = {"suite": suite, "passed": passed, "exit_code": code, "seconds": round(time.monotonic() - started, 2), "summary": summaries, "log": str(output.relative_to(ROOT))}
        results.append(record)
        print(json.dumps(record, ensure_ascii=True), flush=True)
    files = set(ROOT.glob("scripts/content/*.gd")) | set(ROOT.glob("data/modules/chapter_01/source/*")) | set(ROOT.glob("tests/content/*.gd")) | set(ROOT.glob("tests/fixtures/chapter_appointment_*.json")) | set(ROOT.glob("tests/fixtures/chapter_parallel_contacts_*.json"))
    files |= set(ROOT.glob("assets/art/cards/chapter_01/*.png")) | set(ROOT.glob("assets/art/characters/chapter_01/*.png"))
    for relative in ["scripts/model/table_state.gd", "scripts/model/content_catalog.gd", "scripts/view/card_content.gd", "scripts/ui/dialogue_overlay.gd", "scripts/ui/dialogue_choice_button.gd", "scripts/ui/customer_lane.gd", "scripts/table_app.gd", "scripts/table_interaction.gd", "scripts/ui/chapter_action_menu.gd", "scripts/services/game_snapshot.gd", "scripts/services/save_store.gd", "localization/game.csv", "data/modules/chapter_01/module.json"]:
        files.add(ROOT / relative)
    manifest = json.loads((ROOT / "data/modules/chapter_01/module.json").read_text(encoding="utf-8"))
    for relative in [manifest["stories"], *manifest["translations"]]:
        files.add(ROOT / "data/modules/chapter_01" / relative)
    files = sorted(files)
    fingerprints = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files if path.is_file()}
    report = {"scope": "isolated_module_and_legacy_model_regression", "main_game_chapter_integrated": "development_flag_only_see_separate_main_scene_report",
              "full_chapter_playtest_passed": False, "all_passed": all(row["passed"] for row in results),
              "results": results, "sha256": fingerprints}
    (args.output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0 if report["all_passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
