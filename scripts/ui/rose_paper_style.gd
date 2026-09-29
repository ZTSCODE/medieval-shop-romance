class_name RosePaperStyle
extends StyleBox

const ART_DIR := "res://assets/art/ui/rose_modular/layers_v2/"
const LAYOUT_PATH := ART_DIR + "layout.json"
const INK := Color("513b48")
const CREAM := Color("f5e5de")
const ROSE := Color("dfbcb9")
const MAX_PLANS := 64

var role: StringName = &"panel"
var modulate_color := Color.WHITE
static var _layout: Dictionary = {}
static var _layout_loaded := false
static var _textures: Dictionary = {}
static var _plans: Dictionary = {}
static var _watched: Dictionary = {}
static var _compositor: RosePaperCompositor


static func style_for(paper_role: StringName = &"panel", inset: float = 12.0) -> RosePaperStyle:
	var style := RosePaperStyle.new()
	style.role = paper_role
	style.set_content_margin_all(maxf(inset, 0.0))
	return style


func _draw(canvas_item: RID, rect: Rect2) -> void:
	_draw_cached(canvas_item, rect, role, modulate_color, self, "style:%d" % canvas_item.get_id())


func _get_draw_rect(rect: Rect2) -> Rect2:
	return get_draw_plan(rect).bounds


func get_draw_plan(rect: Rect2) -> Dictionary:
	return plan_for(rect, role)


static func watch_canvas(node: CanvasItem) -> void:
	var id := node.get_canvas_item().get_id()
	_watched[id] = weakref(node)


static func draw_paper(canvas_item: RID, rect: Rect2, paper_role: StringName = &"panel", tint: Color = Color.WHITE) -> void:
	var owner: Object = null
	var reference: WeakRef = _watched.get(canvas_item.get_id())
	if reference != null:
		owner = reference.get_ref()
	_draw_cached(canvas_item, rect, paper_role, tint, owner, String(paper_role) + ":" + str(rect.size))


static func warm_cache(paper_role: StringName, size: Vector2) -> Dictionary:
	return _request_surface(size, paper_role, null, "warm")


static func _draw_cached(canvas_item: RID, rect: Rect2, paper_role: StringName, tint: Color, owner: Object, slot: String) -> void:
	if not _valid_rect(rect) or tint.a <= 0.0:
		return
	var surface := _request_surface(rect.size, paper_role, owner, slot)
	if not bool(surface.get("ready", false)) or not surface.get("texture", RID()).is_valid():
		return
	var bounds: Rect2 = surface.bounds
	RenderingServer.canvas_item_add_texture_rect(canvas_item, Rect2(rect.position + bounds.position, bounds.size), surface.texture, false, tint)


static func _request_surface(size: Vector2, paper_role: StringName, owner: Object, slot: String) -> Dictionary:
	if not _valid_rect(Rect2(Vector2.ZERO, size)):
		return {}
	_ensure_layout()
	var plan := plan_for(Rect2(Vector2.ZERO, size), paper_role)
	if plan.components.is_empty():
		return {}
	for component: Dictionary in plan.components:
		if _texture(component.mask_path) == null:
			return {}
		if component.mode == &"paper" and _texture(component.texture_path) == null:
			return {}
	if _compositor == null:
		_compositor = RosePaperCompositor.new()
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and not tree.root.tree_exiting.is_connected(_release_compositor):
			tree.root.tree_exiting.connect(_release_compositor, CONNECT_ONE_SHOT)
	var ratio := pixel_ratio_for(paper_role)
	return _compositor.request(plan, _textures, ratio, owner, slot)


static func pixel_ratio_for(paper_role: StringName) -> float:
	var factor := 1.0
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		var transform := tree.root.get_final_transform()
		factor = maxf(transform.x.length(), transform.y.length())
	var desired := maxf(4.0, factor * 2.2 * 1.25) if paper_role in [&"card", &"card_label"] else maxf(1.25, factor * 1.25)
	return clampf(ceilf(desired * 4.0) / 4.0, 1.25, 8.0)


