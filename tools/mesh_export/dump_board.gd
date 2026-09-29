extends SceneTree

func _initialize() -> void:
	var mesh := FoldedTerrain.make_mesh(null,null)
	var surfaces: Array = []
	for index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(index)
		var vertices: Array = []
		var uv: Array = []
		for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			vertices.append([p.x,p.y,p.z])
		for p: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
			uv.append([p.x,p.y])
		surfaces.append({"name":"Board" if index==1 else "Terrain","vertices":vertices,"uv":uv})
	var out := FileAccess.open("res://outputs/maya-board-mesh/source-mesh.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"surfaces":surfaces},"\t"))
	out.close()
	print("BOARD_MESH_EXPORTED")
	quit()
