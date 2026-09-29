extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var edit := LineEdit.new()
	edit.position = Vector2(100, 100)
	edit.size = Vector2(240, 50)
	root.add_child(edit)
	await process_frame
	await _move(Vector2(150, 125))
	var cursor := root.get_node("GameCursor")
	_check(DisplayServer.cursor_get_shape() == Input.CURSOR_IBEAM and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE and not cursor._cursor_sprite.visible, "text field retains native text cursor")
	await _move(Vector2(500, 400))
	print("CURSOR_TEXT_FIELD_STATE " + JSON.stringify({"shape": DisplayServer.cursor_get_shape(), "mode": Input.get_mouse_mode(), "sprite": cursor._cursor_sprite.visible, "focus": root.has_focus(), "mouse": root.get_mouse_position(), "rect": root.get_visible_rect()}))
	_check(DisplayServer.cursor_get_shape() == Input.CURSOR_ARROW and Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN and cursor._cursor_sprite.visible, "game area restores painted cursor")
	print("CURSOR_TEXT_FIELD_SUITE: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _move(point: Vector2) -> void:
	Input.warp_mouse(point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("FAIL: " + label)
