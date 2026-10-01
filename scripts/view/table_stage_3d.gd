class_name TableStage3D
extends Control

signal camera_transition_finished

const CANVAS_SIZE := Vector2i(3200, 2200)
const CAMERA_GEOMETRY := preload("res://scripts/view/table_camera_geometry.gd")
const PIXELS_PER_UNIT := CAMERA_GEOMETRY.PIXELS_PER_UNIT
const CAMERA_FOV := CAMERA_GEOMETRY.FOV_DEGREES
const CAMERA_ELEVATION := CAMERA_GEOMETRY.ELEVATION_DEGREES
const TABLE_TEXTURE := "res://assets/art/forest_rebuild/earth-tile.png"
const MEADOW_TEXTURE := "res://assets/art/forest_rebuild/forest-floor-tile.png"
const SURFACE_SHADER := preload("res://assets/shaders/painterly_tiling.gdshader")
const EDITABLE_TABLE_SCENE := preload("res://scenes/world/table_environment_editable.tscn")

var card_canvas: SubViewport
var viewport_3d: SubViewport
var scene_root: Node3D
var environment_root: Node3D
var painted_vegetation: Node3D
var camera_3d: Camera3D
var pointer_light: OmniLight3D
var _pointer_screen := Vector2(-10000, -10000)
var screen_rect := Rect2()
var camera_model: TableCamera

var _image: TextureRect
var _far_background: MeshInstance3D
var _table_title: Control
var _active := true
var _narrative_ratio := 1.0
var _world: Node2D
var _effective_rect := Rect2()
var _render_scale := Vector2.ONE
var _card_plane: MeshInstance3D
var _capture_rect := Rect2()
var _capture_density := 0.0
var _menu_view := false
var _menu_blend := 0.0
var _transition_from := 0.0
var _transition_elapsed := 1.3
var _camera_transition_frozen := false
var _cards_visible := true
const CAMERA_TRANSITION_DURATION := 1.3


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_menu_view(value: bool, instant: bool = false) -> void:
	if _menu_view == value and not instant:
		return
	_menu_view = value
	_transition_from = _menu_blend
	_transition_elapsed = CAMERA_TRANSITION_DURATION if instant else 0.0
	if instant:
		_menu_blend = 1.0 if value else 0.0
	refresh_camera()

func is_camera_transitioning() -> bool:
	return _transition_elapsed < CAMERA_TRANSITION_DURATION

func freeze_camera_transition(value: bool) -> void:
	_camera_transition_frozen = value


func _ready() -> void:
	add_to_group("click_particle_stage")
	_ensure_nodes()
	refresh_camera()


func can_emit_click_dust(screen: Vector2) -> bool:
	if not _active or get_tree().paused or _menu_view or not _effective_rect.has_point(screen):
		return false
	# Reuse the table's existing UI exclusion policy instead of duplicating it.
	var context := get_parent()
	return not context.has_method("_pointer_blocked") or not context.call("_pointer_blocked", screen)


func configure(value: Rect2, model: TableCamera) -> void:
	screen_rect = value
	camera_model = model
	_ensure_nodes()
	refresh_camera()


func attach_world(world: Node2D) -> void:
	_ensure_nodes()
	_world = world
	if world.get_parent() != card_canvas:
		if world.get_parent() != null:
			world.reparent(card_canvas, false)
		else:
			card_canvas.add_child(world)
	_fix_world_transform()


func set_active(value: bool) -> void:
	_active = value
	visible = value
	if is_instance_valid(viewport_3d):
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
		card_canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	if value:
		refresh_camera()


func set_cards_visible(value: bool) -> void:
	_cards_visible = value
	if is_instance_valid(_card_plane):
		_card_plane.visible = value and _capture_rect.has_area() and _menu_blend < 0.98


func set_narrative_ratio(value: float) -> void:
	_narrative_ratio = clampf(value, 0.35, 1.0)
	refresh_camera()


