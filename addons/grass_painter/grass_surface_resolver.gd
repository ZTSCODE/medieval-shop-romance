@tool
class_name GrassPaintSurfaceResolver
extends RefCounted


func find_related(patch: GrassPatch3D) -> Node:
	if not is_instance_valid(patch):
		return null
	var scope: Node = patch.get_parent()
	while scope != null:
		var provider := _find_below(scope, patch)
		if provider != null:
			return provider
		scope = scope.get_parent()
	return null


func raycast_surface(viewport_camera: Camera3D, mouse_position: Vector2, provider: Node) -> Variant:
	if viewport_camera == null or provider == null or not provider.has_method("grass_paint_raycast"):
		return null
	return provider.call("grass_paint_raycast", viewport_camera, mouse_position)


func sample_surface(world_probe: Vector3, provider: Node) -> Variant:
	if provider == null or not provider.has_method("grass_paint_sample"):
		return null
	return provider.call("grass_paint_sample", world_probe)


func _find_below(node: Node, excluded: Node) -> Node:
	if node != excluded and node.has_method("grass_paint_raycast") and node.has_method("grass_paint_sample"):
		return node
	for child: Node in node.get_children():
		if child == excluded:
			continue
		var nested := _find_below(child, excluded)
		if nested != null:
			return nested
	return null
