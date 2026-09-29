class_name RosePaperCompositor
extends RefCounted

const MASK_SHADER := preload("res://scripts/ui/paper_mask_layer.gdshader")
const MAX_ENTRIES := 32
const MAX_BYTES := 128 * 1024 * 1024
const MAX_DIMENSION := 4096

var entries: Dictionary = {}
var consumers: Dictionary = {}
var allocated_bytes := 0
var created_surfaces := 0
var released_surfaces := 0


func request(plan: Dictionary, textures: Dictionary, pixel_ratio: float, owner: Object = null, slot: String = "") -> Dictionary:
	var geometry := surface_geometry(plan.bounds, pixel_ratio)
	var key := String(plan.role) + ":" + str(plan.outer_rect.size) + ":" + str(geometry.pixel_size)
	_bind(owner, slot, key)
	if entries.has(key):
		entries[key].last_used = Time.get_ticks_msec()
		return entries[key]
	var prepared := prepare_components(plan, textures)
	if prepared.size() != plan.components.size():
		return {}
	var surface := {"key": key, "bounds": geometry.bounds, "pixel_size": geometry.pixel_size, "pixel_ratio": geometry.pixel_ratio, "texture": RID(), "viewport": RID(), "canvas": RID(), "items": [], "prepared": prepared, "ready": false, "headless": DisplayServer.get_name() == "headless", "last_used": Time.get_ticks_msec(), "bytes": 0}
	if not surface.headless:
		var cost: int = geometry.pixel_size.x * geometry.pixel_size.y * 4
		_collect(cost)
		if allocated_bytes + cost > MAX_BYTES or entries.size() >= MAX_ENTRIES:
			return {}
		_build_surface(surface)
		allocated_bytes += cost
		surface.bytes = cost
		created_surfaces += 1
	else:
		_collect(0)
		if entries.size() >= MAX_ENTRIES:
			return {}
	entries[key] = surface
	if not surface.headless and not RenderingServer.frame_post_draw.is_connected(_on_frame_rendered):
		RenderingServer.frame_post_draw.connect(_on_frame_rendered, CONNECT_ONE_SHOT)
	return surface


static func surface_geometry(bounds: Rect2, requested_ratio: float) -> Dictionary:
	var ratio := clampf(requested_ratio, 1.0, 8.0)
	ratio = minf(ratio, float(MAX_DIMENSION - 4) / maxf(bounds.size.x, bounds.size.y))
	var first := (bounds.position * ratio).floor() - Vector2.ONE
	var last := (bounds.end * ratio).ceil() + Vector2.ONE
	var pixels := Vector2i(last - first)
	return {"bounds": Rect2(first / ratio, Vector2(pixels) / ratio), "pixel_size": pixels, "pixel_ratio": ratio}


static func prepare_components(plan: Dictionary, textures: Dictionary) -> Array[Dictionary]:
	var prepared: Array[Dictionary] = []
	for component: Dictionary in plan.components:
		var mask: Texture2D = textures.get(component.mask_path)
		var brush: Texture2D = textures.get(component.texture_path)
		if mask == null or (component.mode == &"paper" and brush == null):
			return []
		var material := ShaderMaterial.new()
		material.shader = MASK_SHADER
		material.set_shader_parameter("layer_mode", 0 if component.mode == &"paper" else 1 if component.mode == &"shadow" else 2)
		material.set_shader_parameter("paper_tint", component.tint)
		material.set_shader_parameter("paper_origin", component.paper_origin)
		material.set_shader_parameter("texture_logical_size", component.texture_logical_size)
		material.set_shader_parameter("texture_phase", component.texture_phase)
		material.set_shader_parameter("texture_strength", component.texture_strength)
		material.set_shader_parameter("texture_neutral", component.texture_neutral)
		material.set_shader_parameter("mask_alpha_gain", component.alpha_gain)
		if brush != null:
			material.set_shader_parameter("brush_texture", brush)
			var region: Rect2 = component.texture_region
			var dimensions: Vector2 = component.texture_size
			material.set_shader_parameter("brush_region", Vector4(region.position.x / dimensions.x, region.position.y / dimensions.y, region.size.x / dimensions.x, region.size.y / dimensions.y))
		var mesh := mesh_for(component)
		prepared.append({"mode": component.mode, "material": material, "mask": mask, "transform": component.transform, "mesh": mesh})
	return prepared


static func mesh_for(component: Dictionary) -> Dictionary:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var fills: Array[Rect2] = []
	for patch: Dictionary in component.patches:
		var destination: Rect2 = patch.destination
		if patch.kind == &"center":
			fills.append(destination)
			continue
		var source: Rect2 = patch.source
		var dimensions: Vector2 = component.mask_size
		var uv_first := source.position / dimensions
		var uv_last := source.end / dimensions
		if patch.flip_h:
			var first_x := uv_first.x
			uv_first.x = uv_last.x
			uv_last.x = first_x
		if patch.flip_v:
			var first_y := uv_first.y
			uv_first.y = uv_last.y
			uv_last.y = first_y
		var first := points.size()
		points.append_array(PackedVector2Array([destination.position, Vector2(destination.end.x, destination.position.y), destination.end, Vector2(destination.position.x, destination.end.y)]))
		uvs.append_array(PackedVector2Array([uv_first, Vector2(uv_last.x, uv_first.y), uv_last, Vector2(uv_first.x, uv_last.y)]))
		indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))
	return {"points": points, "uvs": uvs, "indices": indices, "fills": fills}


