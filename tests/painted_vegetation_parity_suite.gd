extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var controller := TablePaintedVegetation3D.new()
	root.add_child(controller)
	controller.set_process(false)
	_check("editable controller keeps the original event capacity", controller._events.size() == 32 and controller._segments.size() == 32)
	_check("speed response increases", TablePaintedVegetation3D.motion_intensity(60.0) < TablePaintedVegetation3D.motion_intensity(600.0))
	_check("slow sweep remains subtle", TablePaintedVegetation3D.motion_intensity(60.0) < 0.05)
	_check("fast sweep remains capped", TablePaintedVegetation3D.motion_intensity(1500.0) == 1.0 and TablePaintedVegetation3D.motion_intensity(9000.0) == 1.0)
	controller.set_pointer(Vector2(600, -1400), Vector2(1500, 0), false, Vector2(-600, -1400))
	_check("fast pointer motion stores the complete swept path", controller._segments[0] == Vector4(-6, -14, 6, -14))
	_check("fast pointer motion stores full strength", controller._events[0].w == 1.0)
	controller.elapsed += 0.01
	controller.set_pointer(Vector2(640, -1400), Vector2(1500, 0), false, Vector2(600, -1400))
	_check("nearby replay is blocked during the minimum interval", controller._next_event == 1 and controller._events[0].z == 0.0)
	_check("spring starts at rest", TablePaintedVegetation3D.interaction_response(0.0) == 0.0)
	_check("spring bends after the pointer leaves", TablePaintedVegetation3D.interaction_response(0.12) > 0.5)
	_check("spring returns through rest", TablePaintedVegetation3D.interaction_response(0.35) < -0.1)
	_check("spring settles without abrupt cutoff", absf(TablePaintedVegetation3D.interaction_response(0.8)) < 0.03 and absf(TablePaintedVegetation3D.interaction_response(0.8)) > 0.01)
	var cursor := controller._next_event
	controller.elapsed = 0.25
	controller.set_pointer(Vector2(600, -1400), Vector2(60, 0), false, Vector2(599, -1400))
	_check("slow replay stays blocked before 0.35 seconds", controller._next_event == cursor)
	controller.set_pointer(Vector2(1600, -1400), Vector2(1500, 0), false, Vector2(1200, -1400))
	_check("a separate pointer region still responds during cooldown", controller._next_event != cursor)
	cursor = controller._next_event
	controller.elapsed = 0.351
	controller.set_pointer(Vector2(590, -1400), Vector2(60, 0), false, Vector2(589, -1400))
	_check("the same region can replay after 0.35 seconds", controller._next_event != cursor)

	var patch := GrassPatch3D.new()
	patch.auto_fill_on_empty = false
	patch.suppress_auto_fill = true
	patch.static_texture = load("res://assets/art/forest_rebuild/editable/broadleaf.png")
	patch.quad_size = Vector2(1.85, 1.20)
	patch.player_bend_strength = 0.30
	patch.disturbance_radius = 1.30
	var logical := Vector2(2.5, -1850.0)
	patch.grass_positions = PackedVector3Array([FoldedTerrain.world_position(logical)])
	patch.grass_rotations = PackedFloat32Array([0.0])
	patch.grass_scales = PackedFloat32Array([1.15])
	patch.grass_phases = PackedFloat32Array([0.2])
	patch.grass_tints = PackedFloat32Array([0.6])
	controller.add_child(patch)
	var camera_basis := Basis.from_euler(Vector3(-1.1, 0.15, 0.0))
	controller.set_camera_basis(camera_basis)
	controller.set_pointer_light(Vector3(1.0, 2.0, 3.0), 4.5, 1.2, Color("ffd7a0"), true)
	controller._apply_runtime_state()
	var renderer := patch.get_node("__GrassRenderer") as MultiMeshInstance3D
	var multimesh := renderer.multimesh
	var mesh := multimesh.mesh as ArrayMesh
	_check("each editable plant uses 45 vertices for local light falloff", mesh != null and mesh.surface_get_array_len(0) == 45)
	var patch_source := FileAccess.get_file_as_string("res://addons/grass_painter/grass_patch_3d.gd")
	_check("plant roots are not shifted by half their visual height", not patch_source.contains("origin.y += quad_size.y"))
	_check("interaction anchor retains unfolded terrain coordinates", is_equal_approx(patch._logical_y_from_local_position(patch.grass_positions[0]), logical.y / 100.0))
	_check("shader custom data retains the painted instance scale", patch_source.contains("logical_y,\n\t\t\t\tinstance_scale"))
	var material := mesh.surface_get_material(0) as ShaderMaterial
	var shader_events: PackedVector4Array = material.get_shader_parameter("events")
	var shader_segments: PackedVector4Array = material.get_shader_parameter("segments")
	var shader_up: Vector3 = material.get_shader_parameter("facing_up")
	_check("swept interaction events reach every painted layer", shader_events.size() == 32 and shader_segments.size() == 32 and shader_segments[0] == controller._segments[0])
	_check("camera basis reaches every painted layer", shader_up.is_equal_approx(camera_basis.orthonormalized().y))
	_check("painted layer keeps original interaction radius and strength", is_equal_approx(float(material.get_shader_parameter("disturbance_radius")), 1.30) and is_equal_approx(float(material.get_shader_parameter("interaction_strength")), 0.30))
	_check("painted layer receives the cursor light without card-wide toggles", material.get_shader_parameter("pointer_light_enabled") == true and (material.get_shader_parameter("pointer_light_position") as Vector3).is_equal_approx(Vector3(1.0, 2.0, 3.0)))
	var shader_source := FileAccess.get_file_as_string("res://addons/grass_painter/grass_material.gdshader")
	_check("shader retains opaque cutout lighting instead of blended cards", shader_source.contains("depth_draw_opaque") and shader_source.contains("discard") and not shader_source.contains("ALPHA ="))
	_check("shader applies swept segments and gradual radial falloff", shader_source.contains("segments[index]") and shader_source.contains("smoothstep(disturbance_radius*0.28"))
	_check("shader computes cursor light falloff per visible plant pixel", shader_source.contains("billboard_world_position") and shader_source.contains("pointer_distance") and shader_source.contains("smoothstep(pointer_light_range*0.12"))

	controller.free()
	print("PAINTED_VEGETATION_PARITY_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label)
