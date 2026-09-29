@tool
class_name TableManualPlant3D
extends Node3D

const GRASS_PATCH_SCRIPT := preload("res://addons/grass_painter/grass_patch_3d.gd")

@export_category("Plant Art")
@export var plant_texture: Texture2D:
	set(value):
		plant_texture = value
		_queue_sync()
@export_range(0.1, 12.0, 0.05) var plant_height_meters := 1.8:
	set(value):
		plant_height_meters = maxf(value, 0.1)
		_queue_sync()
@export var color_multiplier := Color(0.86, 0.86, 0.86, 1.0):
	set(value):
		color_multiplier = value
		_queue_sync()
@export var flip_horizontal := false:
	set(value):
		flip_horizontal = value
		_queue_sync()
@export_range(0.0, 1.0, 0.01) var alpha_scissor := 0.18:
	set(value):
		alpha_scissor = clampf(value, 0.0, 1.0)
		_queue_sync()

@export_category("Motion")
@export var wind_enabled := true:
	set(value):
		wind_enabled = value
		_queue_sync()
@export_range(0.0, 0.4, 0.005) var wind_strength := 0.105:
	set(value):
		wind_strength = maxf(value, 0.0)
		_queue_sync()
@export_range(0.0, 4.0, 0.05) var wind_speed := 1.05:
	set(value):
		wind_speed = maxf(value, 0.0)
		_queue_sync()
@export var interaction_enabled := true:
	set(value):
		interaction_enabled = value
		_queue_sync()
@export_range(0.0, 0.5, 0.01) var interaction_strength := 0.30:
	set(value):
		interaction_strength = maxf(value, 0.0)
		_queue_sync()
@export_range(0.1, 4.0, 0.05) var interaction_radius := 1.30:
	set(value):
		interaction_radius = maxf(value, 0.1)
		_queue_sync()
@export var variation_seed := 1:
	set(value):
		variation_seed = value
		_queue_sync()

@export_category("Placement")
@export var snap_to_folded_surface := true
@export_range(-1.0, 1.0, 0.005) var surface_offset := 0.025:
	set(value):
		surface_offset = value
		_queue_surface_snap()

var _patch: GrassPatch3D
var _sync_queued := false
var _snap_queued := false
var _snapping := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_notify_transform(true)
	_ensure_patch()
	_sync_patch()
	_queue_surface_snap()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_queue_surface_snap()


func _ensure_patch() -> void:
	_patch = get_node_or_null("PlantRenderer") as GrassPatch3D
	if _patch != null:
		return
	_patch = GRASS_PATCH_SCRIPT.new() as GrassPatch3D
	_patch.name = "PlantRenderer"
	_patch.auto_fill_on_empty = false
	_patch.suppress_auto_fill = true
	_patch.grass_positions = PackedVector3Array([Vector3.ZERO])
	_patch.grass_rotations = PackedFloat32Array([0.0])
	_patch.grass_scales = PackedFloat32Array([1.0])
	_patch.grass_phases = PackedFloat32Array([0.5])
	_patch.grass_tints = PackedFloat32Array([0.5])
	add_child(_patch, false, Node.INTERNAL_MODE_FRONT)


func _sync_patch() -> void:
	_sync_queued = false
	_ensure_patch()
	_patch.static_texture = plant_texture
	var aspect := 1.0
	if plant_texture != null and plant_texture.get_height() > 0:
		aspect = float(plant_texture.get_width()) / float(plant_texture.get_height())
	_patch.quad_size = Vector2(plant_height_meters * aspect, plant_height_meters)
	_patch.flip_horizontal = flip_horizontal
	_patch.alpha_scissor = alpha_scissor
	_patch.color_saturation = 1.0
	_patch.natural_color_multiplier = color_multiplier
	_patch.color_variation_strength = 0.045
	_patch.region_color_strength = 0.0
	_patch.outline_strength = 0.0
	_patch.wind_enabled = wind_enabled
	_patch.wind_strength = wind_strength
	_patch.wind_speed = wind_speed
	_patch.player_interaction_enabled = interaction_enabled
	_patch.player_bend_strength = interaction_strength
	_patch.disturbance_radius = interaction_radius
	_patch.minimum_scale = 1.0
	_patch.maximum_scale = 1.0
	var phase := fposmod(sin(float(variation_seed) * 12.9898) * 43758.5453, 1.0)
	_patch.grass_positions = PackedVector3Array([Vector3.ZERO])
	_patch.grass_rotations = PackedFloat32Array([0.0])
	_patch.grass_scales = PackedFloat32Array([1.0])
	_patch.grass_phases = PackedFloat32Array([phase])
	_patch.grass_tints = PackedFloat32Array([fposmod(phase * 7.13, 1.0)])
	_patch.rebuild()


func _queue_sync() -> void:
	if not is_inside_tree() or _sync_queued:
		return
	_sync_queued = true
	call_deferred("_sync_patch")


func _queue_surface_snap() -> void:
	if not is_inside_tree() or not snap_to_folded_surface or _snap_queued or _snapping:
		return
	_snap_queued = true
	call_deferred("_snap_to_surface")


func _snap_to_surface() -> void:
	_snap_queued = false
	if not snap_to_folded_surface or _snapping:
		return
	var table_scene := _find_table_scene()
	var spatial_parent := get_parent_node_3d()
	if table_scene == null or spatial_parent == null:
		return
	var terrain_position := table_scene.to_local(global_position)
	var logical_y := _logical_y_from_folded_position(terrain_position)
	var snapped := FoldedTerrain.world_position(
		Vector2(terrain_position.x, logical_y) * 100.0
	)
	snapped.y += surface_offset
	var target_position := spatial_parent.to_local(table_scene.to_global(snapped))
	if position.distance_to(target_position) <= 0.0001:
		return
	_snapping = true
	position = target_position
	_snapping = false


func _logical_y_from_folded_position(position_on_surface: Vector3) -> float:
	var hinge := FoldedTerrain.hinge_z()
	if position_on_surface.z >= hinge - 0.0001:
		return position_on_surface.z
	var bevel_end := hinge - cos(FoldedTerrain.BEVEL_ANGLE) * FoldedTerrain.BEVEL_LENGTH
	if position_on_surface.z >= bevel_end - 0.0001:
		return hinge - (hinge - position_on_surface.z) / cos(FoldedTerrain.BEVEL_ANGLE)
	return hinge - FoldedTerrain.BEVEL_LENGTH - (bevel_end - position_on_surface.z) / cos(FoldedTerrain.FOLD_ANGLE)


func _find_table_scene() -> Node3D:
	var scope := get_parent()
	while scope != null:
		if scope is Node3D and scope.has_node("BoardSurface"):
			return scope as Node3D
		scope = scope.get_parent()
	return null
