extends RefCounted

const INK := Color("eee4c9")
const MUTED := Color("b5aaa0")
const DARK_INK := Color("423a38")
const ERROR := Color("d58f7c")
const TILE := "res://assets/art/ui/dialogue_20260922/plum-brush-tile.png"
const EDGE := "res://assets/art/ui/unified_paper_20260922/brush-edge.png"
const TILE_SIZE := 460.0
const EDGE_WIDTH := 10.0
const PANEL_TINT := Color.WHITE
const SLIP_TINT := Color.WHITE
const FIELD_TINT := Color(0.83,0.83,0.83)
const SELECTED_TINT := Color(1.486,1.627,1.461)
const ACCENT_TINT := Color(1.30,0.92,0.79)
const BUTTON_PIGMENT := Vector3(0.274,0.236,0.228)
const SELECTED_PIGMENT := Vector3(0.407,0.384,0.333)
static var journal_scale := 1.0

static func tint_for(role: StringName) -> Color:
	match role:
		&"heading", &"slip", &"card": return SLIP_TINT
		&"field", &"encounter": return FIELD_TINT
		&"selected", &"hover": return SELECTED_TINT
		&"accent": return ACCENT_TINT
	return PANEL_TINT

static func button_material() -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = preload("res://scripts/ui/forest_menu_recolor.gdshader")
	result.set_shader_parameter("paper_color",BUTTON_PIGMENT)
	result.set_shader_parameter("selected_color",SELECTED_PIGMENT)
	return result
