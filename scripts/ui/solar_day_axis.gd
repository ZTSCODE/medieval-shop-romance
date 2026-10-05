extends ProgressBar

const INK := Color("e3d6b8")
var _glyphs: Array[TextureRect] = []
var _marker: ColorRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	min_value = 0.0
	max_value = 1.0
	step = 0.0
	show_percentage = false
	add_theme_stylebox_override("background", StyleBoxEmpty.new())
	add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	value_changed.connect(func(_value: float) -> void: _layout_marker(); queue_redraw())
	resized.connect(queue_redraw)
	resized.connect(_layout_glyphs)
	_build_glyphs()
	_marker = ColorRect.new()
	_marker.name = "DayMovingMarker"
	_marker.size = Vector2(16,16)
	_marker.color = Color("e8cc83")
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var marker_material := ShaderMaterial.new()
	marker_material.shader = preload("res://scripts/ui/solar_marker.gdshader")
	_marker.material = marker_material
	add_child(_marker)
	_marker.hide()
	resized.connect(_layout_marker)
	_layout_marker()

func _layout_marker() -> void:
	if is_instance_valid(_marker):
		_marker.position = get_marker_position() - _marker.size * 0.5

func get_marker_position() -> Vector2:
	return Vector2(size.x * 0.5, lerpf(74.0, 213.0, value))

func _draw() -> void:
	preload("res://scripts/ui/hud_reference_paper.gd").draw_paper(get_canvas_item(), Rect2(Vector2.ZERO, size), "time")
	var x := size.x * 0.5
	draw_line(Vector2(x, 74), Vector2(x, 213), Color("aca99a"), 1.3, true)
	for index: int in 2:
		var y := 74.0 if index == 0 else 213.0
		draw_circle(Vector2(x, y), 6.5, Color("333430"))
		draw_circle(Vector2(x, y), 5, Color("70736e") if index == 0 else Color("999b97"))
	var marker := get_marker_position()
	draw_circle(marker, 5, Color("d9c28e"))

func _build_glyphs() -> void:
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform vec4 ink : source_color; void fragment(){ COLOR=vec4(ink.rgb,texture(TEXTURE,UV).a*ink.a); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("ink", INK)
	var paths := ["res://assets/art/ui/ebb_crayon/sun-glyph-v2.png", "res://assets/art/ui/ebb_crayon/moon-glyph-v2.png"]
	var regions := [Rect2(80,76,1093,1094), Rect2(261,223,732,831)]
	for index in 2:
		var atlas := AtlasTexture.new()
		atlas.atlas = load(paths[index]) as Texture2D
		atlas.region = regions[index]
		var glyph := TextureRect.new()
		glyph.texture = atlas
		glyph.material = material
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(glyph)
		_glyphs.append(glyph)
	_layout_glyphs()

func _layout_glyphs() -> void:
	for index in _glyphs.size():
		var dimensions := Vector2(32,32)
		_glyphs[index].size = dimensions
		_glyphs[index].position = Vector2(size.x*0.5-dimensions.x*0.5,29 if index==0 else 226)
