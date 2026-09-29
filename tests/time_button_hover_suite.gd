extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(960, 640)
	root.content_scale_size = root.size
	var button := preload("res://scripts/ui/time_cycle_button.gd").new()
	button.position = Vector2(200, 200)
	button.size = Vector2(72, 36)
	root.add_child(button)
	await process_frame
	await _move(Vector2(230, 215))
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = Vector2(230, 215)
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await create_timer(0.2).timeout
	_check(button.has_focus() and button._paper.tint.is_equal_approx(button.Paper.TAB_ACTIVE), "mouse click highlights hovered button")
	await _move(Vector2(450, 400))
	_check(button.has_focus() and button._paper.tint.is_equal_approx(button.Paper.HOVER_TINT), "mouse exit clears highlight despite retained focus")
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	Input.parse_input_event(key)
	await create_timer(0.2).timeout
	_check(button._paper.tint.is_equal_approx(button.Paper.TAB_ACTIVE), "keyboard focus remains visible")
	await _move(Vector2(470, 420))
	_check(button._paper.tint.is_equal_approx(button.Paper.HOVER_TINT), "return to mouse clears keyboard highlight")
	print("TIME_BUTTON_HOVER failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	await create_timer(0.2).timeout

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
