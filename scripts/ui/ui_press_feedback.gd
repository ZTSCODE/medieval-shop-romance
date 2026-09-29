class_name UiPressFeedback
extends Node

signal changed(amount: float)

var amount := 1.0
var _held := false
var _motion: Tween
var _control: Control
var _pressed_at_msec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_control = get_parent() as Control
	_control.visibility_changed.connect(_visibility_changed)
	if _control is BaseButton:
		_control.button_down.connect(set_pressed.bind(true))
		_control.button_up.connect(set_pressed.bind(false))


func set_pressed(value: bool) -> void:
	if _held == value:
		return
	_held = value
	if value:
		_pressed_at_msec = Time.get_ticks_msec()
	if is_instance_valid(_motion):
		_motion.kill()
	_motion = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_motion.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if value:
		_motion.tween_method(_apply, amount, 0.97, 0.08)
	else:
		# 快速点击也先完成一次轻压，避免同帧松手把动画取消。
		var remaining := maxf(0.0, 0.08 - float(Time.get_ticks_msec() - _pressed_at_msec) / 1000.0)
		if remaining > 0.0:
			_motion.tween_method(_apply, amount, 0.97, remaining)
			_motion.tween_method(_apply, 0.97, 1.0, 0.14)
		else:
			_motion.tween_method(_apply, amount, 1.0, 0.14)


func _apply(value: float) -> void:
	amount = value
	changed.emit(amount)


func reset() -> void:
	_held = false
	if is_instance_valid(_motion):
		_motion.kill()
	_apply(1.0)


func _visibility_changed() -> void:
	if not _control.is_visible_in_tree():
		reset()


func _input(event: InputEvent) -> void:
	if _held and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		set_pressed(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		reset()
