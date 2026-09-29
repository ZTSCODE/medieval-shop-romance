extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var environment := (load("res://scenes/world/table_environment_editable.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(environment)
	var vegetation := environment.get_node("EnvironmentRoot/EditableVegetation") as TablePaintedVegetation3D
	var manual_root := environment.get_node("EnvironmentRoot/EditableVegetation/EditableManualPlants") as Node3D
	var before_count := vegetation.painted_instance_count()
	var manual := (load("res://scenes/world/manual_plant_3d.tscn") as PackedScene).instantiate() as TableManualPlant3D
	manual_root.add_child(manual)
	manual.position = FoldedTerrain.world_position(Vector2(-1450.0, 900.0)) + Vector3(0.0, 0.8, 0.0)
	manual._snap_to_surface()
	var patch := manual.get_node("PlantRenderer") as GrassPatch3D
	_check("manual plant template creates one editable renderer", patch != null and patch.grass_positions.size() == 1 and vegetation.painted_instance_count() == before_count + 1)
	_check("manual plant snaps its root onto the folded surface", absf(environment.to_local(manual.global_position).y - 0.025) < 0.001)
	var expected_anchor := Vector2(-14.5, 9.0)
	_check("manual plant keeps unfolded coordinates for interaction", patch._unfolded_anchor_from_local_position(Vector3.ZERO).distance_to(expected_anchor) < 0.01)
	_check("manual plant inherits automatic wind and pointer interaction", patch.wind_enabled and patch.player_interaction_enabled and is_equal_approx(patch.wind_strength, 0.105) and is_equal_approx(patch.player_bend_strength, 0.30))
	vegetation.elapsed = 0.0
	vegetation._apply_runtime_state()
	vegetation._process(0.5)
	var material := patch._material
	var elapsed_value: Variant = material.get_shader_parameter("elapsed")
	var wind_value: Variant = material.get_shader_parameter("wind_strength")
	_check("automatic wind clock advances without a pointer event", elapsed_value is float and wind_value is float and is_equal_approx(elapsed_value, 0.5) and is_equal_approx(wind_value, 0.105))
	vegetation.set_pointer(Vector2(-1450.0, 900.0), Vector2(800.0, 0.0), false, Vector2(-1500.0, 900.0))
	var segments: PackedVector4Array = material.get_shader_parameter("segments")
	_check("manual plant receives the same swept pointer interaction", segments.size() == 32 and segments[0] == Vector4(-15.0, 9.0, -14.5, 9.0))
	manual.plant_texture = load("res://assets/art/forest_rebuild/editable/whiteflowers.png")
	manual.plant_height_meters = 2.4
	manual._sync_patch()
	var texture := manual.plant_texture
	var expected_width := 2.4 * float(texture.get_width()) / float(texture.get_height())
	_check("replacing the texture preserves aspect ratio and requested height", patch.static_texture == texture and is_equal_approx(patch.quad_size.x, expected_width) and is_equal_approx(patch.quad_size.y, 2.4))
	var shader_source := FileAccess.get_file_as_string("res://addons/grass_painter/grass_material.gdshader")
	_check("wind is evaluated independently from pointer interaction", shader_source.contains("float wind = wind_enabled ?") and shader_source.contains("wind_lateral+push"))
	print("MANUAL_PLANT_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label)
