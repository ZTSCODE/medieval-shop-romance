extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures += 1


func _run() -> void:
	var cursor = root.get_node("GameCursor")
	_check("autoload present", cursor != null)
	_check("pause independent", cursor.process_mode == Node.PROCESS_MODE_ALWAYS)
	var current_size: int = cursor.cursor_size_for_window(root.size)
	for texture in cursor.current_textures():
		var image: Image = texture.get_image()
		_check("adaptive canvas", image.get_size() == Vector2i(current_size, current_size))
		_check("transparent corner", image.get_pixel(current_size - 1, 0).a == 0.0)
	var textures: Array[Texture2D] = cursor.current_textures()
	_check("normal mapping", cursor.texture_for_shape(Input.CURSOR_ARROW, false) == textures[0])
	_check("hover mapping", cursor.texture_for_shape(Input.CURSOR_POINTING_HAND, false) == textures[1])
	_check("pressed mapping", cursor.texture_for_shape(Input.CURSOR_ARROW, true) == textures[2])
	_check("shape alone cannot fake drag", cursor.texture_for_shape(Input.CURSOR_DRAG, true) == textures[2])
	_check("explicit drag grip mapping", cursor.texture_for_shape(Input.CURSOR_ARROW, true, true) == textures[3])
	_check("idle can drop stays hover", cursor.texture_for_shape(Input.CURSOR_CAN_DROP, false) == textures[1])
	_check("640p scales down", cursor.cursor_size_for_window(Vector2i(960, 640)) == 102)
	_check("800p uses approved size", cursor.cursor_size_for_window(Vector2i(1280, 800)) == 128)
	_check("1080p scales up", cursor.cursor_size_for_window(Vector2i(1920, 1080)) == 173)
	_check("4K respects readability cap", cursor.cursor_size_for_window(Vector2i(3840, 2160)) == 192)
	_check("drag hotspot matches glowing fingertip", cursor.drag_hotspot_for_size(256) == Vector2(24, 24))
	var original_window_size := root.size
	root.size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	_check("live resize applies 800p cursor", cursor.current_textures()[0].get_size() == Vector2(128, 128))
	root.size = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	_check("live resize applies 1080p cursor", cursor.current_textures()[0].get_size() == Vector2(173, 173))
	root.size = original_window_size
	await process_frame
	await process_frame
	_check("forbidden preserved", not Input.CURSOR_FORBIDDEN in cursor.CUSTOM_SHAPES)
	_check("text cursor preserved", not Input.CURSOR_IBEAM in cursor.CUSTOM_SHAPES)
	cursor._apply(true)
	_check("press state", cursor._pressed)
	cursor._apply(false)
	_check("release state", not cursor._pressed)
	var left_press := InputEventMouseButton.new()
	left_press.button_index = MOUSE_BUTTON_LEFT
	left_press.pressed = true
	left_press.position = Vector2(96, 72)
	cursor._input(left_press)
	_check("left press uses pressed state", cursor._pressed and not cursor.is_dragging_visual())
	_check("left particle follows event position", cursor.latest_particle_position() == left_press.position)
	var short_motion := InputEventMouseMotion.new()
	short_motion.position = Vector2(99, 74)
	cursor._sync_pointer_state(true, short_motion.position)
	_check("small motion stays pressed", not cursor.is_dragging_visual())
	var drag_motion := InputEventMouseMotion.new()
	drag_motion.position = Vector2(104, 80)
	cursor._sync_pointer_state(true, drag_motion.position)
	_check("threshold motion uses drag state", cursor.is_dragging_visual())
	var left_release := InputEventMouseButton.new()
	left_release.button_index = MOUSE_BUTTON_LEFT
	left_release.pressed = false
	left_release.position = drag_motion.position
	cursor._sync_pointer_state(false, left_release.position)
	_check("release clears drag state", not cursor._pressed and not cursor.is_dragging_visual())
	for spark in cursor._particle_layer.get_children():
		spark.queue_free()
	await process_frame
	cursor.spawn_click_particles(Vector2(120, 90))
	await process_frame
	_check("click particles spawn", cursor.particle_count() == 1)
	await create_timer(0.36).timeout
	_check("click particles finish", cursor.particle_count() == 0)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = Vector2(140, 100)
	cursor._input(right_click)
	_check("right click particles spawn", cursor.particle_count() == 1)
	_check("right particle follows event position", cursor.latest_particle_position() == right_click.position)
	_check("right press stays pressed without motion", cursor._pressed and not cursor.is_dragging_visual())
	cursor._sync_pointer_state(true, right_click.position + Vector2(9, 0))
	_check("right drag uses drag state", cursor.is_dragging_visual())
	cursor._sync_pointer_state(false, right_click.position)
	await process_frame
	await create_timer(0.36).timeout
	_check("right click particles finish", cursor.particle_count() == 0)
	var middle_press := InputEventMouseButton.new()
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.pressed = true
	middle_press.position = Vector2(180, 120)
	cursor._input(middle_press)
	_check("middle press uses pressed state", cursor._pressed and not cursor.is_dragging_visual())
	cursor._sync_pointer_state(true, middle_press.position + Vector2(0, 9))
	_check("middle drag uses drag state", cursor.is_dragging_visual())
	cursor._sync_pointer_state(false, middle_press.position)
	_check("middle release clears state", not cursor._pressed and not cursor.is_dragging_visual())
	print("GAME_CURSOR_FAILURES=" + str(failures))
	quit(1 if failures else 0)
