class_name TableCardView
extends Node2D

const CARD_SIZE := TableState.CARD_SIZE
const HALF_SIZE := CARD_SIZE * 0.5
const CORNER_RADIUS := 2.0
const MAX_TILT := deg_to_rad(4.0)
const FACE_RECT := Rect2(-HALF_SIZE, CARD_SIZE)
const ART_RECT := Rect2(-HALF_SIZE + CARD_SIZE * Vector2(0.06, 0.087), CARD_SIZE * Vector2(0.88, 0.877))
const TITLE_FONT_SIZE := int(CARD_SIZE.x * 0.11)
const TITLE_RECT := Rect2(Vector2(-CARD_SIZE.x * 0.35, -HALF_SIZE.y - CARD_SIZE.y * 0.045), Vector2(CARD_SIZE.x * 0.70, CARD_SIZE.y * 0.13))
const PAPER_SOURCE := Rect2(68, 96, 880, 1372)
const COMPONENT_DIR := "res://assets/art/ui/forest_rebuild/"
const FRAME_PATH := CrayonCardStyle.EDGE_PATH
const PAPER_BASE := Color("718885")

var card_id: String = ""
var category_id := &"item"
var content_kind := &""
var target_position := Vector2.ZERO
var dragging: bool = false
var pressed: bool = false
var hovered: bool = false
var selected: bool = false
var drop_target: bool = false
var combination_hint: bool = false
var reduced_motion: bool = false
var drag_velocity := Vector2.ZERO
var drag_order: int = 0
var stack_count: int = 1

var _hover_mix: float = 0.0
var _drag_mix: float = 0.0
var _selected_mix: float = 0.0
var _target_mix: float = 0.0
var _combination_hint_mix: float = 0.0
var _tilt: float = 0.0
var _bounce: float = 0.0
var _bounce_velocity: float = 0.0
var _visual_transform := Transform2D.IDENTITY
var _frame_texture: Texture2D
var _font: Font
var _title: String = ""
var _category: String = ""
var _detail: String = ""
var _accent := Color(0.56, 0.62, 0.57)
var _meter_value: float = 0.0
var _meter_enabled: bool = false
var _art_texture: Texture2D
var _art_region := Rect2(0.0, 0.0, 1.0, 1.0)
var _art_portrait := false
var _art_currency := false
var _art_fit: StringName = &"cover"
var _masked_destination := Rect2()
var _masked_source := Rect2()
var _art_layer: Node2D
var _art_material: ShaderMaterial
var _glyph_layer: Node2D
var _gold_layer: Node2D
var _gold_material: ShaderMaterial
var _gold_clock := 0.0
static var _component_cache: Dictionary = {}


func _init() -> void:
	_font = GameTheme.paper_font()
	_update_visual_transform()


func _ready() -> void:
	_art_layer = Node2D.new()
	_art_layer.name = "ArtSurface"
	_art_material = ShaderMaterial.new()
	_art_material.shader = preload("res://assets/shaders/card_art_edge.gdshader")
	_art_layer.material = _art_material
	add_child(_art_layer)
	_art_layer.draw.connect(_draw_art_layer)
	_prepare_masked_art()
	_gold_layer = Node2D.new()
	_gold_layer.name = "InsetGoldSurface"
	_gold_material = ShaderMaterial.new()
	_gold_material.shader = preload("res://assets/shaders/card_inset_gold.gdshader")
	_gold_material.set_shader_parameter("title_paper",_component("card-title-sage.png"))
	_gold_material.set_shader_parameter("gold_noise",preload("res://assets/art/ui/forest_rebuild/gold-grain-noise.tres"))
	_gold_layer.material = _gold_material
	add_child(_gold_layer)
	_gold_layer.draw.connect(_draw_inset_gold)
	_glyph_layer = Node2D.new()
	_glyph_layer.name = "TypeGlyph"
	add_child(_glyph_layer)
	_glyph_layer.draw.connect(_draw_type_glyph)
	if ResourceLoader.exists(FRAME_PATH):
		_frame_texture = load(FRAME_PATH) as Texture2D
	queue_redraw()


