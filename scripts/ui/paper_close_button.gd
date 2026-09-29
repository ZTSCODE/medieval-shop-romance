extends Button

var press_feedback: UiPressFeedback


func _init() -> void:
	# 只缩放绘制内容，命中区域和容器位置保持不动。
	set_meta("paper_motion_bound", true)


func _ready() -> void:
	press_feedback = UiPressFeedback.new()
	press_feedback.changed.connect(func(_amount: float) -> void: queue_redraw())
	add_child(press_feedback)


func _draw() -> void:
	var amount := press_feedback.amount if is_instance_valid(press_feedback) else 1.0
	draw_set_transform(size * (1.0 - amount) * 0.5, 0.0, Vector2.ONE * amount)
