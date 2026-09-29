@tool
class_name GrassPatch3D
extends Node3D

const GRASS_SHADER := preload("res://addons/grass_painter/grass_material.gdshader")
const FOLDED_TERRAIN := preload("res://scripts/view/folded_terrain.gd")
const RENDERER_NAME := &"__GrassRenderer"
const PREVIEW_NAME := &"__GrassBrushPreview"

@export_category("Feature Switches")
@export var wind_enabled := true:
	set(value):
		wind_enabled = value
		_set_live_shader_parameter(&"wind_enabled", wind_enabled)
@export var player_interaction_enabled := true:
	set(value):
		player_interaction_enabled = value
		_set_live_shader_parameter(
			&"player_interaction_enabled",
			player_interaction_enabled
		)
		if not player_interaction_enabled:
			_player = null
@export var color_adjustment_enabled := true:
	set(value):
		color_adjustment_enabled = value
		_set_live_shader_parameter(
			&"color_adjustment_enabled",
			color_adjustment_enabled
		)

@export_category("Visual")
@export var static_texture: Texture2D:
	set(value):
		if static_texture == value:
			return
		static_texture = value
		_fit_quad_to_texture_aspect(static_texture)
		if is_inside_tree():
			_rebuild_instances()
@export var quad_size := Vector2(0.82, 0.32)
@export var flip_horizontal := false:
	set(value):
		flip_horizontal = value
		_set_live_shader_parameter(&"flip_horizontal", flip_horizontal)
@export_range(0.0, 1.0, 0.01) var alpha_scissor := 0.18
@export_range(0.0, 1.0, 0.01) var color_saturation := 0.72
@export var natural_color_multiplier := Color(0.96, 0.78, 0.72, 1.0)
@export_range(0.0, 2.0, 0.05) var outline_width_pixels := 1.25:
	set(value):
		outline_width_pixels = clampf(value, 0.0, 2.0)
		_set_live_shader_parameter(&"outline_width_pixels", outline_width_pixels)
@export_range(0.0, 1.0, 0.01) var outline_strength := 0.46:
	set(value):
		outline_strength = clampf(value, 0.0, 1.0)
		_set_live_shader_parameter(&"outline_strength", outline_strength)
@export var outline_color := Color(0.10, 0.15, 0.09, 1.0):
	set(value):
		outline_color = value
		_set_live_shader_parameter(&"outline_color", outline_color)
@export_range(0.0, 20.0, 0.1) var outline_forward_distance_limit := 5.0:
	set(value):
		outline_forward_distance_limit = clampf(value, 0.0, 20.0)
		_set_live_shader_parameter(
			&"outline_forward_distance_limit",
			outline_forward_distance_limit
		)

@export_category("Color Variation")
@export_range(0.0, 0.35, 0.01) var color_variation_strength := 0.10:
	set(value):
		color_variation_strength = clampf(value, 0.0, 0.35)
		_set_live_shader_parameter(
			&"color_variation_strength",
			color_variation_strength
		)
@export var cool_color_multiplier := Color(0.88, 0.99, 1.08, 1.0):
	set(value):
		cool_color_multiplier = value
		_set_live_shader_parameter(&"cool_color_multiplier", cool_color_multiplier)
@export var warm_color_multiplier := Color(1.08, 1.02, 0.88, 1.0):
	set(value):
		warm_color_multiplier = value
		_set_live_shader_parameter(&"warm_color_multiplier", warm_color_multiplier)
@export_range(0.0, 0.3, 0.01) var shape_variation_strength := 0.08:
	set(value):
		shape_variation_strength = clampf(value, 0.0, 0.3)
		_set_live_shader_parameter(
			&"shape_variation_strength",
			shape_variation_strength
		)

@export_category("Landscape Color Regions")
@export_range(0.0, 1.0, 0.01) var region_color_strength := 0.78:
	set(value):
		region_color_strength = clampf(value, 0.0, 1.0)
		_set_live_shader_parameter(&"region_color_strength", region_color_strength)
