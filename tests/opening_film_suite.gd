extends SceneTree

# 开场动画的数据与流程检查（无界面）：使用真实 data/content.json 与 localization/game.csv，不读写玩家存档。
# 运行：Godot --headless --path . --script tests/opening_film_suite.gd

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_definition()
	_test_finish_intro()
	print("OPENING_FILM_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_definition() -> void:
	var definition := ContentCatalog.opening_definition()
	var film: Dictionary = definition.get("film", {})
	_check(OpeningFlow._definition_valid(definition), "opening definition still valid with a film")
	_check(film.get("video") is String and ResourceLoader.exists(String(film.get("video", ""))), "film video exists and is imported")
	_check(OpeningFilmView.available(definition), "film view reports the film as available")
	var captions: Array = film.get("captions", [])
	_check(captions.size() > 0, "film has captions")
	var keys := _csv_rows()
	var ordered := true
	var localized := true
	var previous_end := 0.0
	for entry: Variant in captions:
		if not entry is Dictionary or float(entry.start) < previous_end or float(entry.end) <= float(entry.start):
			ordered = false
			break
		previous_end = float(entry.end)
		var row: Array = keys.get(String(entry.key), [])
		if row.size() < 3 or String(row[1]).is_empty() or String(row[2]).is_empty():
			localized = false
	_check(ordered, "captions are in order and never overlap")
	_check(localized, "every caption has Chinese and English text")
	_check(keys.has(String(film.get("skip_key", ""))), "skip button text is localized")
	var title: Dictionary = film.get("title", {})
	var name_row: Array = keys.get(String(title.get("key", "")), [])
	_check(name_row.size() >= 3 and not String(name_row[1]).is_empty() and not String(name_row[2]).is_empty(), "the game name shown at the end is localized")
	_check(float(title.get("start", -1.0)) > previous_end, "the name appears after the last caption")
	_check(OpeningFlow.intro_page_count() == int(definition.get("name_entry_page", -1)), "naming still follows the whole prologue")


func _test_finish_intro() -> void:
	var paged := OpeningFlow.new()
	paged.start(TableState.new())
	for i in OpeningFlow.intro_page_count():
		paged.advance_intro()
	for start_page in [0, 2]:
		var flow := OpeningFlow.new()
		flow.start(TableState.new())
		for i in start_page:
			flow.advance_intro()
		_check(flow.stage == &"intro", "film starts inside the prologue (from page %d)" % start_page)
		flow.finish_intro()
		_check(flow.stage == paged.stage and flow.intro_index == paged.intro_index, "finishing the film equals reading every page (from page %d)" % start_page)
		_check(flow.to_data() == paged.to_data(), "and saves the same state (from page %d)" % start_page)
		flow.finish_intro()
		_check(flow.stage == paged.stage, "finishing twice changes nothing (from page %d)" % start_page)


func _csv_rows() -> Dictionary:
	var rows := {}
	var file := FileAccess.open("res://localization/game.csv", FileAccess.READ)
	while file != null and not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 3:
			rows[row[0]] = Array(row)
	return rows


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)
