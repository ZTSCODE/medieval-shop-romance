from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import string
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "docs/content_design/script"
BUILD_ROOT = ROOT / "data/modules/chapter_01/builds"
REPORT_ROOT = ROOT / "outputs/content-production/script"
SPEAKERS = {"narrator", "hero", "npc.messenger", "npc.springwright", "npc.hearthkeeper"}
STAGE_BEATS = (
    ("arrival.road", "arrival.exchange", "arrival.shelter", "arrival.bound_fire"),
    ("workshop.try", "workshop.parcel", "workshop.supper", "workshop.permission"),
    ("basin.arrival", "basin.cloth", "basin.help", "basin.confidence"),
    ("market.notice", "market.first_order", "market.shared_work", "market.stay"),
    ("storm.warning", "storm.test", "storm.delivery", "storm.choice"),
    ("agreement.table", "agreement.offer", "agreement.boundary", "agreement.invitation"),
    ("search.arrival", "search.prepare", "search.alibi", "search.trust"),
    ("shelter.complete", "shelter.promise", "shelter.meeting", "shelter.morning"),
)
CORE_STAGES = {"story.ch01." + beat: stage for stage, beats in enumerate(STAGE_BEATS, 1) for beat in beats}
OPTIONAL_STAGES = {"story.ch01." + phase + "." + slug: 9
                   for phase in ("contact_request", "contact_visit", "return_visit")
                   for slug in ("corin", "oren", "bram")}
EXPECTED_STAGES = {**CORE_STAGES, **OPTIONAL_STAGES}
EXCLUSIVE_FACTS = (
    {"fact.ch01.conflict.disarm", "fact.ch01.conflict.isolate"},
    {"fact.ch01.contact_interest.corin_maps", "fact.ch01.contact_interest.corin_rest"},
    {"fact.ch01.contact_interest.oren_music", "fact.ch01.contact_interest.oren_craft"},
    {"fact.ch01.contact_interest.bram_food", "fact.ch01.contact_interest.bram_stories"},
    *({"fact.ch01.contact_visit." + slug + ".friendship", "fact.ch01.contact_visit." + slug + ".personal"}
      for slug in ("corin", "oren", "bram")),
)
ACTION_KINDS = {"explore", "gather", "craft", "transfer", "repair", "trade", "visit", "choice", "conflict"}
WORD = re.compile(r"[A-Za-z0-9]+(?:['’\-][A-Za-z0-9]+)*")
LOCAL_ID = re.compile(r"[a-z][a-z0-9_]*\Z")
FACT_ID = re.compile(r"fact\.ch01\.[a-z0-9_.]+\Z")


class CompileError(ValueError):
    pass


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        demand(key not in result, "duplicate_json_key: " + key)
        result[key] = value
    return result


def demand(ok, message):
    if not ok:
        raise CompileError(message)


def words(value):
    return len(WORD.findall(value))


def placeholders(value):
    try:
        return sorted(field for _, field, _, _ in string.Formatter().parse(value) if field is not None)
    except ValueError as exc:
        raise CompileError("invalid_format_placeholder") from exc


def validate_text(value, where):
    demand(isinstance(value, dict), where + ": not_object")
    for lang in ("en", "zh"):
        demand(isinstance(value.get(lang), str) and value[lang].strip(), where + ": missing_" + lang)
    demand(placeholders(value["en"]) == placeholders(value["zh"]), where + ": translation_placeholder_mismatch")


def validate_facts(value, where, reject_conflicts=True):
    demand(isinstance(value, list), where + ": facts_not_list")
    demand(all(isinstance(f, str) and FACT_ID.fullmatch(f) for f in value), where + ": invalid_fact_id")
    demand(len(value) == len(set(value)), where + ": duplicate_fact")
    if reject_conflicts:
        for group in EXCLUSIVE_FACTS:
            demand(len(group.intersection(value)) < 2, where + ": mutually_exclusive_facts")


def edges(node):
    if "choices" in node:
        return [c["next"] for c in node["choices"]]
    if "cases" in node:
        return [c["next"] for c in node["cases"]] + [node["fallback"]]
    return [node["next"]]