@export_range(2.0, 30.0, 0.5) var region_size_meters := 4.5:
	set(value):
		region_size_meters = clampf(value, 2.0, 30.0)
		_set_live_shader_parameter(&"region_size_meters", region_size_meters)
		_refresh_existing_landscape_regions()
@export var shadow_region_multiplier := Color(0.12, 0.32, 0.28, 1.0):
	set(value):
		shadow_region_multiplier = value
		_set_live_shader_parameter(
			&"shadow_region_multiplier",
			shadow_region_multiplier
		)
@export var base_region_multiplier := Color(0.28, 0.54, 0.28, 1.0):
	set(value):
		base_region_multiplier = value
		_set_live_shader_parameter(&"base_region_multiplier", base_region_multiplier)
@export var sunlit_region_multiplier := Color(0.60, 0.72, 0.34, 1.0):
	set(value):
		sunlit_region_multiplier = value
		_set_live_shader_parameter(
			&"sunlit_region_multiplier",
			sunlit_region_multiplier
		)
@export_range(0.02, 0.3, 0.01) var region_transition_softness := 0.06:
	set(value):
		region_transition_softness = clampf(value, 0.02, 0.3)
		_set_live_shader_parameter(
			&"region_transition_softness",
			region_transition_softness
		)

@export_category("Distribution")
@export var auto_fill_on_empty := true
@export var fill_extents := Vector2(42.0, 28.0)
@export var fill_density := 0.55
@export var minimum_spacing := 0.58
@export_range(0.0, 1.0, 0.01) var cluster_threshold := 0.36
@export var distribution_seed := 480731

@export_category("Variation")
@export var minimum_scale := 0.72
@export var maximum_scale := 1.18
@export_range(0.0, 45.0, 0.5) var maximum_y_rotation_degrees := 14.0

@export_category("Procedural Wind")
@export var wind_direction := Vector2(1.0, 0.24)
@export_range(0.0, 0.4, 0.005) var wind_strength := 0.105
@export_range(0.0, 4.0, 0.05) var wind_speed := 1.05
@export_range(0.01, 2.0, 0.01) var wind_wave_scale := 0.42
@export_range(0.01, 4.0, 0.01) var wind_detail_scale := 1.30
@export_range(0.0, 6.0, 0.05) var wind_detail_speed := 1.70
@export_range(0.2, 4.0, 0.05) var wind_wave_sharpness := 1.55
@export_range(0.5, 4.0, 0.05) var wind_root_power := 1.75

@export_category("Player Interaction")
@export_range(0.1, 4.0, 0.05) var disturbance_radius := 1.1
@export_range(0.0, 5.0, 0.05) var disturbance_speed_threshold := 0.2
@export_range(0.0, 0.5, 0.01) var player_bend_strength := 0.18
@export_range(0.0, 0.8, 0.01) var player_vertical_compression := 0.24
@export_node_path("Node3D") var player_path: NodePath

@export_storage var grass_positions := PackedVector3Array()
@export_storage var grass_rotations := PackedFloat32Array()
@export_storage var grass_scales := PackedFloat32Array()
@export_storage var grass_phases := PackedFloat32Array()
@export_storage var grass_tints := PackedFloat32Array()
@export_storage var suppress_auto_fill := false

var _renderer: MultiMeshInstance3D
var _material: ShaderMaterial
var _brush_preview: MeshInstance3D
var _player: Node3D
var _landscape_regions := PackedFloat32Array()
var _external_position := Vector3.ZERO
var _external_velocity := Vector3.ZERO
var _external_interaction_age := INF


func _ready() -> void:
	_fit_quad_to_texture_aspect(static_texture)
	_rebuild_instances()
	set_process(true)


