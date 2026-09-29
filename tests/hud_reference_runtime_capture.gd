extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

var app: Node
var failures := 0
const OUTPUT := "res://outputs/hud-ui-20260929/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1672, 941)
	TranslationServer.set_locale("zh_CN")
	var translations := Translation.new()
	translations.locale = "zh_CN"
	var rows := FileAccess.open("res://tests/fixtures/hud_player_preview.csv", FileAccess.READ)
	rows.get_csv_line()
	while not rows.eof_reached():
		var row := rows.get_csv_line()
		if row.size() == 2:
			translations.add_message(row[0], row[1])
	TranslationServer.add_translation(translations)
	app = PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	await create_timer(0.7).timeout
	app._commit_new_journey(tr("HUD_PREVIEW_PLAYER_NAME"))
	var content: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/hud_player_preview.json"))
	var registered := ContentCatalog.enable_module("hud_preview", content)
	_check("preview player module registered", registered.ok)
	app.overlay.player_hud.portrait.queue_redraw()
	await create_timer(1.8).timeout
	_check("isolated save profile", app.qa_mode)
	_check("player portrait loaded", GameArt.portrait("hero") != null)
	_check("player name displayed", app.overlay.player_hud.name_label.text == tr("HUD_PREVIEW_PLAYER_NAME"))
	_check_column_centered("desktop column vertically centered")
	_check("single time button inside paper", app.overlay.day_progress.get_global_rect().encloses(app.overlay.time_cycle_button.get_global_rect()))
	await _shot("01-hud-in-game.png")
	app.set_game_paused(true)
	await create_timer(0.4).timeout
	await _shot("02-hud-with-pause.png")
	app.set_game_paused(false)
	if "--preview-hold" in OS.get_cmdline_user_args():
		print("HUD preview ready")
		return
	app.overlay.time_cycle_button.pressed.emit()
	_check("normal cycles to triple", not app._time_paused and app._game_speed == 3.0 and app.board.simulation_speed == 3.0)
	_check("triple label", app.overlay.time_cycle_button.text == tr("HUD_TIME_SPEED_THREE"))
	_check("triple generated icon", app.overlay.time_cycle_button._state == "speed-3x" and app.overlay.time_cycle_button._glyph.texture != null)
	await _shot("04-hud-triple.png")
	app.overlay.time_cycle_button.pressed.emit()
	_check("triple cycles to paused", app._time_paused and app.board.simulation_paused)
	_check("paused label", app.overlay.time_cycle_button.text == tr("HUD_TIME_STATE_PAUSED"))
	_check("pause generated icon", app.overlay.time_cycle_button._state == "pause")
	await _shot("05-hud-time-paused.png")
	app.overlay.time_cycle_button.pressed.emit()
	_check("paused cycles to normal", not app._time_paused and not app.board.simulation_paused and app._game_speed == 1.0)
	_check("normal label", app.overlay.time_cycle_button.text == tr("HUD_TIME_SPEED_ONE"))
	app.set_game_paused(true)
	app.overlay.time_cycle_button.pressed.emit()
	_check("menu blocks time cycling", app._game_speed == 1.0 and not app._time_paused)
	app.set_game_paused(false)
	for page: String in ["recipes", "npcs"]:
		app.journal.buttons[page].pressed.emit()
		await create_timer(0.2).timeout
		_check(page + " opens", app.journal.current_page == page)
		app.journal.close()
	root.size = Vector2i(960, 640)
	await create_timer(0.5).timeout
	_check("small single time button inside paper", app.overlay.day_progress.get_global_rect().encloses(app.overlay.time_cycle_button.get_global_rect()))
	_check_column_centered("small column vertically centered")
	await _shot("03-hud-small.png")
	var previous_scale := UiScale.preference
	UiScale.configure("120")
	await create_timer(0.3).timeout
	_check_column_centered("120 percent column vertically centered")
	_check("120 percent column stays on screen", app.overlay.day_progress.get_global_rect().position.y >= 0 and app.overlay.day_root.get_global_rect().end.y <= root.get_visible_rect().size.y)
	UiScale.configure(previous_scale)
	print("HUD_REFERENCE_RUNTIME failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func _check_column_centered(label: String) -> void:
	var top: float = app.overlay.day_progress.get_global_rect().position.y
	var bottom: float = app.overlay.day_root.get_global_rect().end.y
	_check(label, absf((top + bottom) * 0.5 - root.get_visible_rect().size.y * 0.5) < 1.5)

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check("capture " + filename, root.get_texture().get_image().save_png(OUTPUT + filename) == OK)