def conditions_overlap(a, b):
    positive = set(a["all"]) | set(b["all"])
    negative = set(a["none"]) | set(b["none"])
    if positive & negative:
        return False
    return not any(len(positive & group) > 1 for group in EXCLUSIVE_FACTS)


def validate_scene(scene):
    demand(isinstance(scene, dict), "scene_not_object")
    sid = scene.get("id")
    demand(sid in EXPECTED_STAGES, "unknown_scene_id: " + str(sid))
    demand(type(scene.get("stage")) is int and scene["stage"] == EXPECTED_STAGES[sid], sid + ": wrong_stage")
    demand(scene.get("completion_event") == sid.replace("story.", "event.", 1) + ".complete", sid + ": bad_completion_event")
    demand(isinstance(scene.get("summary_zh"), str) and scene["summary_zh"].strip(), sid + ": missing_editor_summary")
    action = scene.get("board_action", {})
    demand(isinstance(action, dict) and action.get("kind") in ACTION_KINDS, sid + ": invalid_board_action")
    demand(action.get("timing") in ("before", "during", "after"), sid + ": invalid_action_timing")
    demand(isinstance(action.get("summary_zh"), str) and action["summary_zh"].strip(), sid + ": missing_action_summary")
    raw = scene.get("nodes")
    demand(isinstance(raw, list) and raw, sid + ": missing_nodes")
    nodes = {}
    for node in raw:
        demand(isinstance(node, dict), sid + ": node_not_object")
        nid = node.get("id")
        demand(isinstance(nid, str) and LOCAL_ID.fullmatch(nid), sid + ": invalid_node_id")
        demand(nid not in nodes, sid + ": duplicate_node: " + nid)
        nodes[nid] = node
        where = sid + "/" + nid
        kinds = sum(key in node for key in ("speaker", "choices", "cases", "action_id"))
        demand(kinds == 1, where + ": ambiguous_node_kind")
        if "speaker" in node:
            demand(node["speaker"] in SPEAKERS, where + ": unknown_speaker")
            validate_text(node, where)
            demand(isinstance(node.get("next"), str), where + ": next_not_string")
        elif "choices" in node:
            choices = node["choices"]
            demand(isinstance(choices, list) and 2 <= len(choices) <= 3, where + ": choice_count")
            seen = set()
            for choice in choices:
                validate_text(choice, where)
                cid = choice.get("id")
                demand(isinstance(cid, str) and LOCAL_ID.fullmatch(cid), where + ": invalid_choice_id")
                demand(cid not in seen, where + ": duplicate_choice_id")
                seen.add(cid)
                demand(isinstance(choice.get("next"), str) and choice["next"], where + ": choice_missing_response")
                validate_facts(choice.get("facts"), where)
        elif "action_id" in node:
            demand(isinstance(node["action_id"], str) and re.fullmatch(r"action\.ch01\.[a-z0-9_.]+", node["action_id"]), where + ": invalid_action_id")
            demand(isinstance(node.get("next"), str), where + ": action_next_not_string")
        else:
            cases = node["cases"]
            demand(isinstance(cases, list) and cases, where + ": empty_cases")
            for case in cases:
                demand(isinstance(case, dict), where + ": case_not_object")
                validate_facts(case.get("all"), where)
                validate_facts(case.get("none"), where, reject_conflicts=False)
                demand(bool(case["all"] or case["none"]), where + ": unconditional_case")
                demand(not set(case["all"]) & set(case["none"]), where + ": impossible_case")
                demand(isinstance(case.get("next"), str), where + ": case_next_not_string")
            for index, case in enumerate(cases):
                for other in cases[index + 1:]:
                    demand(not conditions_overlap(case, other), where + ": ambiguous_conditions")
            demand(isinstance(node.get("fallback"), str) and node["fallback"], where + ": missing_fallback")
    entry = scene.get("entry")
    demand(entry in nodes, sid + ": missing_entry")
    demand(action["timing"] != "during" or any("action_id" in n for n in raw), sid + ": during_without_action_gate")
    for nid, node in nodes.items():
        for target in edges(node):
            demand(target == "" or target in nodes, sid + "/" + nid + ": missing_target: " + str(target))
    visiting, visited = set(), set()

    def walk(nid):
        if nid == "":
            return
        demand(nid not in visiting, sid + ": cycle: " + nid)
        if nid in visited:
            return
        visiting.add(nid)
        for target in edges(nodes[nid]):
            walk(target)
        visiting.remove(nid)
        visited.add(nid)

    walk(entry)
    demand(visited == set(nodes), sid + ": unreachable_nodes: " + ",".join(sorted(set(nodes) - visited)))
    return nodes


