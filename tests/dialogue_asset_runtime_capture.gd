extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

class PreviewFlow extends DialogueFlow:
	var active := true
	func is_active() -> bool:
		return active
	func current_line() -> Dictionary:
		return {"speaker": "narrator", "text_key": "PREVIEW_DIALOGUE_SHORT" if line_index == 0 else "PREVIEW_DIALOGUE_LONG"}
	func presentation_info() -> Dictionary:
		return {"narrator": true, "total": 2, "last_line": line_index == 1, "marker": "preview:%d" % line_index}
	func advance() -> void:
		line_index += 1
		if line_index > 1:
			active = false
		changed.emit()

var app: Node
var failures := 0
const OUTPUT := "res://outputs/dialogue-wide-20261003"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	TranslationServer.set_locale("zh_CN")
	var translations := Translation.new()
	translations.locale = "zh_CN"
	var rows := FileAccess.open("res://tests/fixtures/dialogue_asset_preview.csv", FileAccess.READ)
	rows.get_csv_line()
	while not rows.eof_reached():
		var row := rows.get_csv_line()
		if row.size() == 2:
			translations.add_message(row[0], row[1])
	TranslationServer.add_translation(translations)
	root.size = Vector2i(1600, 900)
	app = PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	await create_timer(0.6).timeout
	app._commit_new_journey("UI Preview")
	await create_timer(1.8).timeout
	var flow := PreviewFlow.new()
	app._replace_dialogue(flow)
	app._apply_pause_state()
	await create_timer(0.6).timeout
	var ui: DialogueOverlay = app.dialogue_overlay
	ui._characters = 100000.0
	ui.story_label.visible_characters = -1
	await process_frame
	_check("native texture bound", ui.text_panel.get_theme_stylebox("panel").get_script().resource_path.ends_with("reference_dialogue_paper.gd"))
	_check("isolated save profile", app.qa_mode and app.save_store.directory.contains("qa-profile"))
	_check("single nameplate and botanical decoration", not ui._speaker_tab.visible and not ui._leaf.visible)
	_check("dialogue at least twice previous width", ui.text_panel.size.x / UiScale.reference_size(ui._root).x >= 1340.0 / 1672.0 - 0.001)
	_check("compact panel keeps text space", ui._content.size.y >= 24)
	await _shot("01-dialogue-in-game-1600x900.png")
	if "--preview-hold" in OS.get_cmdline_user_args():
		print("Dialogue preview ready for interactive inspection")
		return
	ui.continue_button.pressed.emit()
	await process_frame
	_check("continue advances dialogue", flow.line_index == 1)
	ui._characters = 100000.0
	ui.story_label.visible_characters = -1
	root.size = Vector2i(960, 640)
	await create_timer(0.6).timeout
	_check("small screen content inside panel", ui.text_panel.get_rect().encloses(ui._content.get_rect()))
	_check("long text scrolls when needed", ui.story_label.get_minimum_size().y <= ui._content.size.y or ui._content.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO)
	await _shot("02-long-dialogue-960x640.png")
	ui.set_menu_paused(true)
	ui.advance()
	_check("pause blocks advance", flow.line_index == 1)
	ui.set_menu_paused(false)
	ui.advance()
	await create_timer(0.4).timeout
	_check("dialogue closes", not ui.is_presenting())
	print("DIALOGUE_ASSET_RUNTIME failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func _shot(filename: String) -> void:
	app.opening_overlay.hide_all()
	app.opening_overlay.hide()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.get_format() not in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]:
		var display := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGB8)
		for y in image.get_height():
			for x in image.get_width():
				display.set_pixel(x, y, image.get_pixel(x, y).linear_to_srgb())
		image = display
	_check("capture " + filename, image.save_png(OUTPUT.path_join(filename)) == OK)
