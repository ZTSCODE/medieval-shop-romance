extends SceneTree

var failures := 0
var checks := 0
const OUT := "res://work/menu-button-fix-20260922/"

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, result: bool) -> void:
	checks += 1
	if not result:
		failures += 1
	print(("PASS " if result else "FAIL ") + label)

func _settle() -> void:
	await create_timer(0.45).timeout

func _shot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + path)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	TranslationServer.set_locale("zh_CN")
	var overlay := SessionOverlay.new()
	root.add_child(overlay)
	overlay.set_hud_visible(false)
	for dimensions: Vector2i in [Vector2i(3840, 2160), Vector2i(1280, 720), Vector2i(3840, 2160)]:
		root.size = dimensions
		overlay.set_paused(true)
		await _settle()
		for iteration in 3:
			overlay.set_paused(false)
			await process_frame
			overlay.set_paused(true)
			await _settle()
			var panel_rect: Rect2 = overlay._window.get_global_rect()
			var all_inside := true
			var all_centered := true
			for button: Button in overlay._pause_entries.get_children():
				all_inside = all_inside and panel_rect.encloses(button.get_global_rect())
				all_centered = all_centered and absf(button.get_global_rect().get_center().x - panel_rect.get_center().x) < 2.0
			_check("pause buttons contained and centered %s reopen %d" % [dimensions, iteration], all_inside and all_centered)
		await _shot("pause-%dx%d.png" % [dimensions.x, dimensions.y])
		overlay.open_page("settings")
		await _settle()
		overlay.back()
		await _settle()
		_check("settings return keeps first button contained %s" % dimensions, overlay._window.get_global_rect().encloses(overlay.resume_button.get_global_rect()))
		var button: Button = overlay.resume_button
		button.grab_focus()
		await _settle()
		var motion := InputEventMouseMotion.new()
		motion.position = button.get_global_rect().get_center()
		root.push_input(motion, true)
		await _settle()
		var press := InputEventMouseButton.new()
		press.position = motion.position
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		root.push_input(press, true)
		await _settle()
		_check("press keeps selected color and shrinks %s" % dimensions, button._selection > 0.999 and is_equal_approx(button.press_feedback.amount,0.97) and button._visual.scale.distance_to(Vector2.ONE*0.97)<0.001 and button.scale==Vector2.ONE)
		press.pressed = false
		root.push_input(press, true)
		await _settle()
		_check("release restores scale %s" % dimensions, button.scale == Vector2.ONE and button._visual.scale.distance_to(Vector2.ONE) < 0.001)
		var down := InputEventKey.new()
		down.keycode = KEY_DOWN
		down.pressed = true
		root.push_input(down, true)
		down.pressed = false
		root.push_input(down, true)
		await _settle()
		_check("keyboard takes sole selection from pointer %s" % dimensions, overlay.new_journey_button.has_focus() and overlay.new_journey_button._selection > 0.999 and button._selection < 0.001)
	overlay.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await _check_shape()
	print("Menu button regression checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check_shape() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(700, 170)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var button := preload("res://scripts/ui/forest_menu_button.gd").new()
	viewport.add_child(button)
	button.size = Vector2(660, 132)
	button.position = Vector2(20, 19)
	button._leaf.hide()
	button._set_selection(0)
	await _settle()
	await RenderingServer.frame_post_draw
	var normal := viewport.get_texture().get_image()
	normal.save_png(OUT + "paper-normal.png")
	button._set_selection(1)
	await _settle()
	await RenderingServer.frame_post_draw
	var selected := viewport.get_texture().get_image()
	selected.save_png(OUT + "paper-selected.png")
	var alpha_changes := 0
	var rgb_changes := 0
	for y in normal.get_height():
		for x in normal.get_width():
			var a := normal.get_pixel(x, y)
			var b := selected.get_pixel(x, y)
			if absf(a.a - b.a) > 0.001:
				alpha_changes += 1
			if a.a > 0.5 and absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.1:
				rgb_changes += 1
	_check("actual render preserves every paper alpha pixel", alpha_changes == 0)
	_check("actual render recolors original paper", rgb_changes > 1000)
	viewport.queue_free()