func refresh_camera() -> void:
	if not is_instance_valid(camera_3d) or screen_rect.size.x <= 0.0 or screen_rect.size.y <= 0.0:
		return
	var probe_started := HitchProbe.stamp()
	_effective_rect = Rect2(screen_rect.position, Vector2(screen_rect.size.x * _narrative_ratio, screen_rect.size.y))
	position = _effective_rect.position
	size = _effective_rect.size
	_image.position = Vector2.ZERO
	_image.size = size
	# 逻辑坐标用于布局；帧缓冲按窗口实际像素创建，避免高分屏二次放大。
	var physical_scale := get_viewport().get_stretch_transform().get_scale().abs()
	var pixel_size := Vector2i(maxi(1, roundi(size.x * physical_scale.x)), maxi(1, roundi(size.y * physical_scale.y)))
	if viewport_3d.size != pixel_size:
		viewport_3d.size = pixel_size
	_render_scale = Vector2(pixel_size) / size
	var zoom_value := maxf(camera_model.zoom, 0.01) if camera_model != null else 1.0
	var center := (camera_model.bounds.get_center() - camera_model.offset) / zoom_value if camera_model != null else Vector2.ZERO
	var game_transform := CAMERA_GEOMETRY.gameplay_transform(size.y, zoom_value, center)
	# 菜单只把概览取景向棋盘上方平移，保持概览高度与焦距，不沿后坡推进。
	var menu_transform := CAMERA_GEOMETRY.menu_transform(size.y)
	camera_3d.position = game_transform.origin.lerp(menu_transform.origin, _menu_blend)
	camera_3d.basis = Basis(
		game_transform.basis.get_rotation_quaternion().slerp(
			menu_transform.basis.get_rotation_quaternion(),
			_menu_blend
		)
	)
	camera_3d.fov = CAMERA_FOV
	_fix_world_transform()
	_refresh_card_capture(zoom_value)
	var upper_edge := to_screen(Vector2(0, TableState.WORLD_BOUNDS.position.y)).y - _effective_rect.position.y
	_table_title.position = Vector2(to_screen(Vector2(0, TableState.WORLD_BOUNDS.position.y)).x - _effective_rect.position.x - 92.0, upper_edge - 34.0)
	_table_title.visible = false
	_card_plane.visible = _cards_visible and _card_plane.visible and _menu_blend < 0.98
	for child in environment_root.get_children():
		if child.has_method("set_camera_basis"):
			child.set_camera_basis(camera_3d.global_basis)
		if child.has_method("ensure_visible_area") and _menu_blend < 0.001:
			var visible_world := Rect2(to_world(_effective_rect.position), Vector2.ZERO)
			for corner: Vector2 in [Vector2(_effective_rect.end.x, _effective_rect.position.y), _effective_rect.end, Vector2(_effective_rect.position.x, _effective_rect.end.y)]:
				visible_world = visible_world.expand(to_world(corner))
			child.ensure_visible_area(visible_world)
	if _active:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		card_canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	HitchProbe.record("stage_refresh_camera", probe_started)


func to_world(screen: Vector2) -> Vector2:
	if not is_instance_valid(camera_3d) or not camera_3d.is_inside_tree():
		return Vector2.ZERO
	var local := (screen - _effective_rect.position) * _render_scale
	var inverse := scene_root.global_transform.affine_inverse()
	var ray_origin := inverse * camera_3d.project_ray_origin(local)
	var direction := (inverse.basis * camera_3d.project_ray_normal(local)).normalized()
	var intersection: Variant = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, direction)
	if intersection == null:
		return Vector2(INF, INF)
	var point: Vector3 = intersection
	return Vector2(point.x, point.z) * PIXELS_PER_UNIT


func to_terrain(screen: Vector2) -> Vector2:
	var local := (screen - _effective_rect.position) * _render_scale
	var inverse := scene_root.global_transform.affine_inverse()
	return FoldedTerrain.from_ray(
		inverse * camera_3d.project_ray_origin(local),
		(inverse.basis * camera_3d.project_ray_normal(local)).normalized()
	)


func to_screen(world: Vector2) -> Vector2:
	if not is_instance_valid(camera_3d) or not camera_3d.is_inside_tree():
		return Vector2.ZERO
	var point := Vector3(world.x / PIXELS_PER_UNIT, 0.0, world.y / PIXELS_PER_UNIT)
	return camera_3d.unproject_position(scene_root.to_global(point)) / _render_scale + _effective_rect.position