def word_bounds(scene):
    nodes = {node["id"]: node for node in scene["nodes"]}
    cache = {"": (0, 0)}

    def visit(nid):
        if nid in cache:
            return cache[nid]
        node = nodes[nid]
        own = words(node["en"]) if "speaker" in node else 0
        alternatives = []
        if "choices" in node:
            for choice in node["choices"]:
                low, high = visit(choice["next"])
                alternatives.append((low + words(choice["en"]), high + words(choice["en"])))
        else:
            alternatives = [visit(target) for target in edges(node)]
        cache[nid] = (own + min(p[0] for p in alternatives), own + max(p[1] for p in alternatives))
        return cache[nid]

    return visit(scene["entry"])


def read_default_path(scene, facts):
    nodes = {node["id"]: node for node in scene["nodes"]}
    nid, total, spoken, choices_count, pages = scene["entry"], 0, 0, 0, []
    while nid:
        node = nodes[nid]
        if "speaker" in node:
            count = words(node["en"])
            total += count
            spoken += count if node["speaker"] != "narrator" else 0
            pages.append((nid, count, node["speaker"]))
            nid = node["next"]
        elif "choices" in node:
            choice = node["choices"][0]
            total += words(choice["en"])
            choices_count += 1
            for group in EXCLUSIVE_FACTS:
                demand(len((facts | set(choice["facts"])) & group) < 2, scene["id"] + ": contradictory_route_facts")
            facts.update(choice["facts"])
            nid = choice["next"]
        elif "action_id" in node:
            nid = node["next"]
        else:
            matches = [c for c in node["cases"] if set(c["all"]) <= facts and not set(c["none"]) & facts]
            demand(len(matches) <= 1, scene["id"] + ": ambiguous_route_dispatch")
            nid = matches[0]["next"] if matches else node["fallback"]
    return total, spoken, choices_count, pages


def text_key(*parts):
    return "CH01_" + "_".join(parts).replace("story.ch01.", "").replace(".", "_").upper()


