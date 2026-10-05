extends Button

var entry_kind := "recipes"
var _hover_fill := 0.0
var _paper: Panel
var press_feedback: UiPressFeedback
var _keyboard_focus := false
var _suppress_mouse_hover := false
const Paper = preload("res://scripts/ui/settings_control_paper.gd")


func _process(delta: float) -> void:
	var highlighted := (is_hovered() and not _suppress_mouse_hover) or (has_focus() and _keyboard_focus)
	var target := 1.0 if not disabled and (highlighted or button_pressed) else 0.0
	var next := move_toward(_hover_fill, target, delta / 0.14)
	if not is_equal_approx(next, _hover_fill):
		_hover_fill = next
		if is_instance_valid(_paper):
			var style := _paper.get_theme_stylebox("panel")
			style.tint = Paper.BASE_TINT.lerp(Paper.TAB_ACTIVE, smoothstep(0.0, 1.0, _hover_fill))
			_paper.queue_redraw()
		queue_redraw()


func _ready() -> void:
	_paper = Panel.new()
	_paper.name = "JournalButtonPaper"
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.show_behind_parent = true
	_paper.add_theme_stylebox_override("panel", Paper.make())
	add_child(_paper)
	_paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	press_feedback = UiPressFeedback.new()
	press_feedback.changed.connect(_update_press_visual)
	add_child(press_feedback)
	pressed.connect(func() -> void: _suppress_mouse_hover = true)
	mouse_exited.connect(func() -> void: _suppress_mouse_hover = false)
	resized.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	toggled.connect(func(_value: bool) -> void: queue_redraw())


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_keyboard_focus = false
	elif event is InputEventKey and event.pressed:
		_keyboard_focus = true


func _update_press_visual(amount: float) -> void:
	_paper.pivot_offset = _paper.size * 0.5
	_paper.scale = Vector2.ONE * amount
	queue_redraw()


var _icon: Texture2D
var _icon_region := Rect2()

func _draw() -> void:
	var amount := press_feedback.amount if is_instance_valid(press_feedback) else 1.0
	draw_set_transform(size*(1.0-amount)*0.5,0.0,Vector2.ONE*amount)
	var path := "res://assets/art/ui/forest_rebuild/recipe-solid.png" if entry_kind == "recipes" else "res://assets/art/ui/forest_rebuild/relationship-solid.png"
	var icon := GameArt.texture(path)
	var source := Rect2(272,348,742,642) if entry_kind == "recipes" else Rect2(286,404,684,538)
	ImagePlacement.draw(get_canvas_item(),icon,Rect2((size-Vector2(48,40))*0.5,Vector2(48,40)),&"contain",Color("efe4c8"),source)