func _refresh_card_capture(zoom_value: float) -> void:
	if not is_instance_valid(_card_plane):
		return
	var corners := [_effective_rect.position, Vector2(_effective_rect.end.x, _effective_rect.position.y), _effective_rect.end, Vector2(_effective_rect.position.x, _effective_rect.end.y)]
	var capture := TableState.WORLD_BOUNDS
	if _menu_blend < 0.001:
		var first := true
		for corner: Vector2 in corners:
			var point := to_world(corner)
			if not point.is_finite():
				continue
			capture = Rect2(point, Vector2.ZERO) if first else capture.expand(point)
			first = false
		if first:
			_card_plane.visible = false
			return
	# 只画当前视野，按64逻辑像素分块稳定尺寸，避免拖动时反复分配全棋盘大纹理。
	capture = capture.grow(32.0)
	var start := (capture.position / 64.0).floor() * 64.0
	var finish := (capture.end / 64.0).ceil() * 64.0
	capture = Rect2(start, finish - start).intersection(TableState.WORLD_BOUNDS)
	_card_plane.visible = _cards_visible and capture.has_area()
	if not capture.has_area():
		return
	var density := maxf(1.0, ceilf(zoom_value * maxf(_render_scale.x, _render_scale.y) * 1.35 * 2.0) * 0.5)
	density = minf(density, 8192.0 / maxf(capture.size.x, capture.size.y))
	# 帧缓冲跟随物理视口分配，不随每个缩放中间帧重新创建GPU纹理。
	var pixels := Vector2i(mini(8192, ceili(viewport_3d.size.x * 1.75 / 256.0) * 256), mini(8192, ceili(viewport_3d.size.y * 1.75 / 256.0) * 256))
	if capture == _capture_rect and card_canvas.size == pixels:
		return
	_capture_rect = capture
	_capture_density = density
	if card_canvas.size != pixels:
		card_canvas.size = pixels
	var raster_scale := Vector2(pixels) / capture.size
	card_canvas.canvas_transform = Transform2D(Vector2(raster_scale.x, 0), Vector2(0, raster_scale.y), -(Vector2(CANVAS_SIZE) * 0.5 + capture.position) * raster_scale)
	(_card_plane.mesh as PlaneMesh).size = capture.size / PIXELS_PER_UNIT
	_card_plane.position = Vector3(capture.get_center().x / PIXELS_PER_UNIT, 0.0, capture.get_center().y / PIXELS_PER_UNIT)


func get_display_rect() -> Rect2:
	return _effective_rect


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_pointer_screen = event.position


func _process(delta: float) -> void:
	if _active:
		if is_camera_transitioning() and not _camera_transition_frozen:
			_transition_elapsed = minf(_transition_elapsed + delta, CAMERA_TRANSITION_DURATION)
			var progress := smoothstep(0.0, 1.0, _transition_elapsed / CAMERA_TRANSITION_DURATION)
			_menu_blend = lerpf(_transition_from, 1.0 if _menu_view else 0.0, progress)
			if not is_camera_transitioning():
				camera_transition_finished.emit()
		refresh_camera()
		var screen_pointer := _pointer_screen
		pointer_light.visible = not _menu_view and not is_camera_transitioning() and not _camera_transition_frozen and _effective_rect.has_point(screen_pointer)
		if pointer_light.visible:
			var at := to_terrain(screen_pointer)
			pointer_light.visible = at.is_finite()
			if pointer_light.visible:
				pointer_light.position = FoldedTerrain.world_position(at) + Vector3(0, 1.7, 0)
		if is_instance_valid(painted_vegetation) and painted_vegetation.has_method("set_pointer_light"):
			painted_vegetation.call(
				"set_pointer_light",
				pointer_light.global_position,
				pointer_light.omni_range,
				pointer_light.light_energy,
				pointer_light.light_color,
				pointer_light.visible
			)


func _fix_world_transform() -> void:
	if is_instance_valid(_world):
		_world.position = Vector2(CANVAS_SIZE) * 0.5
		_world.scale = Vector2.ONE
		_world.rotation = 0.0


func _ensure_nodes() -> void:
	if is_instance_valid(viewport_3d):
		return
	card_canvas = SubViewport.new()
	card_canvas.name = "CardCanvas"
	card_canvas.process_mode = Node.PROCESS_MODE_PAUSABLE
	card_canvas.size = CANVAS_SIZE
	card_canvas.disable_3d = true
	card_canvas.transparent_bg = true
	card_canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	card_canvas.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	card_canvas.gui_disable_input = true
	card_canvas.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(card_canvas)
	viewport_3d = SubViewport.new()
	viewport_3d.name = "TableViewport3D"
	viewport_3d.size = Vector2i(1280, 800)
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_3d.gui_disable_input = true
	add_child(viewport_3d)
	scene_root = EDITABLE_TABLE_SCENE.instantiate() as Node3D
	viewport_3d.add_child(scene_root)
	environment_root = scene_root.get_node("EnvironmentRoot") as Node3D
	painted_vegetation = environment_root.get_node_or_null("EditableVegetation") as Node3D
	_far_background = scene_root.get_node_or_null("DistantSkyWorldPlane") as MeshInstance3D
	camera_3d = Camera3D.new()
	camera_3d.name = "TableCamera3D"
	camera_3d.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera_3d.keep_aspect = Camera3D.KEEP_HEIGHT
	camera_3d.fov = CAMERA_FOV
	camera_3d.near = 0.05
	camera_3d.far = 1400.0
	camera_3d.current = true
	scene_root.add_child(camera_3d)
	_build_card_plane()
	pointer_light = OmniLight3D.new()
	pointer_light.name = "PointerWarmLight"
	pointer_light.light_color = Color("ffd7a0")
	pointer_light.light_energy = 1.5
	pointer_light.omni_range = 4.5
	pointer_light.omni_attenuation = 1.4
	pointer_light.shadow_enabled = false
	pointer_light.visible = false
	scene_root.add_child(pointer_light)
	_image = TextureRect.new()
	_image.name = "TablePerspectiveImage"
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.texture = viewport_3d.get_texture()
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_image)
	_table_title = preload("res://scripts/ui/forest_board_title.gd").new()
	add_child(_table_title)