func play_unfold() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	var old_visual := Vector4(_hover_mix, _drag_mix, _selected_mix, _target_mix)
	var old_hint := _combination_hint_mix
	var old_tilt := _tilt
	var old_bounce := _bounce
	var animated_gold := selected or drop_target or combination_hint or _selected_mix > 0.005 or _target_mix > 0.005 or _combination_hint_mix > 0.005
	if not reduced_motion and animated_gold:
		_gold_clock += dt
	var movement_rate := 70.0 if dragging else 35.0
	if reduced_motion and not dragging:
		movement_rate = 50.0
	position = position.lerp(target_position, _decay(movement_rate, dt))
	if position.distance_squared_to(target_position) < 0.0004:
		position = target_position
	_hover_mix = lerpf(_hover_mix, float(hovered), _decay(22.0, dt))
	_drag_mix = lerpf(_drag_mix, float(dragging or pressed), _decay(28.0, dt))
	_selected_mix = lerpf(_selected_mix, float(selected), _decay(22.0, dt))
	_target_mix = lerpf(_target_mix, float(drop_target), _decay(20.0, dt))
	_combination_hint_mix = lerpf(_combination_hint_mix,float(combination_hint),_decay(16.0,dt))
	var target_tilt: float = 0.0
	if dragging and not reduced_motion:
		target_tilt = clampf(drag_velocity.x * 0.000048, -MAX_TILT, MAX_TILT)
	_tilt = lerpf(_tilt, target_tilt, _decay(19.0, dt))
	if reduced_motion:
		_tilt = 0.0
		_bounce = 0.0
		_bounce_velocity = 0.0
	else:
		var spring := _step_spring(_bounce, _bounce_velocity, 36.0, 0.62, dt)
		_bounce = spring.x
		_bounce_velocity = spring.y
		if absf(_bounce) < 0.001 and absf(_bounce_velocity) < 0.01:
			_bounce = 0.0
			_bounce_velocity = 0.0
	_update_visual_transform()
	var new_visual := Vector4(_hover_mix, _drag_mix, _selected_mix, _target_mix)
	if animated_gold or old_visual.distance_squared_to(new_visual) > 0.0000001 or absf(old_hint - _combination_hint_mix) > 0.0003 or absf(old_tilt - _tilt) > 0.0003 or absf(old_bounce - _bounce) > 0.0003:
		queue_redraw()


func snap_to(pos: Vector2) -> void:
	position = pos
	target_position = pos
	_bounce = 0.0
	_bounce_velocity = 0.0
	_tilt = 0.0
	_update_visual_transform()
	queue_redraw()


func land() -> void:
	if reduced_motion:
		return
	_bounce_velocity = 82.0


func set_content(title: String, category: String, detail: String, accent: Color = Color(0.56, 0.62, 0.57)) -> void:
	if _title == title and _category == category and _detail == detail and _accent == accent:
		return
	_title = title
	_category = category
	_detail = detail
	_accent = accent
	queue_redraw()


func set_meter(value: float, enabled: bool) -> void:
	var next_value := clampf(value, 0.0, 1.0)
	if is_equal_approx(_meter_value, next_value) and _meter_enabled == enabled:
		return
	_meter_value = next_value
	_meter_enabled = enabled
	queue_redraw()


func set_art(texture: Texture2D, region: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0), portrait: bool = false, currency: bool = false, fit: StringName = &"cover") -> void:
	var safe_region := region.intersection(Rect2(0.0, 0.0, 1.0, 1.0))
	if not safe_region.has_area():
		safe_region = Rect2(0.0, 0.0, 1.0, 1.0)
	if _art_texture == texture and _art_region == safe_region and _art_portrait == portrait and _art_currency == currency and _art_fit == fit:
		return
	_art_texture = texture
	_art_region = safe_region
	_art_portrait = portrait
	_art_currency = currency
	_art_fit = fit
	_prepare_masked_art()
	if is_instance_valid(_art_layer):
		_art_layer.queue_redraw()
	queue_redraw()


func hit_test(world_point: Vector2) -> bool:
	var point := _visual_transform.affine_inverse() * (transform.affine_inverse() * world_point)
	if not _title.is_empty() and get_title_rect().has_point(point):
		return true
	if not FACE_RECT.has_point(point):
		return false
	var rounded_core := HALF_SIZE - Vector2.ONE * CORNER_RADIUS
	var corner_distance := point.abs() - rounded_core
	var outside_corner := Vector2(maxf(corner_distance.x, 0.0), maxf(corner_distance.y, 0.0))
	return outside_corner.length_squared() <= CORNER_RADIUS * CORNER_RADIUS