def compile_documents(documents, require_complete=True):
    scenes, scene_ids, inputs = [], set(), []
    for label, document in documents:
        demand(isinstance(document, dict) and type(document.get("schema_version")) is int and document["schema_version"] == 1, label + ": schema_version")
        demand(document.get("module_id") == "chapter_01", label + ": module_id")
        demand(document.get("source_language") == "en", label + ": source_language")
        demand(isinstance(document.get("scenes"), list), label + ": scene_list")
        for scene in document["scenes"]:
            validate_scene(scene)
            demand(scene["id"] not in scene_ids, "duplicate_scene: " + scene["id"])
            scene_ids.add(scene["id"])
            scenes.append(scene)
        inputs.append({"path": label, "sha256": hashlib.sha256(json.dumps(document, ensure_ascii=False, sort_keys=True).encode()).hexdigest(),
                       "sha256_kind": "canonical_json_sorted_keys_utf8"})
    missing = sorted(set(CORE_STAGES) - scene_ids)
    demand(not require_complete or not missing, "missing_scenes: " + ",".join(missing))
    order = {sid: i for i, sid in enumerate(EXPECTED_STAGES)}
    scenes.sort(key=lambda scene: order[scene["id"]])
    graph, translations, metrics, editorial = {}, {}, [], []
    facts, total_words, spoken_words, total_choices = set(), 0, 0, 0

    def add_text(key, source):
        demand(key not in translations, "duplicate_translation_key: " + key)
        translations[key] = (source["en"], source["zh"])

    for scene in scenes:
        sid = scene["id"]
        compiled_nodes = {}
        for node in scene["nodes"]:
            nid = node["id"]
            if "speaker" in node:
                key = text_key(sid, nid)
                add_text(key, node)
                compiled_nodes[nid] = {"type": "line", "speaker": node["speaker"], "text_key": key, "next": node["next"]}
            elif "choices" in node:
                choices = []
                for choice in node["choices"]:
                    key = text_key(sid, nid, choice["id"])
                    add_text(key, choice)
                    choices.append({"id": choice["id"], "text_key": key, "next": choice["next"], "facts": choice["facts"]})
                compiled_nodes[nid] = {"type": "choice", "choices": choices}
            elif "action_id" in node:
                compiled_nodes[nid] = {"type": "action", "action_id": node["action_id"], "next": node["next"]}
            else:
                compiled_nodes[nid] = {"type": "condition", "cases": node["cases"], "fallback": node["fallback"]}
        graph[sid] = {"id": sid, "stage": scene["stage"], "entry": scene["entry"], "nodes": compiled_nodes,
                      "completion_event": scene["completion_event"]}
        low, high = word_bounds(scene)
        route_facts = facts if sid in CORE_STAGES else facts.copy()
        count, spoken, choices_count, pages = read_default_path(scene, route_facts)
        if sid in CORE_STAGES:
            total_words += count
            spoken_words += spoken
            total_choices += choices_count
        library_words = sum(words(n["en"]) if "speaker" in n else sum(words(c["en"]) for c in n.get("choices", [])) for n in scene["nodes"])
        long_pages = [{"node": n["id"], "words": words(n["en"])} for n in scene["nodes"] if "speaker" in n and words(n["en"]) > 65]
        metrics.append({"id": sid, "stage": scene["stage"], "default_route_words": count, "spoken_words": spoken,
                        "scene_local_lower_bound": low, "scene_local_upper_bound": high, "library_words": library_words,
                        "default_choice_count": choices_count, "node_count": len(scene["nodes"]), "long_pages": long_pages,
                        "action_gates": [n["action_id"] for n in scene["nodes"] if "action_id" in n]})
        editorial.append({"id": sid, "summary_zh": scene["summary_zh"], "board_action": scene["board_action"],
                          "action_ids": [n["action_id"] for n in scene["nodes"] if "action_id" in n], "action_binding_status": "not_implemented"})
    demand(bool(scenes), "no_scenes")
    csv_buffer = io.StringIO(newline="")
    writer = csv.writer(csv_buffer, lineterminator="\n")
    writer.writerow(["keys", "en", "zh_CN"])
    for key, values in sorted(translations.items()):
        writer.writerow([key, *values])
    report = {"schema_version": 1, "status": "compiled_draft_not_runtime_or_editorial_acceptance", "complete_scene_set": not missing,
              "missing_scenes": missing, "scene_count": len(scenes), "translation_count": len(translations),
              "default_route_words": total_words, "default_spoken_words": spoken_words,
              "default_choice_count": total_choices, "library_words": sum(m["library_words"] for m in metrics),
              "pure_reading_minutes_at_190_wpm": round(total_words / 190, 2),
              "route_scope": "core 32 first-choice scenes only; optional visits are separate and no board-action timing or quest reachability is proved",
              "bounds_scope": "scene-local bounds include conditional alternatives; not certified chapter branches",
              "facts_on_default_route": sorted(facts), "scenes": metrics, "inputs": inputs}
    return {"stories": graph, "exclusive_fact_groups": [sorted(g) for g in EXCLUSIVE_FACTS]}, csv_buffer.getvalue(), report, editorial