static func _release_compositor() -> void:
	if _compositor != null:
		_compositor.clear()
		_compositor = null


static func reload_assets() -> void:
	_release_compositor()
	_layout.clear()
	_layout_loaded = false
	_textures.clear()
	_plans.clear()
	for id: int in _watched.keys():
		if _watched[id].get_ref() == null:
			_watched.erase(id)


static func texture_for(asset_name: StringName) -> Texture2D:
	_ensure_layout()
	var assets: Dictionary = _layout.get("assets", {})
	var entry: Dictionary = assets.get(String(asset_name), {})
	return _texture(_asset_path(String(entry.get("path", String(asset_name) + ".png"))))


static func plan_for(rect: Rect2, paper_role: StringName = &"panel", layout_override: Dictionary = {}) -> Dictionary:
	_ensure_layout()
	var key := String(paper_role) + ":" + str(rect)
	if layout_override.is_empty() and _plans.has(key):
		return _plans[key]
	var layout := _layout if layout_override.is_empty() else layout_override
	var plan := {"role": String(paper_role), "outer_rect": rect, "face_rect": rect, "bounds": rect, "layers": [], "components": [], "patches": [], "backing_rects": [], "backing_bounds": [], "fill_rect": Rect2(), "frame_scale": 0.0, "tile_scale": 0.0}
	if not _valid_rect(rect):
		return plan
	var roles: Dictionary = layout.get("roles", {})
	var config: Dictionary = roles.get(String(paper_role), {})
	var entries: Array = config.get("layers", [])
	var first_component := true
	for index in mini(entries.size(), 4):
		if not entries[index] is Dictionary:
			continue
		var entry: Dictionary = entries[index]
		var shape := _asset_spec(String(entry.get("shape", "")), layout)
		if shape.name.is_empty():
			continue
		var layer_rect := _inset_rect(rect, _insets(entry.get("insets")), _vector(entry.get("offset"), Vector2.ZERO))
		var rotation := float(entry.get("rotation_deg", 0.0))
		rotation = clampf(rotation, -1.0, 1.0) if is_finite(rotation) else 0.0
		var transform := Transform2D(deg_to_rad(rotation), layer_rect.get_center()) * Transform2D(0.0, -layer_rect.get_center())
		var scale := _frame_scale(shape, layer_rect, entry)
		var tile := _asset_spec(String(entry.get("texture", "brush_tile")), layout)
		var tile_width := clampf(float(entry.get("tile_width", tile.logical_width)), 32.0, 1536.0)
		var layer := {"name": String(entry.get("id", "layer_%d" % index)), "rect": layer_rect, "transform": transform, "rotation_deg": rotation, "frame_scale": scale, "tile_width": tile_width, "components": []}
		var shadow_name := String(entry.get("shadow", ""))
		if not shadow_name.is_empty():
			var shadow := _registered_asset(_asset_spec(shadow_name, layout), shape, layer_rect, scale)
			var shadow_offset := _vector(entry.get("shadow_offset"), Vector2(1.0, 1.5))
			var shadow_transform := transform * Transform2D(0.0, shadow_offset)
			var shadow_tint := _color(entry.get("shadow_tint"), Color(0.22, 0.15, 0.17, 0.1))
			var shadow_component := _component(shadow.asset, shadow.rect, shadow.scale, shadow_transform, &"shadow", shadow_tint, entry, tile, tile_width, layer_rect)
			layer.components.append(shadow_component)
		var tint := _color(entry.get("tint"), CREAM)
		tint.a = 1.0
		var paper := _component(shape, layer_rect, scale, transform, &"paper", tint, entry, tile, tile_width, layer_rect)
		layer.components.append(paper)
		var ink_name := String(entry.get("ink", ""))
		if not ink_name.is_empty():
			var ink := _registered_asset(_asset_spec(ink_name, layout), shape, layer_rect, scale)
			var ink_tint := _color(entry.get("ink_tint"), Color("fbf0da"))
			layer.components.append(_component(ink.asset, ink.rect, ink.scale, transform, &"ink", ink_tint, entry, tile, tile_width, layer_rect))
		layer.bounds = _points_bounds(transform * _rect_points(layer_rect))
		for component: Dictionary in layer.components:
			plan.components.append(component)
			plan.patches.append_array(component.patches)
			plan.bounds = component.bounds if first_component else plan.bounds.merge(component.bounds)
			first_component = false
		plan.layers.append(layer)
		if index == entries.size() - 1 or layer.name == "front":
			plan.face_rect = layer_rect
			plan.fill_rect = paper.fill_rect
			plan.frame_scale = scale
			plan.tile_scale = tile_width / tile.region.size.x
		else:
			plan.backing_rects.append(layer_rect)
			plan.backing_bounds.append(layer.bounds)
	if layout_override.is_empty() and not plan.components.is_empty():
		var assets_ready := true
		for component: Dictionary in plan.components:
			assets_ready = assets_ready and _textures.has(component.mask_path) and _textures.has(component.texture_path)
		if assets_ready:
			if _plans.size() >= MAX_PLANS:
				_plans.clear()
			_plans[key] = plan
	return plan


