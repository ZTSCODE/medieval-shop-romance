extends SceneTree

const SettingsSkin = preload("res://scripts/ui/settings_book_skin.gd")
const OUTPUT := "res://outputs/settings-book-20260929/long-popup.png"
var failures := 0
var chosen := -1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1672, 941)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var background := ColorRect.new()
	background.size = Vector2(root.size)
	background.color = Color("182027")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	var option := OptionButton.new()
	option.position = Vector2(610, 100)
	option.size = Vector2(450, 60)
	for index in range(40):
		option.add_item("Display resolution %02d" % index)
	SettingsSkin.apply_option(option)
	option.item_selected.connect(func(index: int): chosen = index)
	root.add_child(option)
	var popup := option.get_popup()
	await process_frame
	root.grab_focus()
	await create_timer(0.2).timeout
	var cursor = root.get_node("GameCursor")
	await _move(option.position + option.size * 0.5)
	await _click(option.position + option.size * 0.5)
	var button_motion: Node
	for child in option.get_children():
		if child.get_script() == preload("res://scripts/ui/settings_control_motion.gd"):
			button_motion = child
	_check(button_motion != null and button_motion._paper.press_amount < 1.0, "first popup opening plays option press feedback")
	var scroll_feedback = popup.get_node("SettingsPopupMotion")
	var scroll_bar: ScrollBar
	for bar: ScrollBar in scroll_feedback._scrollbars:
		if bar is VScrollBar:
			scroll_bar = bar
	_check(is_zero_approx(scroll_bar.self_modulate.a), "scrollbar hidden during expansion")
	var final_paper_size: Vector2 = popup.get_theme_stylebox("panel").popup_full_size
	_check(popup.visible and final_paper_size.y >= 500 and final_paper_size.y <= 660 and popup.size.y <= final_paper_size.y, "40-item themed popup respects height limit")
	var center := Vector2(popup.position) + Vector2(popup.size) * 0.5
	await _move(center)
	_check(cursor._native_window_cursor and not cursor._cursor_sprite.visible and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "popup hover uses one native painted pointer")
	await create_timer(0.25).timeout
	_check(is_zero_approx(scroll_bar.self_modulate.a), "overflow scrollbar stays hidden until scrolling")
	await _click(center, MOUSE_BUTTON_WHEEL_DOWN)
	await create_timer(0.1).timeout
	_check(scroll_bar.self_modulate.a > 0.9, "user wheel reveals overflow scrollbar")
	await create_timer(0.9).timeout
	_check(is_zero_approx(scroll_bar.self_modulate.a), "idle scrollbar fades out")
	for index in range(50):
		await _click(center, MOUSE_BUTTON_WHEEL_DOWN)
	var last_point := Vector2(popup.position) + Vector2(120, popup.size.y - 34)
	await _move(last_point)
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	_check(shot.save_png(OUTPUT) == OK, "long popup evidence saved")
	var sample := popup.position + Vector2i(popup.size.x - 50, popup.size.y - 54)
	var bottom := shot.get_pixelv(sample)
	print("LONG_POPUP_GEOMETRY " + JSON.stringify({"position": popup.position, "size": popup.size, "bottom_sample": bottom, "focused_item": popup.get_focused_item()}))
	_check(maxf(bottom.r, maxf(bottom.g, bottom.b)) > 0.18, "lower popup paper remains visible above black")
	await _click(last_point)
	_check(chosen == 39 and not popup.visible, "scroll to end then pointer selects final item")
	await _move(Vector2(1100, 850))
	_check(not cursor._native_window_cursor and cursor._cursor_sprite.visible and Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN, "close restores single software pointer")
	await _move(option.position + option.size * 0.5)
	await _click(option.position + option.size * 0.5)
	final_paper_size = popup.get_theme_stylebox("panel").popup_full_size
	_check(popup.visible and final_paper_size.y >= 500 and final_paper_size.y <= 660 and popup.size.y <= final_paper_size.y, "reopening long popup recomputes valid content size")
	popup.hide()
	option.clear()
	for index in range(3):
		option.add_item("Window mode %d" % index)
	await _click(option.position + option.size * 0.5)
	_check(popup.visible and popup.size.y > 70 and popup.size.y < 220, "three-item popup keeps compact natural height")
	var motion := popup.get_node("SettingsPopupMotion")
	_check(motion._expansion > 0.0 and motion._expansion < 1.0 and motion._target_size != Vector2i.ZERO, "popup contents are mid-expansion after opening")
	await RenderingServer.frame_post_draw
	var early := root.get_texture().get_image()
	early.save_png("res://outputs/settings-book-20260929/popup-expand-early.png")
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var settled := root.get_texture().get_image()
	settled.save_png("res://outputs/settings-book-20260929/popup-expand-settled.png")
	_check(is_equal_approx(motion._expansion, 1.0), "popup expansion settles at full size")
	_check(is_zero_approx(scroll_bar.self_modulate.a), "compact popup never reveals scrollbar after expansion")
	var difference := 0.0
	var bounds := Rect2i(popup.position, popup.size).intersection(Rect2i(Vector2i.ZERO, settled.get_size()))
	for y in range(bounds.position.y, bounds.end.y, 3):
		for x in range(bounds.position.x, bounds.end.x, 3):
			var before := early.get_pixel(x, y)
			var after := settled.get_pixel(x, y)
			difference += absf(before.r - after.r) + absf(before.g - after.g) + absf(before.b - after.b)
	_check(difference > 2.0, "rendered popup visibly changes during full-content expansion")
	var empty_icon = popup.get_theme_icon("radio_unchecked")
	_check(empty_icon.source.get_image().get_used_rect().size == Vector2i.ZERO, "unselected items have no visible empty boxes")
	var checked_icon = popup.get_theme_icon("radio_checked")
	_check(checked_icon.source.get_image().get_used_rect().size != Vector2i.ZERO, "selected item retains visible check mark")
	await _move(Vector2(popup.position) + Vector2(130, 78))
	popup.set_focused_item(1)
	await process_frame
	_check(popup.get_theme_stylebox("hover").get_border_width(SIDE_LEFT) == 0 and popup.get_theme_color("font_hover_color").r < 0.2, "focused row has no default border and dark contrast text")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/settings-book-20260929/popup-hover.png")
	popup.hide()
	_check(is_instance_valid(motion._closing_layer), "closing creates non-interactive full-content contraction")
	print("POPUP_CLOSE_CAPTURE_US=%d" % motion._last_close_capture_usec)
	await create_timer(0.06).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/settings-book-20260929/popup-close-middle.png")
	await create_timer(0.12).timeout
	_check(not is_instance_valid(motion._closing_layer), "closing animation removes temporary visual layer")
	await _move(option.position + option.size * 0.5)
	await _click(option.position + option.size * 0.5)
	motion._tween.pause()
	motion._set_expansion(0.70)
	await process_frame
	chosen = -1
	await _click(Vector2(popup.position) + Vector2(120, 18 + 42 + 21))
	_check(chosen == 1, "revealed menu item keeps original pointer hit coordinates during expansion")
	await create_timer(0.2).timeout
	print("CURSOR_LONG_POPUP_SUITE failures=%d selected=%d" % [failures, chosen])
	quit(0 if failures == 0 else 1)


func _move(point: Vector2) -> void:
	Input.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = Vector2(24, 24)
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await process_frame


func _check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1


