extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

const OUTPUT := "res://outputs/ui-linear-color-20261002/"
var app: Node
var before := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--flow-qa" not in OS.get_cmdline_user_args():
		quit(2)
		return
	before = "--before" in OS.get_cmdline_user_args()
	if before:
		for filename in ["main_menu_paper.gdshader", "forest_menu_recolor.gdshader"]:
			var shader := load("res://scripts/ui/" + filename) as Shader
			shader.code = FileAccess.get_file_as_string(OUTPUT + "backup/" + filename)
	root.size = Vector2i(1672, 941)
	app = PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	await create_timer(2.0).timeout
	app.main_menu.buttons["continue"].disabled = false
	app.main_menu.buttons["continue"].grab_focus()
	await create_timer(0.5).timeout
	for enabled in [false, true]:
		DisplayServer.window_request_hdr_output(enabled)
		await create_timer(0.4).timeout
		await _shot("main-" + ("hdr" if enabled else "sdr"))
	app._commit_new_journey("Preview")
	await create_timer(2.0).timeout
	app.set_game_paused(true)
	app.overlay.resume_button.grab_focus()
	await create_timer(0.5).timeout
	await _shot("pause")
	app.set_game_paused(false)
	for page in ["recipes", "npcs"]:
		app.journal.toggle(page)
		await create_timer(0.8).timeout
		await _shot(page)
		app.journal.close()
		await create_timer(0.4).timeout
	print("UI_LINEAR_COLOR_CAPTURE complete")
	quit()

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var display := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var color := img.get_pixel(x, y)
			if img.get_format() not in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]:
				color = color.linear_to_srgb()
			display.set_pixel(x, y, color)
	var folder := OUTPUT + ("before/" if before else "after/")
	DirAccess.make_dir_recursive_absolute(folder)
	display.save_png(folder + label + ".png")
	if label.begins_with("main"):
		var rect: Rect2 = app.main_menu.buttons["continue"]._paper.get_global_rect()
		var file := FileAccess.open(folder + label + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"button_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "hdr": DisplayServer.window_is_hdr_output_enabled()}, "\t"))
	print("CAPTURE ", folder + label)