static func _frame_scale(asset: Dictionary, rect: Rect2, entry: Dictionary) -> float:
	var margins: Vector4 = asset.margins
	var maximum := maxf(maxf(margins.x, margins.y), maxf(margins.z, margins.w))
	var scale := float(entry.get("frame_scale", float(entry.get("border_thickness", 10.0)) / maximum))
	if not is_finite(scale) or scale <= 0.0:
		scale = 10.0 / maximum
	return scale * minf(1.0, minf(rect.size.x / ((margins.x + margins.z) * scale), rect.size.y / ((margins.y + margins.w) * scale)))


static func _registered_asset(asset: Dictionary, shape: Dictionary, paper_rect: Rect2, paper_scale: float) -> Dictionary:
	var anchor: Rect2 = asset.registered_region
	if not asset.has_registration:
		anchor = shape.region
	var shape_region: Rect2 = shape.region
	var registration_scale := minf(shape_region.size.x / anchor.size.x, shape_region.size.y / anchor.size.y)
	var scale := paper_scale * registration_scale
	var region: Rect2 = asset.region
	var padding := Vector4(anchor.position.x - region.position.x, anchor.position.y - region.position.y, region.end.x - anchor.end.x, region.end.y - anchor.end.y)
	var margins: Vector4 = shape.margins / registration_scale + padding
	var mapped := asset.duplicate()
	mapped.margins = margins
	var target := Rect2(paper_rect.position - Vector2(padding.x, padding.y) * scale, paper_rect.size + Vector2(padding.x + padding.z, padding.y + padding.w) * scale)
	return {"asset": mapped, "rect": target, "scale": scale}


