extends SceneTree

class TestStage extends Node3D:
	var scene_root: Node3D = self
	func to_terrain(at: Vector2) -> Vector2:
		return at

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures += 1


func _run() -> void:
	var stage := TestStage.new()
	root.add_child(stage)
	stage.add_to_group("click_particle_stage")
	var cursor = root.get_node("GameCursor")
	cursor.spawn_click_particles(Vector2(320, 240))
	var handle = cursor._particle_layer.get_child(0)
	var burst: CPUParticles3D = handle.emitters[0]
	_check("two depth-bearing dust layers", handle.emitters.size() == 2)
	_check("emitter belongs to scene world", burst.get_parent() == stage)
	_check("ground point in world space", burst.position.is_equal_approx(FoldedTerrain.world_position(Vector2(320, 240)) + Vector3.UP * 0.04))
	_check("real engine particle emitter", burst is CPUParticles3D)
	_check("one-shot bounded dust", burst.one_shot and burst.amount == 32 and burst.lifetime <= 1.1)
	_check("random sizes speeds and lifetimes", burst.scale_amount_min < burst.scale_amount_max and burst.initial_velocity_min < burst.initial_velocity_max and burst.lifetime_randomness > 0)
	_check("non-fixed random seed", not burst.use_fixed_seed)
	_check("independent world-space motes", not burst.local_coords)
	_check("friction decelerates dust", burst.damping_min > 0 and burst.damping_max > burst.damping_min)
	_check("alpha fades to zero", burst.color_ramp.sample(1.0).a == 0)
	_check("soft small particle texture", burst.mesh.material.albedo_texture.get_width() == 16)
	_check("no input interception", not burst.is_processing_input() and not burst.is_processing_unhandled_input())
	var first_mesh: Mesh = burst.mesh
	for index in range(100):
		cursor.spawn_click_particles(Vector2(200 + index, 300))
	_check("rapid clicks have hard burst cap", cursor.particle_count() == cursor.MAX_CLICK_BURSTS)
	_check("newest click still spawns", cursor.latest_particle_position() == Vector2(299, 300))
	_check("bursts share texture resource", cursor._particle_layer.get_child(0).emitters[0].mesh == first_mesh)
	paused = true
	await create_timer(cursor.CLICK_SPARK.CLEANUP_DEADLINE + 0.15, true).timeout
	await process_frame
	_check("world dust freezes while paused", cursor.particle_count() == cursor.MAX_CLICK_BURSTS)
	cursor.spawn_click_particles(Vector2(0, 0))
	_check("paused UI clicks do not emit", cursor.latest_particle_position() == Vector2(299, 300))
	paused = false
	await create_timer(cursor.CLICK_SPARK.CLEANUP_DEADLINE + 0.15).timeout
	await process_frame
	_check("resumed bursts clean up", cursor.particle_count() == 0)
	var previous: int = cursor.particle_count()
	for button in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = true
		cursor._input(event)
	_check("middle and wheel create no dust", cursor.particle_count() == previous)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	cursor._input(release)
	_check("release does not emit", cursor.particle_count() == previous)
	await process_frame
	_check("all external emitters also freed", stage.get_child_count() == 0)
	cursor.spawn_click_particles(Vector2(150, 120))
	var surviving_handle = cursor._particle_layer.get_child(0)
	stage.queue_free()
	await process_frame
	surviving_handle.queue_free()
	await process_frame
	_check("stage removal has no dangling emitter", cursor.particle_count() == 0)
	print("CLICK_DUST_FAILURES=%d" % failures)
	quit(1 if failures else 0)
