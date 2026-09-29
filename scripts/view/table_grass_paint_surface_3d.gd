@tool
class_name TableGrassPaintSurface3D
extends Node3D

@export var exclude_board := true
@export_range(0.0, 5.0, 0.05) var board_clearance_meters := 1.35
@export var maximum_front_meters := 70.0


func grass_paint_raycast(viewport_camera: Camera3D, mouse_position: Vector2) -> Variant:
	if viewport_camera == null:
		return null
	var inverse := global_transform.affine_inverse()
	var logical := FoldedTerrain.from_ray(
		inverse * viewport_camera.project_ray_origin(mouse_position),
		(inverse.basis * viewport_camera.project_ray_normal(mouse_position)).normalized()
	)
	var local_surface: Variant = _surface_for_logical(logical)
	return to_global(local_surface) if local_surface is Vector3 else null


func grass_paint_sample(world_probe: Vector3) -> Variant:
	var local_surface: Variant = _surface_for_logical(_logical_from_world_probe(to_local(world_probe)))
	return to_global(local_surface) if local_surface is Vector3 else null


func _surface_for_logical(logical: Vector2) -> Variant:
	if not logical.is_finite():
		return null
	if absf(logical.x) > FoldedTerrain.TERRAIN_WIDTH:
		return null
	if logical.y < FoldedTerrain.terminal_z(logical.x) or logical.y > maximum_front_meters * 100.0:
		return null
	if exclude_board and TableState.WORLD_BOUNDS.grow(board_clearance_meters * 100.0).has_point(logical):
		return null
	return FoldedTerrain.world_position(logical)


func _logical_from_world_probe(world_probe: Vector3) -> Vector2:
	var hinge := FoldedTerrain.hinge_z()
	var bevel_end_z := hinge - cos(FoldedTerrain.BEVEL_ANGLE) * FoldedTerrain.BEVEL_LENGTH
	var depth := 0.0
	if world_probe.z >= hinge:
		return Vector2(world_probe.x, world_probe.z) * 100.0
	if world_probe.z >= bevel_end_z:
		depth = (hinge - world_probe.z) / cos(FoldedTerrain.BEVEL_ANGLE)
	else:
		depth = FoldedTerrain.BEVEL_LENGTH + (bevel_end_z - world_probe.z) / cos(FoldedTerrain.FOLD_ANGLE)
	return Vector2(world_probe.x * 100.0, (hinge - depth) * 100.0)