static func _component(mask: Dictionary, rect: Rect2, scale: float, transform: Transform2D, mode: StringName, tint: Color, entry: Dictionary, texture: Dictionary, tile_width: float, paper_rect: Rect2) -> Dictionary:
	var patches: Array[Dictionary] = []
	var source: Rect2 = mask.region
	var margins: Vector4 = mask.margins
	var border := margins * scale
	var overlap := 0.75 if mode == &"paper" else 0.0
	var fill_rect := Rect2(rect.position + Vector2(border.x - overlap, border.y - overlap), rect.size - Vector2(border.x + border.z - overlap * 2.0, border.y + border.w - overlap * 2.0))
	if mode == &"paper" and fill_rect.has_area():
		patches.append({"kind": &"center", "source": Rect2(), "destination": fill_rect, "quad": transform * _rect_points(fill_rect), "transform": transform})
	var corners: Array[Rect2] = [
		Rect2(source.position, Vector2(margins.x, margins.y)),
		Rect2(Vector2(source.end.x - margins.z, source.position.y), Vector2(margins.z, margins.y)),
		Rect2(Vector2(source.position.x, source.end.y - margins.w), Vector2(margins.x, margins.w)),
		Rect2(source.end - Vector2(margins.z, margins.w), Vector2(margins.z, margins.w)),
	]
	var targets: Array[Rect2] = [
		Rect2(rect.position, Vector2(border.x, border.y)),
		Rect2(Vector2(rect.end.x - border.z, rect.position.y), Vector2(border.z, border.y)),
		Rect2(Vector2(rect.position.x, rect.end.y - border.w), Vector2(border.x, border.w)),
		Rect2(rect.end - Vector2(border.z, border.w), Vector2(border.z, border.w)),
	]
	var edges: Array[Rect2] = [
		Rect2(source.position + Vector2(margins.x, 0.0), Vector2(source.size.x - margins.x - margins.z, margins.y)),
		Rect2(Vector2(source.position.x + margins.x, source.end.y - margins.w), Vector2(source.size.x - margins.x - margins.z, margins.w)),
		Rect2(source.position + Vector2(0.0, margins.y), Vector2(margins.x, source.size.y - margins.y - margins.w)),
		Rect2(Vector2(source.end.x - margins.z, source.position.y + margins.y), Vector2(margins.z, source.size.y - margins.y - margins.w)),
	]
	var edge_targets: Array[Rect2] = [
		Rect2(rect.position + Vector2(border.x, 0.0), Vector2(rect.size.x - border.x - border.z, border.y)),
		Rect2(Vector2(rect.position.x + border.x, rect.end.y - border.w), Vector2(rect.size.x - border.x - border.z, border.w)),
		Rect2(rect.position + Vector2(0.0, border.y), Vector2(border.x, rect.size.y - border.y - border.w)),
		Rect2(Vector2(rect.end.x - border.z, rect.position.y + border.y), Vector2(border.z, rect.size.y - border.y - border.w)),
	]
	for side in 4:
		_append_edge(patches, edges[side], edge_targets[side], scale, side < 2, bool(mask.mirror), transform, side)
	for corner in 4:
		patches.append(_patch(corners[corner], targets[corner], transform, false, false, "corner_%d" % corner))
	return {"mode": mode, "alpha_gain": clampf(float(entry.get("shadow_alpha_gain", mask.alpha_gain)), 0.1, 16.0) if mode == &"shadow" else 1.0, "mask_path": mask.path, "mask_size": mask.texture_size, "texture_path": texture.path, "texture_region": texture.region, "texture_size": texture.texture_size, "texture_logical_size": Vector2(tile_width, tile_width * texture.region.size.y / texture.region.size.x), "texture_strength": clampf(float(entry.get("texture_strength", 0.22)), 0.0, 1.0), "texture_neutral": clampf(float(entry.get("texture_neutral", texture.neutral)), 0.0, 1.0), "texture_phase": _vector(entry.get("texture_phase"), Vector2.ZERO), "paper_origin": paper_rect.position, "rect": rect, "bounds": _points_bounds(transform * _rect_points(rect)), "fill_rect": fill_rect, "transform": transform, "tint": tint, "patches": patches}


static func _append_edge(patches: Array[Dictionary], source: Rect2, target: Rect2, scale: float, horizontal: bool, mirror: bool, transform: Transform2D, side: int) -> void:
	if not source.has_area() or not target.has_area() or scale <= 0.0:
		return
	var source_length := source.size.x if horizontal else source.size.y
	var target_length := target.size.x if horizontal else target.size.y
	var length := source_length * scale
	for index in ceili(target_length / length):
		var remaining := minf(length, target_length - index * length)
		var destination := target
		var sample := source
		var flipped := mirror and index % 2 == 1
		if horizontal:
			destination.position.x += index * length
			destination.size.x = remaining
			sample.size.x = remaining / scale
			if flipped:
				sample.position.x = source.end.x - sample.size.x
		else:
			destination.position.y += index * length
			destination.size.y = remaining
			sample.size.y = remaining / scale
			if flipped:
				sample.position.y = source.end.y - sample.size.y
		patches.append(_patch(sample, destination, transform, flipped and horizontal, flipped and not horizontal, "edge_%d" % side))