func get_visual_rect() -> Rect2:
	var combined := transform * _visual_transform
	var local_rect := FACE_RECT.merge(get_title_rect()) if not _title.is_empty() else FACE_RECT
	var first := combined * local_rect.position
	var result := Rect2(first, Vector2.ZERO)
	result = result.expand(combined * Vector2(local_rect.end.x, local_rect.position.y))
	result = result.expand(combined * local_rect.end)
	result = result.expand(combined * Vector2(local_rect.position.x, local_rect.end.y))
	return result


func _draw() -> void:
	var lift := _current_lift()
	var shadow_transform := _visual_transform
	shadow_transform.origin = HALF_SIZE + Vector2(1.0 + lift * 0.20, 2.0 + lift * 0.25)
	draw_set_transform_matrix(shadow_transform)
	for spread: float in [5.0, 2.5, 0.0]:
		ImagePlacement.draw(get_canvas_item(), _component("card-sage-paper.png"), FACE_RECT.grow(spread * (0.3 + _drag_mix * 0.7)), &"contain", Color(0.025, 0.03, 0.035, 0.055 + _drag_mix * 0.035), PAPER_SOURCE)
	draw_set_transform_matrix(_visual_transform)
	var hint_pulse := 0.78 if reduced_motion else 0.68 + 0.32 * (0.5 + 0.5 * sin(_gold_clock * 5.2))
	var active_rim := maxf(maxf(_selected_mix, _target_mix), _combination_hint_mix * hint_pulse)
	ImagePlacement.draw(get_canvas_item(), _component("card-sage-paper.png"), FACE_RECT, &"contain", _paper_tint(), PAPER_SOURCE)
	if is_instance_valid(_art_layer):
		_art_layer.transform = _visual_transform
	if is_instance_valid(_gold_layer):
		_gold_layer.transform = _visual_transform
		_gold_layer.visible = active_rim > 0.005
		_gold_material.set_shader_parameter("strength",active_rim)
		_gold_material.set_shader_parameter("shimmer_clock",_gold_clock)
		_gold_layer.queue_redraw()
	if is_instance_valid(_glyph_layer):
		_glyph_layer.transform = _visual_transform
		_glyph_layer.queue_redraw()
	_draw_content()
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_inset_gold() -> void:
	ImagePlacement.draw(_gold_layer.get_canvas_item(), _component("card-sage-paper.png"), FACE_RECT, &"contain", Color.WHITE, PAPER_SOURCE)


func _draw_type_glyph() -> void:
	var glyph := GameArt.texture("res://assets/art/ui/forest_rebuild/type-leaf.png")
	if category_id == &"character":
		var people := AtlasTexture.new()
		people.atlas = GameArt.texture("res://assets/art/ui/forest_rebuild/relationship-solid.png")
		people.region = Rect2(286,404,684,538)
		glyph = people
	if glyph != null:
		ImagePlacement.draw(_glyph_layer.get_canvas_item(), glyph, Rect2(FACE_RECT.position + CARD_SIZE * Vector2(0.075, 0.093), CARD_SIZE * Vector2(0.085, 0.072)), &"contain", Color(0.75,0.70,0.57,0.90))


func get_title_rect() -> Rect2:
	return TITLE_RECT


func _draw_content() -> void:
	if _title.is_empty():
		return
	var title_rect := get_title_rect()
	var title_tint := _paper_tint()
	_draw_title_shadow(title_rect)
	ImagePlacement.draw(get_canvas_item(), _component("card-title-sage.png"), title_rect, &"contain", title_tint, Rect2(110, 196, 1810, 380))
	var text_width := title_rect.size.x - 12.0
	var baseline := title_rect.position.y + (title_rect.size.y - _font.get_height(TITLE_FONT_SIZE)) * 0.5 + _font.get_ascent(TITLE_FONT_SIZE)
	draw_string(_font, Vector2(title_rect.position.x + 6.0, baseline), _fit_line(_title, text_width, TITLE_FONT_SIZE), HORIZONTAL_ALIGNMENT_CENTER, text_width, TITLE_FONT_SIZE, Color("f1eadb"))