func _process(delta: float) -> void:
	if _material == null:
		return
	if not player_interaction_enabled:
		return
	_external_interaction_age += maxf(delta, 0.0)
	if not is_instance_valid(_player):
		_player = get_node_or_null(player_path) as Node3D
		if _player == null and not Engine.is_editor_hint():
			_player = get_tree().get_first_node_in_group("player") as Node3D

	var current_position := Vector3.ZERO
	var current_velocity := Vector3.ZERO
	if is_instance_valid(_player):
		current_position = _player.global_position
		if _player is CharacterBody3D:
			current_velocity = (_player as CharacterBody3D).velocity
	elif _external_interaction_age < 0.42:
		current_position = _external_position
		current_velocity = _external_velocity * exp(-_external_interaction_age * 7.5)
	_material.set_shader_parameter("player_position", current_position)
	_material.set_shader_parameter("player_velocity", current_velocity)


func rebuild() -> void:
	_rebuild_instances()


func set_external_interaction(world_position: Vector3, world_velocity: Vector3) -> void:
	_external_position = world_position
	_external_velocity = world_velocity
	_external_interaction_age = 0.0


func set_table_environment_state(
	elapsed: float,
	events: PackedVector4Array,
	directions: PackedVector4Array,
	segments: PackedVector4Array,
	camera_basis: Basis
) -> void:
	if not is_instance_valid(_material):
		return
	_material.set_shader_parameter("elapsed", elapsed)
	_material.set_shader_parameter("events", events)
	_material.set_shader_parameter("directions", directions)
	_material.set_shader_parameter("segments", segments)
	_material.set_shader_parameter("facing_right", camera_basis.x)
	_material.set_shader_parameter("facing_up", camera_basis.y)
	_material.set_shader_parameter("facing_forward", camera_basis.z)
	_material.set_shader_parameter("wind_strength", wind_strength if wind_enabled else 0.0)
	_material.set_shader_parameter("wind_speed", wind_speed)
	_material.set_shader_parameter("wind_direction", wind_direction)
	_material.set_shader_parameter("wind_wave_scale", wind_wave_scale)
	_material.set_shader_parameter("wind_detail_scale", wind_detail_scale)
	_material.set_shader_parameter("wind_detail_speed", wind_detail_speed)
	_material.set_shader_parameter("wind_wave_sharpness", wind_wave_sharpness)
	_material.set_shader_parameter("wind_root_power", wind_root_power)
	_material.set_shader_parameter("bend_strength", 1.0 if wind_enabled or player_interaction_enabled else 0.0)
	_material.set_shader_parameter("interaction_strength", player_bend_strength if player_interaction_enabled else 0.0)
	_material.set_shader_parameter("disturbance_radius", disturbance_radius)


func set_table_pointer_light(
	position: Vector3,
	light_range: float,
	energy: float,
	color: Color,
	enabled: bool
) -> void:
	if not is_instance_valid(_material):
		return
	_material.set_shader_parameter("pointer_light_position", position)
	_material.set_shader_parameter("pointer_light_range", maxf(light_range, 0.001))
	_material.set_shader_parameter("pointer_light_energy", maxf(energy, 0.0))
	_material.set_shader_parameter("pointer_light_color", Vector3(color.r, color.g, color.b))
	_material.set_shader_parameter("pointer_light_enabled", enabled)


func _fit_quad_to_texture_aspect(texture: Texture2D) -> void:
	if texture == null:
		return
	var texture_size := texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var preserved_height := maxf(quad_size.y, 0.001)
	quad_size = Vector2(
		preserved_height * texture_size.x / texture_size.y,
		preserved_height
	)


func _set_live_shader_parameter(parameter: StringName, value: Variant) -> void:
	if is_instance_valid(_material):
		_material.set_shader_parameter(parameter, value)


func _refresh_existing_landscape_regions() -> void:
	if (
		not is_inside_tree()
		or not is_instance_valid(_renderer)
		or _renderer.multimesh == null
	):
		return
	var distribution := snapshot_distribution()
	if grass_positions.is_empty() and auto_fill_on_empty and not suppress_auto_fill:
		distribution = _generate_default_distribution()
	var positions: PackedVector3Array = distribution.get(
		"positions",
		PackedVector3Array()
	)
	var grass_multimesh := _renderer.multimesh
	if positions.size() != grass_multimesh.instance_count:
		_rebuild_instances()
		return
	_landscape_regions.resize(positions.size())
	for index in positions.size():
		var anchor := _unfolded_anchor_from_local_position(positions[index])
		var logical_y := anchor.y
		var region_value := _landscape_region(anchor)
		_landscape_regions[index] = region_value
		var custom_data := grass_multimesh.get_instance_custom_data(index)
		custom_data.b = logical_y
		custom_data.a = _value_or_default(grass_scales, index, 1.0)
		grass_multimesh.set_instance_custom_data(index, custom_data)


