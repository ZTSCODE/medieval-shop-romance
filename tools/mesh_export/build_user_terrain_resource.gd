extends SceneTree


func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://assets/models/terrain/board-terrain-user-v1.json")
	var data: Dictionary = JSON.parse_string(source)
	if data.is_empty():
		push_error("User terrain JSON is missing or invalid")
		quit(2)
		return
	var mesh := ArrayMesh.new()
	for surface_key in ["0", "1"]:
		var surface: Dictionary = data.surfaces[surface_key]
		var build := SurfaceTool.new()
		build.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in surface.vertices.size():
			var point: Array = surface.vertices[index]
			var normal: Array = surface.normals[index]
			var uv: Array = surface.uv[index]
			build.set_normal(Vector3(normal[0], normal[1], normal[2]))
			build.set_uv(Vector2(uv[0], uv[1]))
			build.add_vertex(Vector3(point[0], point[1], point[2]))
		build.index()
		build.commit(mesh)
	mesh.set_meta("source_fbx", "outputs/maya-board-mesh/mesh.fbx")
	mesh.set_meta("source_scale_recovery", 100.0)
	var error := ResourceSaver.save(mesh, "res://assets/models/terrain/board-terrain-user-v1.res")
	if error != OK:
		push_error("Could not save user terrain resource: %s" % error)
		quit(3)
		return
	print("USER_TERRAIN_RESOURCE_SAVED aabb=", mesh.get_aabb(), " surfaces=", mesh.get_surface_count())
	quit()
