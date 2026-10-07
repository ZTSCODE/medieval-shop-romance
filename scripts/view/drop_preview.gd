class_name TableDropPreview
extends Node2D

const PAPER_SOURCE := TableCardView.PAPER_SOURCE
const PAPER_TEXTURE := preload("res://assets/art/ui/forest_rebuild/card-sage-paper.png")
const TITLE_TEXTURE := preload("res://assets/art/ui/forest_rebuild/card-title-sage.png")

var preview_size := TableState.CARD_SIZE:
	set(value):
		preview_size = value
		_refresh()
var blocked := false:
	set(value):
		blocked = value
		_refresh()

var _gold_layer: Node2D
var _gold_material: ShaderMaterial
var _clock := 0.0


func _ready() -> void:
	_gold_layer = Node2D.new()
	_gold_layer.name = "DropPreviewGold"
	_gold_material = ShaderMaterial.new()
	_gold_material.shader = preload("res://assets/shaders/card_inset_gold.gdshader")
	_gold_material.set_shader_parameter("source_origin", TableCardView.PAPER_INTERIOR.position)
	_gold_material.set_shader_parameter("source_size", TableCardView.PAPER_INTERIOR.size)
	_gold_material.set_shader_parameter("face_size", TableCardView.CARD_SIZE)
	_gold_material.set_shader_parameter("corner_radius", TableCardView.CORNER_RADIUS)
	_gold_material.set_shader_parameter("title_paper",TITLE_TEXTURE)
	_gold_material.set_shader_parameter("gold_noise",preload("res://assets/art/ui/forest_rebuild/gold-grain-noise.tres"))
	_gold_layer.material = _gold_material
	add_child(_gold_layer)
	_gold_layer.draw.connect(_draw_gold)
	_refresh()


func _process(delta: float) -> void:
	if not visible or blocked or not is_instance_valid(_gold_material):
		return
	_clock += maxf(delta, 0.0)
	_gold_material.set_shader_parameter("strength",0.90 + 0.10 * (0.5 + 0.5 * sin(_clock * 4.6)))
	_gold_material.set_shader_parameter("shimmer_clock",_clock)
	_gold_material.set_shader_parameter("linear_canvas", get_viewport().use_hdr_2d)
	_gold_material.set_shader_parameter("hdr_headroom", get_window().get_output_max_linear_value() if get_viewport().use_hdr_2d else 1.0)


func _draw() -> void:
	var count := _preview_count()
	for index in count:
		var rect := Rect2(Vector2(0.0, index * TableState.STACK_STEP), TableState.CARD_SIZE)
		var tint := Color(0.60,0.24,0.19,0.48) if blocked else Color(0.55,0.47,0.34,0.52)
		TableCardView._draw_paper_patch(get_canvas_item(), PAPER_TEXTURE, rect, PAPER_SOURCE, tint, 80.0, 12.0)
		if blocked:
			var blocked_color: Color = CrayonCardStyle.palette(Color("c37560")).body
			TableCardView._draw_rounded_card_paper(get_canvas_item(), PAPER_TEXTURE, rect.grow(-2.0), Color(blocked_color, 0.72))


func _draw_gold() -> void:
	if blocked:
		return
	for index in _preview_count():
		var rect := Rect2(Vector2(0.0,index * TableState.STACK_STEP),TableState.CARD_SIZE)
		TableCardView._draw_paper_patch(_gold_layer.get_canvas_item(), PAPER_TEXTURE, rect, PAPER_SOURCE, Color.WHITE, 80.0, 12.0)


func _preview_count() -> int:
	return maxi(int(roundf((preview_size.y - TableState.CARD_SIZE.y) / TableState.STACK_STEP)) + 1,1)


func _refresh() -> void:
	queue_redraw()
	if is_instance_valid(_gold_layer):
		_gold_layer.visible = not blocked
		_gold_layer.queue_redraw()
