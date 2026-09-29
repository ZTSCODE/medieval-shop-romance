extends "res://scripts/ui/forest_menu_button.gd"

const PausePaper = preload("res://scripts/ui/pause_reference_paper.gd")
const SHADOW_OFFSETS := [Vector2(-1, 3), Vector2(1, 3), Vector2(0, 2)]
var _shadow_layers: Array[TextureRect] = []

func _ready() -> void:
	super._ready()
	_paper.texture = PausePaper.atlas("button")
	for offset: Vector2 in SHADOW_OFFSETS:
		var shadow := TextureRect.new()
		shadow.name = "ButtonShadow%d" % _shadow_layers.size()
		shadow.texture = _paper.texture
		shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shadow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.show_behind_parent = true
		shadow.self_modulate = Color(0, 0, 0, 0.10)
		_paper.add_child(shadow)
		shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_shadow_layers.append(shadow)
	resized.connect(_layout_shadows)
	_layout_shadows()

func _layout_shadows() -> void:
	var factor := size.y / 76.0
	for index: int in _shadow_layers.size():
		var offset: Vector2 = SHADOW_OFFSETS[index] * factor
		var shadow := _shadow_layers[index]
		shadow.offset_left = offset.x
		shadow.offset_right = offset.x
		shadow.offset_top = offset.y
		shadow.offset_bottom = offset.y