func _build_surface(surface: Dictionary) -> void:
	var viewport := RenderingServer.viewport_create()
	var canvas := RenderingServer.canvas_create()
	surface.viewport = viewport
	surface.canvas = canvas
	var pixels: Vector2i = surface.pixel_size
	RenderingServer.viewport_set_size(viewport, pixels.x, pixels.y)
	RenderingServer.viewport_set_disable_3d(viewport, true)
	RenderingServer.viewport_set_transparent_background(viewport, true)
	RenderingServer.viewport_set_clear_mode(viewport, RenderingServer.VIEWPORT_CLEAR_ALWAYS)
	RenderingServer.viewport_set_default_canvas_item_texture_filter(viewport, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR)
	RenderingServer.viewport_attach_canvas(viewport, canvas)
	var ratio: float = surface.pixel_ratio
	var bounds: Rect2 = surface.bounds
	RenderingServer.viewport_set_canvas_transform(viewport, canvas, Transform2D(0.0, Vector2.ONE * ratio, 0.0, -bounds.position * ratio))
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		RenderingServer.viewport_set_parent_viewport(viewport, tree.root.get_viewport_rid())
	var order := 0
	for part: Dictionary in surface.prepared:
		var item := RenderingServer.canvas_item_create()
		surface.items.append(item)
		RenderingServer.canvas_item_set_parent(item, canvas)
		RenderingServer.canvas_item_set_draw_index(item, order)
		RenderingServer.canvas_item_set_transform(item, part.transform)
		RenderingServer.canvas_item_set_material(item, part.material.get_rid())
		var mesh: Dictionary = part.mesh
		for fill: Rect2 in mesh.fills:
			RenderingServer.canvas_item_add_rect(item, fill, Color.WHITE)
		if not mesh.points.is_empty():
			var colors := PackedColorArray()
			colors.resize(mesh.points.size())
			colors.fill(Color.WHITE)
			RenderingServer.canvas_item_add_triangle_array(item, mesh.indices, mesh.points, colors, mesh.uvs, PackedInt32Array(), PackedFloat32Array(), part.mask.get_rid())
		order += 1
	RenderingServer.viewport_set_update_mode(viewport, RenderingServer.VIEWPORT_UPDATE_ONCE)
	RenderingServer.viewport_set_active(viewport, true)
	surface.texture = RenderingServer.viewport_get_texture(viewport)


func _on_frame_rendered() -> void:
	for surface: Dictionary in entries.values():
		if not surface.headless and not surface.ready:
			surface.ready = true
	_notify_consumers.call_deferred()


func _bind(owner: Object, slot: String, key: String) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var id := owner.get_instance_id()
	if not consumers.has(id):
		consumers[id] = {"owner": weakref(owner), "slots": {}}
	consumers[id].slots[slot] = key


func _notify_consumers() -> void:
	for id: int in consumers.keys():
		var owner: Object = consumers[id].owner.get_ref()
		if owner == null:
			consumers.erase(id)
		elif owner is CanvasItem:
			owner.queue_redraw()
		elif owner is Resource:
			owner.emit_changed()


func _collect(incoming_bytes: int) -> void:
	var used := {}
	for id: int in consumers.keys():
		var owner: Object = consumers[id].owner.get_ref()
		if owner == null:
			consumers.erase(id)
			continue
		for key: String in consumers[id].slots.values():
			used[key] = true
	var candidates: Array[Dictionary] = []
	for surface: Dictionary in entries.values():
		if not used.has(surface.key):
			candidates.append(surface)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.last_used < b.last_used)
	for surface: Dictionary in candidates:
		if allocated_bytes + incoming_bytes <= MAX_BYTES and entries.size() < MAX_ENTRIES:
			break
		_release(surface)
		entries.erase(surface.key)


func prune_unreferenced() -> void:
	var used := {}
	for id: int in consumers.keys():
		var owner: Object = consumers[id].owner.get_ref()
		if owner == null:
			consumers.erase(id)
			continue
		for key: String in consumers[id].slots.values():
			used[key] = true
	for key: String in entries.keys():
		if not used.has(key):
			_release(entries[key])
			entries.erase(key)


func _release(surface: Dictionary) -> void:
	if surface.viewport.is_valid():
		RenderingServer.viewport_set_active(surface.viewport, false)
	for item: RID in surface.items:
		RenderingServer.free_rid(item)
	if surface.canvas.is_valid():
		RenderingServer.free_rid(surface.canvas)
	if surface.viewport.is_valid():
		RenderingServer.free_rid(surface.viewport)
		released_surfaces += 1
	allocated_bytes -= int(surface.bytes)
	surface.prepared.clear()
	surface.items.clear()
	surface.texture = RID()
	surface.viewport = RID()
	surface.canvas = RID()


func clear() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_rendered):
		RenderingServer.frame_post_draw.disconnect(_on_frame_rendered)
	for surface: Dictionary in entries.values():
		_release(surface)
	entries.clear()
	consumers.clear()
	allocated_bytes = 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for surface: Dictionary in entries.values():
			if surface.viewport.is_valid():
				RenderingServer.viewport_set_active(surface.viewport, false)
			for item: RID in surface.items:
				RenderingServer.free_rid(item)
			if surface.canvas.is_valid():
				RenderingServer.free_rid(surface.canvas)
			if surface.viewport.is_valid():
				RenderingServer.free_rid(surface.viewport)
