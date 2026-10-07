class_name DevLiveReload
extends CanvasLayer

# 开发用的“边改边看”：只有带 --live 启动时才会创建（见 docs/knowledge/dev-live-reload.md），正式游戏里不存在。
# 它只负责盯文件和按键，发现变化就发信号；真正怎么重读、怎么重启由 table_app 决定。
# - data/content.json、data/onboarding_goals.json 改了：游戏不重启，直接重读。
# - localization/game.csv 改了：直接从 CSV 重建译文（不用等 Godot 重新导入）。
# - work/live/restart.flag 被写入，或按 F5：存档后自动重启并回到刚才的旅程（脚本改动要靠这个生效）。
# - 按 F9：从取名之后重新开始开场，方便反复看开头的文字。
# 左上角的小字是给开发者看的状态，不是玩家界面，所以直接写英文，不走本地化表。

signal content_changed
signal goals_changed
signal restart_requested
signal replay_requested

const CONTENT_PATH := "res://data/content.json"
const GOALS_PATH := "res://data/onboarding_goals.json"
const CSV_PATH := "res://localization/game.csv"
const RESTART_FLAG := "res://work/live/restart.flag"
const POLL_SECONDS := 0.4
# 一次修改往往连着写好几个文件；等文件安静下来再重读，避免读到写了一半的内容。
const QUIET_SECONDS := 0.8

var _stamps := {}
var _dirty := {}
var _elapsed := 0.0
var _label: Label
var _message_time := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(12.0, 8.0)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	for path: String in [CONTENT_PATH, GOALS_PATH, CSV_PATH, RESTART_FLAG]:
		_stamps[path] = _stamp(path)
	say("")


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			say("")
	for path: String in _dirty.keys():
		_dirty[path] -= delta
		if _dirty[path] <= 0.0:
			_dirty.erase(path)
			_changed(path)
	_elapsed += delta
	if _elapsed < POLL_SECONDS:
		return
	_elapsed = 0.0
	for path: String in _stamps:
		var stamp := _stamp(path)
		if stamp != _stamps[path]:
			_stamps[path] = stamp
			_dirty[path] = QUIET_SECONDS


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F5:
		get_viewport().set_input_as_handled()
		restart_requested.emit()
	elif event.keycode == KEY_F9:
		get_viewport().set_input_as_handled()
		replay_requested.emit()


# 左上角的状态行；空字符串恢复成常驻的按键提示。
func say(message: String) -> void:
	if not is_instance_valid(_label):
		return
	_label.text = "LIVE   F5 restart   F9 replay opening" if message.is_empty() else "LIVE   " + message
	_message_time = 0.0 if message.is_empty() else 6.0
	if not message.is_empty():
		print("[live] " + message)


func _changed(path: String) -> void:
	match path:
		CONTENT_PATH:
			content_changed.emit()
		GOALS_PATH:
			goals_changed.emit()
		CSV_PATH:
			var error := reload_translations()
			say("text reloaded" if error.is_empty() else "text NOT reloaded: " + error)
		RESTART_FLAG:
			if FileAccess.file_exists(RESTART_FLAG):
				restart_requested.emit()


# 直接从 CSV 重建全部译文，效果与 Godot 导入器生成的 .translation 相同（首行是 key 和各语言代码）。
func reload_translations() -> String:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		return "cannot open game.csv"
	var header := file.get_csv_line()
	if header.size() < 2:
		return "game.csv has no language columns"
	var translations: Array[Translation] = []
	for column in range(1, header.size()):
		var translation := Translation.new()
		translation.locale = header[column]
		translations.append(translation)
	var rows := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 2 or row[0].is_empty():
			continue
		rows += 1
		for column in range(1, mini(row.size(), header.size())):
			if not row[column].is_empty():
				translations[column - 1].add_message(row[0], row[column].c_unescape())
	if rows == 0:
		return "game.csv is empty"
	TranslationServer.clear()
	for translation: Translation in translations:
		TranslationServer.add_translation(PlayerNameText.around(translation))
	get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	return ""


func _stamp(path: String) -> int:
	return int(FileAccess.get_modified_time(path)) if FileAccess.file_exists(path) else 0