func _build_board() -> void:
	var extent := TableState.WORLD_BOUNDS.size / PIXELS_PER_UNIT
	var slab := MeshInstance3D.new()
	slab.name = "BoardThickness"
	var box := BoxMesh.new()
	box.size = Vector3(extent.x, 0.16, extent.y)
	slab.mesh = box
	# Keep the slab top clear of the imported painted surface. At -0.10 the
	# surfaces were only 2 mm apart, so the plain slab won the depth test.
	slab.position.y = -0.15
	slab.visible = false
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color("30251e")
	edge.roughness = 0.95
	slab.material_override = edge
	scene_root.add_child(slab)
	var surface := MeshInstance3D.new()
	surface.name = "BoardSurface"
	var base := ShaderMaterial.new()
	base.shader = SURFACE_SHADER
	base.set_shader_parameter("grain", load(TABLE_TEXTURE))
	base.set_shader_parameter("tile_size_meters", 6.0)
	base.set_shader_parameter("surface_tint", Color.WHITE)
	base.set_shader_parameter("unfolded_coordinates", true)
	var ground := ShaderMaterial.new()
	ground.shader = SURFACE_SHADER
	ground.set_shader_parameter("grain", load(MEADOW_TEXTURE))
	ground.set_shader_parameter("tile_size_meters", 4.0)
	ground.set_shader_parameter("unfolded_coordinates", true)
	surface.mesh = load("res://assets/models/terrain/board-terrain-user-v1.res") as ArrayMesh
	if surface.mesh == null:
		surface.mesh = FoldedTerrain.make_mesh(base,ground)
	else:
		surface.set_surface_override_material(0,ground)
		if surface.mesh.get_surface_count()>1:
			surface.set_surface_override_material(1,base)
	scene_root.add_child(surface)
	var wood := ShaderMaterial.new()
	wood.shader = SURFACE_SHADER
	wood.set_shader_parameter("grain", load("res://assets/art/forest_rebuild/wood-rim-tile.png"))
	wood.set_shader_parameter("tile_size_meters", 2.0)
	for side in 4:
		var beam := MeshInstance3D.new()
		beam.name = "WoodRim" + str(side)
		var shape := BoxMesh.new()
		shape.size = Vector3(extent.x + 1.4, 0.28, 0.72) if side < 2 else Vector3(0.72,0.28,extent.y)
		beam.mesh = shape
		beam.material_override = wood
		beam.position = Vector3(0,-0.055, (-1.0 if side == 0 else 1.0) * (extent.y * 0.5 + 0.30)) if side < 2 else Vector3((-1.0 if side == 2 else 1.0) * (extent.x * 0.5 + 0.30),-0.055,0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		scene_root.add_child(beam)
	_build_card_plane()


func _build_card_plane() -> void:
	var extent := TableState.WORLD_BOUNDS.size / PIXELS_PER_UNIT
	var cards := MeshInstance3D.new()
	_card_plane = cards
	cards.name = "CardPlane"
	var card_mesh := PlaneMesh.new()
	card_mesh.size = extent
	cards.mesh = card_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = card_canvas.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.disable_receive_shadows = true
	cards.material_override = material
	cards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene_root.add_child(cards)


func _build_far_background() -> void:
	_far_background = MeshInstance3D.new()
	_far_background.name = "DistantSkyWorldPlane"
	var plane := QuadMesh.new()
	plane.size = Vector2(500, 500.0 / 3.0)
	_far_background.mesh = plane
	_far_background.position = Vector3(0, -290, -173)
	_far_background.rotation.x = deg_to_rad(-CAMERA_ELEVATION)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = load("res://assets/art/forest_rebuild/distant-river.png")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_far_background.material_override = material
	_far_background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene_root.add_child(_far_background)