func _draw_title_shadow(title_rect: Rect2) -> void:
	var placement := ImagePlacement.fit(Rect2(110, 196, 1810, 380), title_rect, &"contain")
	var destination: Rect2 = placement.destination
	# 下缘两小段收尖断笔，避免整片投影把题签本身染暗。
	for stroke: Vector3 in [Vector3(0.09, 0.34, 0.38), Vector3(0.62, 0.19, 0.27)]:
		var at := Vector2(destination.position.x + destination.size.x * stroke.x, destination.end.y - 0.45)
		var length := destination.size.x * stroke.y
		var points := PackedVector2Array([at, at+Vector2(length*0.23,-0.15), at+Vector2(length*0.72,0.1), at+Vector2(length,0.3), at+Vector2(length*0.82,1.4), at+Vector2(length*0.47,2.1), at+Vector2(length*0.15,1.1)])
		var ink := Color(0.065,0.05,0.045,stroke.z)
		var tip := Color(ink,0.02)
		draw_polygon(points,PackedColorArray([tip,ink,ink,tip,ink,ink,tip]))


func _paper_tint() -> Color:
	if category_id == &"character" and content_kind != &"hero":
		return Color(0.94, 0.46, 0.32)
	if category_id == &"location":
		return Color(0.59, 0.79, 0.61)
	return Color(0.67, 0.71, 0.83)


func _draw_art_layer() -> void:
	if _art_texture != null and _masked_destination.has_area() and _masked_source.has_area():
		_art_layer.draw_texture_rect_region(_art_texture, _masked_destination, _masked_source)


func _prepare_masked_art() -> void:
	_masked_destination = Rect2()
	_masked_source = Rect2()
	if _art_texture == null:
		return
	var placement := get_art_placement()
	_masked_destination = placement.destination
	_masked_source = placement.source
	if is_instance_valid(_art_material):
		_art_material.set_shader_parameter("art_origin", _masked_destination.position)
		_art_material.set_shader_parameter("art_size", _masked_destination.size)
		_art_material.set_shader_parameter("source_size", _masked_source.size)


static func _component(filename: String) -> Texture2D:
	if not _component_cache.has(filename):
		var prepared := COMPONENT_DIR + "prepared/" + filename
		_component_cache[filename] = load(prepared if ResourceLoader.exists(prepared) else COMPONENT_DIR + filename) as Texture2D
	return _component_cache[filename] as Texture2D


func get_art_placement() -> Dictionary:
	if _art_texture == null:
		return {"source": Rect2(), "destination": Rect2()}
	var texture_size := _art_texture.get_size()
	var source := Rect2(_art_region.position * texture_size, _art_region.size * texture_size)
	return ImagePlacement.fit(source, ART_RECT, _art_fit, Vector2(0.5, 0.0) if _art_portrait else Vector2(0.5, 0.5))


func _fit_line(value: String, width: float, font_size: int) -> String:
	if _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= width:
		return value
	var shortened := value
	while not shortened.is_empty():
		shortened = shortened.left(shortened.length() - 1)
		if _font.get_string_size(shortened + "…", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= width:
			return shortened + "…"
	return ""


func _update_visual_transform() -> void:
	var scale_amount := 1.0 if reduced_motion else 1.0 + _drag_mix * 0.045
	var visual_scale := Vector2.ONE * (scale_amount + _bounce * 0.002)
	var visual_offset := HALF_SIZE + Vector2(0.0, -_current_lift() + _bounce * 0.4)
	_visual_transform = Transform2D(_tilt, visual_scale, 0.0, visual_offset)


func _current_lift() -> float:
	if reduced_motion:
		return _drag_mix * 2.0
	return _drag_mix * 22.0 + _hover_mix * 3.0 * (1.0 - _drag_mix)


static func _decay(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


static func _step_spring(value: float, velocity: float, frequency: float, damping: float, delta: float) -> Vector2:
	var damped_frequency := frequency * sqrt(1.0 - damping * damping)
	var decay := exp(-damping * frequency * delta)
	var cosine := cos(damped_frequency * delta)
	var sine := sin(damped_frequency * delta)
	var displacement := decay * (value * cosine + (velocity + damping * frequency * value) / damped_frequency * sine)
	var next_velocity := decay * (velocity * cosine - (damping * frequency * velocity + frequency * frequency * value) / damped_frequency * sine)
	return Vector2(displacement, next_velocity)
