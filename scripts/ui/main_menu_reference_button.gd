extends "res://scripts/ui/forest_menu_button.gd"

const SOURCE := Rect2(65, 146, 1926, 472)

func _ready() -> void:
	super._ready()
	var atlas := AtlasTexture.new()
	atlas.atlas = preload("res://assets/art/ui/main_menu_20260929/button-paper-v5.png")
	atlas.region = SOURCE
	_paper.texture = atlas
	_paper.stretch_mode = TextureRect.STRETCH_SCALE
	_paper.material.shader = preload("res://scripts/ui/main_menu_paper.gdshader")
	_paper.material.set_shader_parameter("selected_color", preload("res://scripts/ui/ui_paper_palette.gd").SELECTED_PIGMENT)
	var shadow := TextureRect.new()
	shadow.name = "MainButtonShadow"
	shadow.texture = atlas
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.stretch_mode = TextureRect.STRETCH_SCALE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.show_behind_parent = true
	shadow.self_modulate = Color(0,0,0,0.20)
	_paper.add_child(shadow)
	shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shadow.position.y = 3
