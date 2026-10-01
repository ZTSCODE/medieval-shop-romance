extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/table_environment_editable.tscn") as PackedScene
	_check("editable environment scene loads", packed != null)
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	var environment := scene.get_node_or_null("EnvironmentRoot") as Node3D
	var painted := scene.get_node_or_null("EnvironmentRoot/EditableVegetation") as TablePaintedVegetation3D
	var landmarks := scene.get_node_or_null("EnvironmentRoot/EditableLandmarks") as Node3D
	var distant_landmarks := scene.get_node_or_null("EnvironmentRoot/EditableDistantLandmarks") as Node3D
	var surface := scene.get_node_or_null("EnvironmentRoot/GrassPaintSurface") as TableGrassPaintSurface3D
	_check("board and environment are editor nodes", scene.has_node("BoardSurface") and environment != null)
	var manual_plants := scene.get_node_or_null("EnvironmentRoot/EditableVegetation/EditableManualPlants") as Node3D
	var direct_paint_layers := 0
	for child: Node in painted.get_children():
		if child is GrassPatch3D:
			direct_paint_layers += 1
	_check("near and distant paint layers are saved in scene", painted != null and direct_paint_layers == 8)
	_check("manual plant container is saved in scene", manual_plants != null)
	_check("converted near and far distribution is saved", painted != null and painted.painted_instance_count() > 1000)
	_check("near landmarks remain independently editable", landmarks != null and landmarks.get_child_count() == 16 and manual_plants.get_child_count() == 2)
	_check("distant landmarks and town are independent nodes",distant_landmarks != null and distant_landmarks.get_child_count() >= 24 and distant_landmarks.has_node("CastleTown"))
	_check("editable scene root stands upright",is_equal_approx(scene.rotation_degrees.x,90.0))
	var far_background := scene.get_node_or_null("DistantSkyWorldPlane") as MeshInstance3D
	var far_scale := far_background.transform.basis.get_scale() if far_background != null else Vector3.ZERO
	_check("distant backdrop keeps uniform image scale",far_background != null and absf(far_scale.x-far_scale.y)<0.001 and absf(far_scale.y-far_scale.z)<0.001)
	_check("distant backdrop has enough overscan for wide views",far_scale.x>=0.99)
	_check("paint surface rejects board center", surface != null and surface.grass_paint_sample(scene.to_global(Vector3.ZERO)) == null)
	var outside_logical := Vector2(TableState.WORLD_BOUNDS.position.x - 250.0, TableState.WORLD_BOUNDS.get_center().y)
	var outside_global := scene.to_global(FoldedTerrain.world_position(outside_logical))
	var sampled: Variant = surface.grass_paint_sample(outside_global)
	_check("paint surface accepts terrain outside board", sampled is Vector3 and (sampled as Vector3).distance_to(outside_global) < 0.01)
	var brush_patch := GrassPatch3D.new()
	brush_patch.auto_fill_on_empty = false
	brush_patch.suppress_auto_fill = true
	brush_patch.static_texture = load("res://assets/art/forest_rebuild/editable/broadleaf.png")
	painted.add_child(brush_patch)
	var resolver := GrassPaintSurfaceResolver.new()
	var sampler := Callable(resolver,"sample_surface").bind(surface)
	brush_patch.paint_stamp(outside_global,0.8,8.0,0.05,0.8,1.1,false,sampler)
	_check("brush writes editable instances on folded terrain",brush_patch.grass_positions.size()>0)
	var before_blocked_paint := brush_patch.grass_positions.size()
	brush_patch.paint_stamp(scene.to_global(FoldedTerrain.world_position(TableState.WORLD_BOUNDS.get_center())),0.8,8.0,0.05,0.8,1.1,false,sampler)
	_check("brush does not paint across board",brush_patch.grass_positions.size()==before_blocked_paint)
	brush_patch.queue_free()
	var stage := TableStage3D.new()
	root.add_child(stage)
	stage.configure(TableState.WORLD_BOUNDS, TableCamera.new())
	_check("runtime stage instantiates editable scene", stage.scene_root.scene_file_path == "res://scenes/world/table_environment_editable.tscn")
	_check("runtime exposes painted vegetation controller", stage.painted_vegetation is TablePaintedVegetation3D)
	var plugin_script := load("res://addons/grass_painter/plugin.gd") as Script
	_check("grass painter plugin parses", plugin_script != null and FileAccess.file_exists("res://addons/grass_painter/plugin.cfg"))
	var grass_shader := FileAccess.get_file_as_string("res://addons/grass_painter/grass_material.gdshader")
	_check("painted vegetation shader billboards to camera",grass_shader.contains("MODELVIEW_NORMAL_MATRIX") and grass_shader.contains("facing_right"))
	var first_patch := painted.get_child(0) as GrassPatch3D
	var first_renderer := first_patch.get_node("__GrassRenderer") as MultiMeshInstance3D
	var first_mesh := first_renderer.multimesh.mesh as ArrayMesh
	_check("painted plants retain the 5 by 9 subdivided light mesh",first_mesh != null and first_mesh.surface_get_array_len(0) == 45)
	var unfolded_mapping_ok := true
	for layer: Node in painted.get_children():
		if not layer is GrassPatch3D:
			continue
		var grass_layer := layer as GrassPatch3D
		for position: Vector3 in grass_layer.grass_positions:
			var logical_y := grass_layer._logical_y_from_local_position(position)
			var rebuilt := FoldedTerrain.world_position(Vector2(position.x * 100.0, logical_y * 100.0))
			if rebuilt.distance_to(position) > 0.002:
				unfolded_mapping_ok = false
				break
		if not unfolded_mapping_ok:
			break
	_check("all editable roots map back to exact unfolded pointer coordinates", unfolded_mapping_ok)
	_check("editable pointer replay interval matches the accepted meadow feel", is_equal_approx(painted.interaction_retrigger_interval, 0.35))
	var enabled_plugins: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	_check("grass painter plugin is enabled", "res://addons/grass_painter/plugin.cfg" in enabled_plugins)
	var board_surface := scene.get_node("BoardSurface") as MeshInstance3D
	var board_slab := scene.get_node("BoardThickness") as MeshInstance3D
	var meadow_material := board_surface.get_surface_override_material(0) as ShaderMaterial
	var board_material := board_surface.get_surface_override_material(1) as ShaderMaterial
	_check("plain support slab does not cover the sculpted painted surface", not board_slab.visible)
	_check("board uses the retained wood texture and meadow remains unchanged", (board_material.get_shader_parameter("grain") as Texture2D).resource_path.ends_with("board-wood-retained.png") and (meadow_material.get_shader_parameter("grain") as Texture2D).resource_path.ends_with("forest-floor-tile.png"))
	_check("board texture is no longer suppressed by a gray blue tint", (board_material.get_shader_parameter("surface_tint") as Color).is_equal_approx(Color.WHITE))
	print("EDITABLE_ENVIRONMENT_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label)