func materialize_default_fill() -> void:
	if (
		not grass_positions.is_empty()
		or not auto_fill_on_empty
		or suppress_auto_fill
	):
		return
	restore_distribution(_generate_default_distribution())


func bake_default_fill() -> void:
	restore_distribution(_generate_default_distribution())


func bake_default_fill_with_parameters(
	density: float,
	spacing: float,
	minimum_instance_scale: float,
	maximum_instance_scale: float,
	surface_sampler: Callable = Callable()
) -> void:
	restore_distribution(
		_generate_default_distribution(
			density,
			spacing,
			minimum_instance_scale,
			maximum_instance_scale,
			surface_sampler
		)
	)


func clear_distribution() -> void:
	restore_distribution(_empty_distribution(true))


func snapshot_distribution() -> Dictionary:
	return {
		"positions": grass_positions.duplicate(),
		"rotations": grass_rotations.duplicate(),
		"scales": grass_scales.duplicate(),
		"phases": grass_phases.duplicate(),
		"tints": grass_tints.duplicate(),
		"suppress_auto_fill": suppress_auto_fill,
	}


func snapshot_landscape_regions() -> PackedFloat32Array:
	return _landscape_regions.duplicate()


func restore_distribution(snapshot: Dictionary) -> void:
	grass_positions = snapshot.get("positions", PackedVector3Array()).duplicate()
	grass_rotations = snapshot.get("rotations", PackedFloat32Array()).duplicate()
	grass_scales = snapshot.get("scales", PackedFloat32Array()).duplicate()
	grass_phases = snapshot.get("phases", PackedFloat32Array()).duplicate()
	grass_tints = snapshot.get("tints", PackedFloat32Array()).duplicate()
	suppress_auto_fill = bool(snapshot.get("suppress_auto_fill", false))
	_rebuild_instances()


func paint_stamp(
	world_center: Vector3,
	radius: float,
	density: float,
	minimum_instance_spacing: float,
	minimum_instance_scale: float,
	maximum_instance_scale: float,
	erase: bool,
	surface_sampler: Callable = Callable()
) -> void:
	materialize_default_fill()
	suppress_auto_fill = true
	var local_center := to_local(world_center)
	if not surface_sampler.is_valid():
		local_center.y = 0.0
	if erase:
		_erase_local(local_center, radius)
	else:
		_paint_local(
			local_center,
			radius,
			density,
			minimum_instance_spacing,
			minimum_instance_scale,
			maximum_instance_scale,
			surface_sampler
		)
	_rebuild_instances()


func set_brush_preview(world_center: Vector3, radius: float, visible: bool) -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_brush_preview()
	_brush_preview.visible = visible
	if not visible:
		return

	var preview_mesh := ImmediateMesh.new()
	var preview_material := StandardMaterial3D.new()
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.no_depth_test = true
	preview_material.albedo_color = Color(0.95, 0.72, 0.18, 0.92)
	preview_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, preview_material)
	var local_center := to_local(world_center)
	for index in 65:
		var angle := TAU * float(index) / 64.0
		preview_mesh.surface_add_vertex(
			local_center + Vector3(cos(angle) * radius, 0.06, sin(angle) * radius)
		)
	preview_mesh.surface_end()
	_brush_preview.mesh = preview_mesh


