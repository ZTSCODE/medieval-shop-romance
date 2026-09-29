extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var meadow := TableMeadow3D.new()
	meadow.meadow_width = 100.0
	root.add_child(meadow)
	meadow.set_process(false)
	_check("speed response increases", TableMeadow3D.motion_intensity(60.0) < TableMeadow3D.motion_intensity(600.0))
	_check("slow sweep remains subtle", TableMeadow3D.motion_intensity(60.0) < 0.05)
	_check("fast sweep is capped", TableMeadow3D.motion_intensity(1500.0) == 1.0 and TableMeadow3D.motion_intensity(9000.0) == 1.0)
	meadow.set_pointer(Vector2(600, -1400), Vector2(1500, 0), false, Vector2(-600, -1400))
	_check("first fast event covers whole sweep", meadow._segments[0] == Vector4(-6, -14, 6, -14))
	_check("first fast event has full strength", meadow._events[0].w == 1.0)
	meadow.elapsed += 0.01
	meadow.set_pointer(Vector2(640, -1400), Vector2(1500, 0), false, Vector2(600, -1400))
	_check("nearby motion during cooldown does not mutate animation", meadow._segments[0] == Vector4(-6, -14, 6, -14) and meadow._next_event == 1)
	_check("merged sweeps never restart spring age", meadow._events[0].z == 0.0)
	_check("spring starts at rest", TableMeadow3D.interaction_response(0.0) == 0.0)
	_check("spring bends after pointer leaves", TableMeadow3D.interaction_response(0.12) > 0.5)
	_check("spring returns past rest", TableMeadow3D.interaction_response(0.35) < -0.1)
	_check("spring settles gradually", absf(TableMeadow3D.interaction_response(0.8)) < 0.03 and absf(TableMeadow3D.interaction_response(0.8)) > 0.01)
	meadow.elapsed += 0.05
	meadow.set_pointer(Vector2(650, -1400), Vector2(60, 0), false, Vector2(640, -1400))
	_check("slow event cannot replace strongest history", meadow._events[0].w > meadow._events[1].w)
	var outside := true
	for patch: Dictionary in meadow.patches:
		outside = outside and not meadow._board.has_point(patch.position)
	_check("all roots remain outside board", outside)
	paused = true
	var next := meadow._next_event
	meadow.set_pointer(Vector2.ZERO, Vector2(1000, 0))
	_check("paused input cannot disturb plants", meadow._next_event == next)
	paused = false
	var shader := FileAccess.get_file_as_string("res://assets/shaders/table_meadow_3d.gdshader")
	var camera_basis := Basis(Vector3.RIGHT, deg_to_rad(-60.0))
	meadow.set_camera_basis(camera_basis)
	var material_up: Vector3 = meadow._materials[0].get_shader_parameter("facing_up")
	_check("billboard bases follow main camera across passes", material_up.is_equal_approx(camera_basis.y) and shader.contains("MODELVIEW_NORMAL_MATRIX"))
	_check("board fragment clipping removed", not shader.contains("board_rect"))
	_check("wind follows source strength", is_equal_approx(meadow.wind_strength / 100.0, 0.105))
	_check("plant shadows remain disabled", meadow.shadow_batches.is_empty())
	for index in 150:
		meadow.elapsed = 0.07 + index * 0.001
		meadow.set_pointer(Vector2(660 + index, -1400), Vector2(1500, 0))
	_check("rapid motion cannot erase active first event", meadow._events[0].z == 0.0 and meadow._segments[0].x == -6.0)
	var cursor := meadow._next_event
	meadow.elapsed = 0.25
	meadow.set_pointer(Vector2(600, -1400), Vector2(60, 0), false, Vector2(599, -1400))
	_check("slow replay is blocked before interval", meadow._next_event == cursor)
	meadow.set_pointer(Vector2(1600, -1400), Vector2(1500, 0), false, Vector2(1200, -1400))
	_check("different region responds during cooldown", meadow._next_event != cursor)
	cursor = meadow._next_event
	meadow.elapsed = 0.351
	meadow.set_pointer(Vector2(590, -1400), Vector2(60, 0), false, Vector2(589, -1400))
	_check("same region can replay after interval", meadow._next_event != cursor)
	meadow.free()
	print("Meadow motion checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + label)
