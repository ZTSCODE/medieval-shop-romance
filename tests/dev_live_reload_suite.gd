extends SceneTree

# 开发用“边改边看”的两处重读（无界面）：从 CSV 重建的译文要和 Godot 导入的完全一样；重读 content.json 不改变内容。
# 运行：Godot --headless --path . --script tests/dev_live_reload_suite.gd

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var keys := _csv_keys()
	_check(keys.size() > 100, "the text table has rows")
	PlayerNameText.install()  # 游戏启动时就包好了这一层；重建后的译文也要包。
	var before := _snapshot(keys)
	var live := DevLiveReload.new()
	root.add_child(live)
	await process_frame
	var error := live.reload_translations()
	_check(error.is_empty(), "translations rebuild from the CSV: %s" % error)
	var after := _snapshot(keys)
	var different: Array[String] = []
	for key: String in before:
		if before[key] != after[key]:
			different.append(key)
	_check(different.is_empty(), "rebuilt text equals the imported text, different: %s" % [different.slice(0, 5)])
	_check(after["en:OPENING_FILM_SKIP"] == "Hold to skip" and after["zh_CN:OPENING_FILM_SKIP"] == "长按跳过", "both languages are present")
	PlayerNameText.player_name = "Rowan"
	TranslationServer.set_locale("zh_CN")
	_check(String(TranslationServer.translate("DLG_MESSENGER_CATCH_CHOICE_TELL_1")) == "Rowan。", "the player's name still replaces {name} after a rebuild")
	PlayerNameText.player_name = ""
	var cards := ContentCatalog.card_ids()
	var opening := ContentCatalog.opening_definition()
	_check(ContentCatalog.reload_base().is_empty(), "content.json reloads while running")
	_check(ContentCatalog.card_ids() == cards and ContentCatalog.opening_definition() == opening, "reloading unchanged content changes nothing")
	_check(not DialogueFlow._dialogue_definition("story.hero.thaw_edge").is_empty(), "stories are still valid after the reload")
	print("DEV_LIVE_RELOAD_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _snapshot(keys: Array[String]) -> Dictionary:
	var result := {}
	var locale := TranslationServer.get_locale()
	for code: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(code)
		for key: String in keys:
			result[code + ":" + key] = String(TranslationServer.translate(key))
	TranslationServer.set_locale(locale)
	return result


func _csv_keys() -> Array[String]:
	var keys: Array[String] = []
	var file := FileAccess.open("res://localization/game.csv", FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			keys.append(row[0])
	return keys


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL " + label)
