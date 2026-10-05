extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures += 1

func _run() -> void:
	var stage := TableStage3D.new()
	root.add_child(stage)
	var camera := TableCamera.new()
	for window_size in [Vector2i(960, 640), Vector2i(1920, 1080), Vector2i(3840, 2160)]:
		root.size = window_size
		await process_frame
		var rect := root.get_visible_rect()
		camera.set_bounds(rect)
		for zoom in [0.44, 1.0, 1.8]:
			camera.zoom = zoom
			stage.configure(rect, camera)
			for fraction in [Vector2(0.2, 0.25), Vector2(0.5, 0.5), Vector2(0.8, 0.8)]:
				var point: Vector2 = rect.position + rect.size * fraction
				var ground := stage.to_terrain(point)
				var position_3d := FoldedTerrain.world_position(ground)
				var projected := stage.camera_3d.unproject_position(stage.scene_root.global_transform * position_3d) / stage._render_scale + stage._effective_rect.position
				_check("ray returns click %s zoom %.2f point %s" % [window_size, zoom, fraction], point.distance_to(projected) < 0.1)
	_check("registered stage available", get_first_node_in_group("click_particle_stage") == stage)
	_check("board point allows dust", stage.can_emit_click_dust(stage._effective_rect.get_center()))
	paused = true
	_check("pause blocks world emitter", not stage.can_emit_click_dust(stage._effective_rect.get_center()))
	paused = false
	stage.set_menu_view(true, true)
	_check("main menu blocks world emitter", not stage.can_emit_click_dust(stage._effective_rect.get_center()))
	stage.queue_free()
	await process_frame
	print("CLICK_DUST_PROJECTION_FAILURES=%d" % failures)
	quit(1 if failures else 0)
