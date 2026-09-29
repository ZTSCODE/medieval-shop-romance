extends SceneTree

var failures := 0
var chosen := -1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	root.gui_embed_subwindows = true
	var option := OptionButton.new()
	option.position = Vector2(240, 180)
	option.size = Vector2(280, 48)
	for index in range(14):
		option.add_item("Resolution %d" % index)
	option.item_selected.connect(func(index: int): chosen = index)
	root.add_child(option)
	await process_frame
	root.grab_focus()
	await create_timer(0.2).timeout
	var cursor = root.get_node("GameCursor")
	await _move(Vector2(300, 204))
	await _click(Vector2(300, 204))
	var popup := option.get_popup()
	_check(popup.visible, "real pointer click opens dropdown")
	_check(cursor._native_window_cursor and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE and not cursor._cursor_sprite.visible, "one native painted pointer above popup")
	var popup_point := Vector2(popup.position) + Vector2(45, popup.size.y * 0.4)
	await _move(popup_point)
	_check(cursor._native_window_cursor and not cursor._cursor_sprite.visible, "hover keeps native pointer and no duplicate sprite")
	await _click(popup_point)
	_check(chosen >= 0 and not popup.visible, "popup click selects item without lost input")
	await _move(Vector2(600, 500))
	_check(not cursor._native_window_cursor and cursor._cursor_sprite.visible and Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN, "close restores software painted pointer")
	var edit := LineEdit.new()
	edit.position = Vector2(100, 100)
	edit.size = Vector2(200, 48)
	root.add_child(edit)
	await _move(Vector2(150, 125))
	_check(DisplayServer.cursor_get_shape() == Input.CURSOR_IBEAM and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE and not cursor._cursor_sprite.visible, "text entry keeps native I-beam")
	print("CURSOR_POPUP_SUITE failures=%d selected=%d" % [failures, chosen])
	quit(0 if failures == 0 else 1)


func _move(point: Vector2) -> void:
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await process_frame
	await process_frame


func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await process_frame


func _check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1