static func _patch(source: Rect2, destination: Rect2, transform: Transform2D, flip_h: bool, flip_v: bool, kind: String) -> Dictionary:
	return {"kind": StringName(kind), "source": source, "destination": destination, "quad": transform * _rect_points(destination), "transform": transform, "flip_h": flip_h, "flip_v": flip_v}


static func _asset_spec(name: String, layout: Dictionary) -> Dictionary:
	var assets: Dictionary = layout.get("assets", {})
	var entry: Dictionary = assets.get(name, {})
	var path := _asset_path(String(entry.get("path", name + ".png")))
	var texture := _texture(path)
	var dimensions := texture.get_size() if texture != null else _vector(entry.get("source_size"), Vector2(1024, 1024))
	var region := _rect(entry.get("region"), Rect2(Vector2.ZERO, dimensions))
	region = region.intersection(Rect2(Vector2.ZERO, dimensions))
	if not region.has_area():
		region = Rect2(Vector2.ZERO, dimensions)
	var amount := minf(region.size.x, region.size.y) * 0.2
	var margins := _insets(entry.get("source_margins", [amount, amount, amount, amount]))
	if margins.x <= 0.0 or margins.y <= 0.0 or margins.z <= 0.0 or margins.w <= 0.0 or margins.x + margins.z >= region.size.x or margins.y + margins.w >= region.size.y:
		margins = Vector4(amount, amount, amount, amount)
	return {"name": name, "path": path, "texture_size": dimensions, "region": region, "margins": margins, "registered_region": _rect(entry.get("registered_region"), region), "has_registration": entry.has("registered_region"), "logical_width": float(entry.get("logical_width", 640.0)), "neutral": float(entry.get("neutral", 0.5)), "alpha_gain": float(entry.get("alpha_gain", 1.0)), "mirror": bool(entry.get("mirror_repeat", false))}


static func _texture(path: String) -> Texture2D:
	if not _textures.has(path):
		if not ResourceLoader.exists(path):
			return null
		var loaded := load(path) as Texture2D
		if loaded == null:
			return null
		_textures[path] = loaded
		_plans.clear()
	return _textures[path] as Texture2D


static func _asset_path(path: String) -> String:
	return path if path.begins_with("res://") else ART_DIR + path


static func _ensure_layout() -> void:
	if _layout_loaded or not FileAccess.file_exists(LAYOUT_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if parsed is Dictionary:
		_layout = parsed
	_layout_loaded = true


static func _rect(value: Variant, fallback: Rect2) -> Rect2:
	if value is Array and value.size() == 4:
		var result := Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
		if _valid_rect(result):
			return result
	return fallback


static func _insets(value: Variant) -> Vector4:
	if value is Array and value.size() == 4:
		var result := Vector4(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
		if result.is_finite():
			return Vector4(maxf(result.x, 0.0), maxf(result.y, 0.0), maxf(result.z, 0.0), maxf(result.w, 0.0))
	return Vector4.ZERO


static func _inset_rect(rect: Rect2, insets: Vector4, offset: Vector2) -> Rect2:
	var horizontal := minf(1.0, maxf(rect.size.x - 1.0, 0.0) / maxf(insets.x + insets.z, 0.001))
	var vertical := minf(1.0, maxf(rect.size.y - 1.0, 0.0) / maxf(insets.y + insets.w, 0.001))
	var start := Vector2(insets.x * horizontal, insets.y * vertical)
	var end := Vector2(insets.z * horizontal, insets.w * vertical)
	var dimensions := rect.size - start - end
	return Rect2((rect.position + start + offset).clamp(rect.position, rect.end - dimensions), dimensions)


static func _rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


static func _points_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


static func _vector(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value if value.is_finite() else fallback
	if value is Array and value.size() == 2:
		var result := Vector2(float(value[0]), float(value[1]))
		return result if result.is_finite() else fallback
	return fallback


static func _color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String and Color.html_is_valid(value):
		return Color(value)
	return fallback


static func _valid_rect(rect: Rect2) -> bool:
	return rect.has_area() and rect.position.is_finite() and rect.size.is_finite()