func _rebuild_instances() -> void:
	if not is_inside_tree():
		return
	_ensure_renderer()
	_material = ShaderMaterial.new()
	_material.shader = GRASS_SHADER
	_material.set_shader_parameter("static_texture", static_texture)
	_material.set_shader_parameter("alpha_scissor", alpha_scissor)
	_material.set_shader_parameter("flip_horizontal", flip_horizontal)
	_material.set_shader_parameter("wind_enabled", wind_enabled)
	_material.set_shader_parameter(
		"player_interaction_enabled",
		player_interaction_enabled
	)
	_material.set_shader_parameter(
		"color_adjustment_enabled",
		color_adjustment_enabled
	)
	_material.set_shader_parameter("color_saturation", color_saturation)
	_material.set_shader_parameter(
		"natural_color_multiplier",
		natural_color_multiplier
	)
	_material.set_shader_parameter("outline_width_pixels", outline_width_pixels)
	_material.set_shader_parameter("outline_strength", outline_strength)
	_material.set_shader_parameter("outline_color", outline_color)
	_material.set_shader_parameter(
		"outline_forward_distance_limit",
		outline_forward_distance_limit
	)
	_material.set_shader_parameter(
		"color_variation_strength",
		color_variation_strength
	)
	_material.set_shader_parameter(
		"cool_color_multiplier",
		cool_color_multiplier
	)
	_material.set_shader_parameter(
		"warm_color_multiplier",
		warm_color_multiplier
	)
	_material.set_shader_parameter(
		"shape_variation_strength",
		shape_variation_strength
	)
	_material.set_shader_parameter("region_color_strength", region_color_strength)
	_material.set_shader_parameter("region_size_meters", region_size_meters)
	_material.set_shader_parameter(
		"shadow_region_multiplier",
		shadow_region_multiplier
	)
	_material.set_shader_parameter(
		"base_region_multiplier",
		base_region_multiplier
	)
	_material.set_shader_parameter(
		"sunlit_region_multiplier",
		sunlit_region_multiplier
	)
	_material.set_shader_parameter(
		"region_transition_softness",
		region_transition_softness
	)
	_material.set_shader_parameter("wind_direction", wind_direction)
	_material.set_shader_parameter("wind_strength", wind_strength)
	_material.set_shader_parameter("wind_speed", wind_speed)
	_material.set_shader_parameter("wind_wave_scale", wind_wave_scale)
	_material.set_shader_parameter("wind_detail_scale", wind_detail_scale)
	_material.set_shader_parameter("wind_detail_speed", wind_detail_speed)
	_material.set_shader_parameter(
		"wind_wave_sharpness",
		wind_wave_sharpness
	)
	_material.set_shader_parameter("wind_root_power", wind_root_power)
	_material.set_shader_parameter("disturbance_radius", disturbance_radius)
	_material.set_shader_parameter(
		"disturbance_speed_threshold",
		disturbance_speed_threshold
	)
	_material.set_shader_parameter("player_bend_strength", player_bend_strength)
	_material.set_shader_parameter(
		"player_vertical_compression",
		player_vertical_compression
	)
	_material.set_shader_parameter(
		"bend_strength",
		1.0 if wind_enabled or player_interaction_enabled else 0.0
	)
	_material.set_shader_parameter(
		"interaction_strength",
		player_bend_strength if player_interaction_enabled else 0.0
	)

	var quad := _make_subdivided_mesh()

	var distribution := snapshot_distribution()
	if grass_positions.is_empty() and auto_fill_on_empty and not suppress_auto_fill:
		distribution = _generate_default_distribution()
	var positions: PackedVector3Array = distribution["positions"]
	var rotations: PackedFloat32Array = distribution["rotations"]
	var scales: PackedFloat32Array = distribution["scales"]
	var phases: PackedFloat32Array = distribution["phases"]
	var tints: PackedFloat32Array = distribution["tints"]

	var grass_multimesh := MultiMesh.new()
	grass_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	grass_multimesh.use_custom_data = true
	grass_multimesh.mesh = quad
	grass_multimesh.instance_count = positions.size()
	_landscape_regions.resize(positions.size())
	var bounds := AABB()
	var has_bounds := false
	for index in positions.size():
		var anchor := _unfolded_anchor_from_local_position(positions[index])
		var logical_y := anchor.y
		var region_value := _landscape_region(anchor)
		_landscape_regions[index] = region_value
		var instance_scale := _value_or_default(scales, index, 1.0)
		var instance_rotation := _value_or_default(rotations, index, 0.0)
		var basis := Basis(Vector3.UP, instance_rotation)
		basis = basis.scaled(Vector3.ONE * instance_scale)
		var origin := positions[index]
		grass_multimesh.set_instance_transform(
			index,
			Transform3D(basis, origin)
		)
		grass_multimesh.set_instance_custom_data(
			index,
			Color(
				_value_or_default(phases, index, 0.0),
				_value_or_default(tints, index, 0.5),
				logical_y,
				instance_scale
			)
		)
		if has_bounds:
			bounds = bounds.expand(origin)
		else:
			bounds = AABB(origin, Vector3.ZERO)
			has_bounds = true
	if has_bounds:
		grass_multimesh.custom_aabb = bounds.grow(maxf(quad_size.x, quad_size.y) * maximum_scale * 2.5)
	_renderer.multimesh = grass_multimesh


