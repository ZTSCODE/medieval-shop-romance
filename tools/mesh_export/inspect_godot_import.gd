extends SceneTree


func _initialize() -> void:
	var mesh := load("res://assets/models/terrain/board-terrain-user-v1.res") as ArrayMesh
	if mesh == null:
		push_error("User terrain resource did not load")
		quit(2)
		return
	print("USER_TERRAIN_IMPORT aabb=", mesh.get_aabb(), " surfaces=", mesh.get_surface_count())
	quit()
