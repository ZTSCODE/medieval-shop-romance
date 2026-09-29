extends RefCounted

static func bind(button: Button) -> void:
	if button.has_meta("paper_motion_bound"):
		return
	button.set_meta("paper_motion_bound",true)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/ui/button_press.gdshader")
	button.material = material
	var feedback := UiPressFeedback.new()
	feedback.name = "PaperPressFeedback"
	feedback.changed.connect(func(amount: float) -> void:
		material.set_shader_parameter("press_amount",amount)
		material.set_shader_parameter("press_center",button.size*0.5)
		for child: Node in button.get_children():
			if child is Control and child.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				child.pivot_offset = button.size*0.5-child.position
				child.scale = Vector2.ONE*amount
	)
	button.add_child(feedback)