func _make_subdivided_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in 9:
		for column in 5:
			var at := Vector2(float(column) / 4.0, float(row) / 8.0)
			vertices.append(Vector3((at.x - 0.5) * quad_size.x, (1.0 - at.y) * quad_size.y, 0.0))
			uvs.append(at)
			normals.append(Vector3.BACK)
	for row in 8:
		for column in 4:
			var start := row * 5 + column
			indices.append_array(PackedInt32Array([start, start + 1, start + 5, start + 1, start + 6, start + 5]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	return mesh


func _logical_y_from_local_position(position: Vector3) -> float:
	var hinge := FOLDED_TERRAIN.hinge_z()
	if position.z >= hinge - 0.0001:
		return position.z
	var bevel_end := hinge - cos(FOLDED_TERRAIN.BEVEL_ANGLE) * FOLDED_TERRAIN.BEVEL_LENGTH
	if position.z >= bevel_end - 0.0001:
		return hinge - (hinge - position.z) / cos(FOLDED_TERRAIN.BEVEL_ANGLE)
	return hinge - FOLDED_TERRAIN.BEVEL_LENGTH - (bevel_end - position.z) / cos(FOLDED_TERRAIN.FOLD_ANGLE)


func _unfolded_anchor_from_local_position(position: Vector3) -> Vector2:
	var terrain_position := position
	var table_scene := _find_table_scene()
	if table_scene != null:
		terrain_position = table_scene.to_local(to_global(position))
	return Vector2(
		terrain_position.x,
		_logical_y_from_local_position(terrain_position)
	)


func _find_table_scene() -> Node3D:
	var scope := get_parent()
	while scope != null:
		if scope is Node3D and scope.has_node("BoardSurface"):
			return scope as Node3D
		scope = scope.get_parent()
	return null


func _ensure_renderer() -> void:
	_renderer = get_node_or_null(NodePath(String(RENDERER_NAME))) as MultiMeshInstance3D
	if _renderer != null:
		return
	_renderer = MultiMeshInstance3D.new()
	_renderer.name = RENDERER_NAME
	_renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_renderer.extra_cull_margin = 8.0
	add_child(_renderer)


func _ensure_brush_preview() -> void:
	_brush_preview = get_node_or_null(NodePath(String(PREVIEW_NAME))) as MeshInstance3D
	if _brush_preview != null:
		return
	_brush_preview = MeshInstance3D.new()
	_brush_preview.name = PREVIEW_NAME
	_brush_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brush_preview.visible = false
	add_child(_brush_preview)


func _generate_default_distribution(
	requested_density := -1.0,
	requested_spacing := -1.0,
	requested_minimum_scale := -1.0,
	requested_maximum_scale := -1.0,
	surface_sampler: Callable = Callable()
) -> Dictionary:
	var result := _empty_distribution()
	var positions: PackedVector3Array = result["positions"]
	var rotations: PackedFloat32Array = result["rotations"]
	var scales: PackedFloat32Array = result["scales"]
	var phases: PackedFloat32Array = result["phases"]
	var tints: PackedFloat32Array = result["tints"]
	var random := RandomNumberGenerator.new()
	random.seed = distribution_seed
	var active_density := fill_density if requested_density < 0.0 else requested_density
	var active_spacing := minimum_spacing if requested_spacing < 0.0 else requested_spacing
	var active_minimum_scale := (
		minimum_scale if requested_minimum_scale < 0.0 else requested_minimum_scale
	)
	var active_maximum_scale := (
		maximum_scale if requested_maximum_scale < 0.0 else requested_maximum_scale
	)
	var spacing := maxf(
		sqrt(1.0 / maxf(active_density, 0.0001)),
		maxf(active_spacing, 0.0)
	)
	var columns := maxi(1, int(ceil(fill_extents.x / spacing)))
	var rows := maxi(1, int(ceil(fill_extents.y / spacing)))
	var left := -fill_extents.x * 0.5
	var top := -fill_extents.y * 0.5
	for row in rows:
		for column in columns:
			var local_position := Vector3(
				left + (float(column) + 0.5) * spacing,
				0.0,
				top + (float(row) + 0.5) * spacing
			)
			local_position.x += random.randf_range(-spacing * 0.38, spacing * 0.38)
			local_position.z += random.randf_range(-spacing * 0.38, spacing * 0.38)
			if surface_sampler.is_valid():
				var sampled_surface: Variant = surface_sampler.call(
					to_global(local_position)
				)
				if not sampled_surface is Vector3:
					continue
				local_position = to_local(sampled_surface as Vector3)
			var cluster_value := _cluster_value(local_position)
			if cluster_value < cluster_threshold:
				continue
			if random.randf() > smoothstep(cluster_threshold, 1.0, cluster_value):
				continue
			if not _has_spacing(positions, local_position, active_spacing):
				continue
			_append_instance(
				positions,
				rotations,
				scales,
				phases,
				tints,
				local_position,
				random,
				active_minimum_scale,
				active_maximum_scale
			)
	return result


func _paint_local(
	local_center: Vector3,
	radius: float,
	density: float,
	minimum_instance_spacing: float,
	minimum_instance_scale: float,
	maximum_instance_scale: float,
	surface_sampler: Callable = Callable()
) -> void:
	if density <= 0.0:
		return
	var random := RandomNumberGenerator.new()
	var center_key := (
		int(round(local_center.x * 100.0)) * 73856093
		^ int(round(local_center.z * 100.0)) * 19349663
		^ grass_positions.size() * 83492791
		^ distribution_seed
	)
	random.seed = center_key
	var sample_count := maxi(1, int(ceil(PI * radius * radius * density)))
	for _sample in sample_count:
		var angle := random.randf_range(0.0, TAU)
		var distance := sqrt(random.randf()) * radius
		var candidate := local_center + Vector3(
			cos(angle) * distance,
			0.0,
			sin(angle) * distance
		)
		if surface_sampler.is_valid():
			var sampled_surface: Variant = surface_sampler.call(to_global(candidate))
			if not sampled_surface is Vector3:
				continue
			candidate = to_local(sampled_surface as Vector3)
		if not _has_spacing(
			grass_positions,
			candidate,
			minimum_instance_spacing
		):
			continue
		_append_instance(
			grass_positions,
			grass_rotations,
			grass_scales,
			grass_phases,
			grass_tints,
			candidate,
			random,
			minimum_instance_scale,
			maximum_instance_scale
		)


func _erase_local(local_center: Vector3, radius: float) -> void:
	var kept := _empty_distribution()
	var kept_positions: PackedVector3Array = kept["positions"]
	var kept_rotations: PackedFloat32Array = kept["rotations"]
	var kept_scales: PackedFloat32Array = kept["scales"]
	var kept_phases: PackedFloat32Array = kept["phases"]
	var kept_tints: PackedFloat32Array = kept["tints"]
	for index in grass_positions.size():
		var delta := grass_positions[index] - local_center
		if Vector2(delta.x, delta.z).length() <= radius:
			continue
		kept_positions.append(grass_positions[index])
		kept_rotations.append(_value_or_default(grass_rotations, index, 0.0))
		kept_scales.append(_value_or_default(grass_scales, index, 1.0))
		kept_phases.append(_value_or_default(grass_phases, index, 0.0))
		kept_tints.append(_value_or_default(grass_tints, index, 0.5))
	grass_positions = kept_positions
	grass_rotations = kept_rotations
	grass_scales = kept_scales
	grass_phases = kept_phases
	grass_tints = kept_tints


func _append_instance(
	positions: PackedVector3Array,
	rotations: PackedFloat32Array,
	scales: PackedFloat32Array,
	phases: PackedFloat32Array,
	tints: PackedFloat32Array,
	position: Vector3,
	random: RandomNumberGenerator,
	minimum_instance_scale: float,
	maximum_instance_scale: float
) -> void:
	var scale_low := maxf(0.01, minf(minimum_instance_scale, maximum_instance_scale))
	var scale_high := maxf(scale_low, maxf(minimum_instance_scale, maximum_instance_scale))
	positions.append(position)
	rotations.append(
		deg_to_rad(
			random.randf_range(-maximum_y_rotation_degrees, maximum_y_rotation_degrees)
		)
	)
	scales.append(random.randf_range(scale_low, scale_high))
	phases.append(random.randf())
	tints.append(random.randf())


func _has_spacing(
	existing_positions: PackedVector3Array,
	candidate: Vector3,
	requested_spacing: float
) -> bool:
	var spacing := maxf(requested_spacing, 0.0)
	if spacing <= 0.0:
		return true
	var spacing_squared := spacing * spacing
	for existing in existing_positions:
		var delta := existing - candidate
		if delta.x * delta.x + delta.z * delta.z < spacing_squared:
			return false
	return true


func _cluster_value(local_position: Vector3) -> float:
	var first_wave := sin(local_position.x * 0.31 + float(distribution_seed) * 0.001)
	var second_wave := sin(local_position.z * 0.27 - float(distribution_seed) * 0.0007)
	var diagonal_wave := sin((local_position.x + local_position.z) * 0.17 + 1.7)
	return clampf((first_wave + second_wave + diagonal_wave + 3.0) / 6.0, 0.0, 1.0)


func _region_hash(position: Vector2) -> float:
	return fposmod(
		sin(position.dot(Vector2(127.1, 311.7))) * 43758.5453123,
		1.0
	)


func _region_noise(position: Vector2) -> float:
	var lattice := Vector2(floor(position.x), floor(position.y))
	var local := position - lattice
	local = local * local * (Vector2.ONE * 3.0 - local * 2.0)
	var lower_left := _region_hash(lattice)
	var lower_right := _region_hash(lattice + Vector2(1.0, 0.0))
	var upper_left := _region_hash(lattice + Vector2(0.0, 1.0))
	var upper_right := _region_hash(lattice + Vector2(1.0, 1.0))
	return lerpf(
		lerpf(lower_left, lower_right, local.x),
		lerpf(upper_left, upper_right, local.x),
		local.y
	)


func _landscape_region(world_position: Vector2) -> float:
	var field_position := world_position / maxf(region_size_meters, 0.1)
	var broad_region := _region_noise(
		field_position * 0.72 + Vector2(2.7, 8.1)
	)
	var secondary_region := _region_noise(
		field_position * 1.43 + Vector2(11.6, 3.4)
	)
	return clampf(broad_region * 0.72 + secondary_region * 0.28, 0.0, 1.0)


func _empty_distribution(suppress_default := false) -> Dictionary:
	return {
		"positions": PackedVector3Array(),
		"rotations": PackedFloat32Array(),
		"scales": PackedFloat32Array(),
		"phases": PackedFloat32Array(),
		"tints": PackedFloat32Array(),
		"suppress_auto_fill": suppress_default,
	}


func _value_or_default(values: PackedFloat32Array, index: int, fallback: float) -> float:
	if index >= 0 and index < values.size():
		return values[index]
	return fallback