def build(source_dir=SOURCE_DIR, output_root=BUILD_ROOT, report_root=REPORT_ROOT, require_complete=True):
    files = sorted(source_dir.glob("ch01-act-*.json"))
    demand(bool(files), "no_script_sources")
    documents = [(path.name, json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object)) for path in files]
    graph, csv_text, report, editorial = compile_documents(documents, require_complete)
    graph_text = json.dumps(graph, ensure_ascii=False, indent=2) + "\n"
    digest = hashlib.sha256((graph_text + csv_text).encode()).hexdigest()
    output = output_root / digest[:16]
    output.mkdir(parents=True, exist_ok=True)
    report_root.mkdir(parents=True, exist_ok=True)
    (output / "stories.json").write_text(graph_text, encoding="utf-8")
    (output / "localization.csv").write_text(csv_text, encoding="utf-8-sig", newline="")
    manifest = {"id": "chapter_01", "schema_version": 1, "version": "0.1.0-draft", "enabled_by_default": False,
                "status": "authoring_build_not_integrated", "source_language": "en", "languages": ["en", "zh_CN"],
                "stories": "stories.json", "translations": "localization.csv", "content_sha256": digest,
                "runtime_requirements": ["module_registry", "branch_dialogue_runtime", "board_action_bindings", "save_migration"],
                "base_dependencies": ["card.hero", "card.messenger", "npc.messenger"],
                "missing_production_assets": ["npc.springwright", "npc.hearthkeeper"], "source_provenance": report["inputs"]}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    report["build_directory"] = str(output)
    report["content_sha256"] = digest
    (report_root / "script-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (report_root / "action-bindings-pending.json").write_text(json.dumps(editorial, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (report_root / "chapter-manuscript.md").write_text(render_manuscript(documents, report), encoding="utf-8")
    return report


def render_manuscript(documents, report):
    names = {"narrator": "旁白", "hero": "主角", "npc.messenger": "科林", "npc.springwright": "欧伦", "npc.hearthkeeper": "布拉姆"}
    rows = ["# 第一章英中剧本审阅稿", "", "编辑稿，尚未接入游戏。以下列出全部分支，节点跳转按箭头读取；互斥对白不会在一次游玩中全部出现。", "",
            f"当前默认选择文本路线：{report['default_route_words']}英文词；全部分支库：{report['library_words']}词。这里不把未选分支计入该路线。", ""]
    stage = None
    scenes = [scene for _, doc in documents for scene in doc["scenes"]]
    order = {sid: i for i, sid in enumerate(EXPECTED_STAGES)}
    for scene in sorted(scenes, key=lambda s: order[s["id"]]):
        if scene["stage"] != stage:
            stage = scene["stage"]
            rows.extend([f"## 阶段 {stage}", ""])
        rows.extend([f"### {scene['id']}", "", "**编辑说明：** " + scene["summary_zh"], "",
                     "**牌桌动作：** " + scene["board_action"]["summary_zh"], ""])
        for node in scene["nodes"]:
            rows.extend([f"#### {node['id']}", ""])
            if "speaker" in node:
                rows.extend([f"**{names[node['speaker']]}**", "", node["en"], "", "> " + node["zh"].replace("\n", "\n> "), "",
                             "下一节点：`" + (node["next"] or "结束本场") + "`", ""])
            elif "choices" in node:
                for choice in node["choices"]:
                    rows.extend([f"- **{choice['id']}** → `{choice['next']}`：{choice['en']}", "  " + choice["zh"], ""])
            elif "action_id" in node:
                rows.extend([f"实际操作门：`{node['action_id']}`。成功后 → `{node['next']}`；不能用继续按钮代替卡牌操作。", ""])
            else:
                for case in node["cases"]:
                    rows.append(f"- 需要 {', '.join(case['all']) or '无'}，排除 {', '.join(case['none']) or '无'} → `{case['next']}`")
                rows.extend([f"- 其他情况 → `{node['fallback']}`", ""])
    return "\n".join(rows) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SOURCE_DIR)
    parser.add_argument("--output", type=Path, default=BUILD_ROOT)
    parser.add_argument("--report", type=Path, default=REPORT_ROOT)
    parser.add_argument("--allow-partial", action="store_true")
    args = parser.parse_args()
    try:
        report = build(args.source, args.output, args.report, not args.allow_partial)
    except (CompileError, OSError, json.JSONDecodeError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=True))
        return 1
    print(json.dumps({key: report[key] for key in ("status", "scene_count", "translation_count", "default_route_words", "library_words", "build_directory")}, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
