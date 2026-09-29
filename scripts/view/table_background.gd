class_name TableBackground
extends TextureRect

const ART_PATH := "res://assets/art/ui/ebb_crayon/table_grain.png"
const BACKGROUND_SHADER := """
shader_type canvas_item;
void fragment() {
	vec4 sample_color = texture(TEXTURE, UV);
	vec3 muted = mix(vec3(0.13, 0.18, 0.29), sample_color.rgb, 0.38);
	COLOR = vec4(muted, sample_color.a);
}
"""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shader := Shader.new()
	shader.code = BACKGROUND_SHADER
	var shading := ShaderMaterial.new()
	shading.shader = shader
	material = shading


func _ready() -> void:
	texture = GameArt.texture(ART_PATH)
	get_viewport().size_changed.connect(_sync_viewport)
	_sync_viewport()


func _sync_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
