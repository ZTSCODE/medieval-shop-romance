extends SceneTree

var checks := 0
var failures := 0
var pointer := Vector2.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var holder := VBoxContainer.new()
	root.add_child(holder)
	var button := preload("res://scripts/ui/forest_menu_button.gd").new()
	button.text = "Continue journey"
	button.custom_minimum_size = Vector2(400, 86)
	holder.add_child(button)
	var activations := [0]
	button.pressed.connect(func() -> void: activations[0] += 1)
	await _wait(0.1)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(3840, 2160)]:
		root.size = dimensions
		await _wait(0.1)
		# 物理窗口与逻辑画布不同；输入注入和控件位置统一使用逻辑坐标。
		holder.position = root.get_visible_rect().get_center() - Vector2(200, 43)
		await process_frame
		var resting := button.get_global_rect()
		_check("menu is inside logical viewport %s" % dimensions, root.get_visible_rect().encloses(resting))
		_move(resting.position + Vector2(0.5, resting.size.y * 0.5))
		await _wait(0.2)
		_mouse(true)
		await _wait(0.12)
		_check("held menu keeps hit area %s" % dimensions, button.get_global_rect() == resting and button.scale == Vector2.ONE)
		_check("held menu visibly compresses %s" % dimensions, is_equal_approx(button.press_feedback.amount, 0.97) and button._visual.scale.distance_to(Vector2.ONE * 0.97) < 0.001)
		var paper_scale: Vector2 = button._paper.get_global_transform().get_scale()
		_check("paper leaf and caption share compression %s" % dimensions, paper_scale.distance_to(button._leaf.get_global_transform().get_scale()) < 0.001 and paper_scale.distance_to(button._caption.get_global_transform().get_scale()) < 0.001)
		var stable := true
		for frame in 12:
			await process_frame
			stable = stable and button.get_global_rect() == resting and is_equal_approx(button.press_feedback.amount, 0.97)
		_check("holding at edge never jitters %s" % dimensions, stable)
		_mouse(false)
		await _wait(0.2)
		_check("edge click activates once %s" % dimensions, activations[0] == 1)
		_check("release restores visual only %s" % dimensions, button.scale == Vector2.ONE and button._visual.scale == Vector2.ONE)
		_move(resting.get_center())
		_mouse(true)
		_mouse(false)
		await _wait(0.05)
		_check("quick click still compresses %s" % dimensions, button.press_feedback.amount < 0.99 and button.get_global_rect() == resting)
		await _wait(0.23)
		_check("quick click completes rebound %s" % dimensions, is_equal_approx(button.press_feedback.amount, 1.0) and activations[0] == 2)
		activations[0] = 0
	button.text = "Updated caption"
	button.add_theme_font_size_override("font_size", 31)
	await _wait(0.05)
	_check("text remains accessible and visual updates", button.text == "Updated caption" and button._caption.text == button.text and button._caption.get_theme_font_size("font_size") == 31)
	_check("native glyphs stay transparent", button.get_theme_color("font_color").a == 0.0 and button._caption.get_theme_color("font_color").a == 1.0)
	button.disabled = true
	await _wait(0.05)
	_check("disabled text uses muted visual ink", button._caption.get_theme_color("font_color") == button._disabled_ink)
	print("Menu press feedback checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _move(at: Vector2) -> void:
	pointer = at
	var event := InputEventMouseMotion.new()
	event.position = pointer
	root.push_input(event, true)


func _mouse(down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pointer
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event, true)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(label: String, result: bool) -> void:
	checks += 1
	if not result:
		failures += 1
	print(("PASS " if result else "FAIL ") + label)
