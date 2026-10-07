extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/world/table_environment_editable.tscn") as PackedScene
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	var rig := scene.get_node_or_null("EditorGamePreviewRig") as TableEditorPreviewRig3D
	var preview_camera := scene.get_node_or_null("EditorGamePreviewRig/EditorGamePreviewCamera") as Camera3D
	var preview_light := scene.get_node_or_null("EditorGamePreviewRig/PreviewPointerWarmLight") as OmniLight3D
	_check("editable scene contains the game preview rig", rig != null and preview_camera != null and preview_light != null)
	rig.refresh_preview()
	var expected := TableCameraGeometry.gameplay_transform(800.0, 1.0, Vector2.ZERO)
	_check("default preview camera uses exact gameplay framing", preview_camera.transform.is_equal_approx(expected))
	_check("preview camera shares gameplay projection settings", preview_camera.projection == Camera3D.PROJECTION_PERSPECTIVE and preview_camera.keep_aspect == Camera3D.KEEP_HEIGHT and is_equal_approx(preview_camera.fov, 32.0) and is_equal_approx(preview_camera.near, 0.05) and is_equal_approx(preview_camera.far, 1400.0))
	_check("preview helper light stays disabled in the running game", not preview_light.visible)
	rig.preview_resolution = Vector2i(1920, 1080)
	rig.preview_zoom = 1.35
	rig.preview_center_pixels = Vector2(240.0, -180.0)
	rig.refresh_preview()
	expected = TableCameraGeometry.gameplay_transform(1080.0, 1.35, Vector2(240.0, -180.0))
	_check("preview resolution zoom and center update the same camera formula", preview_camera.transform.is_equal_approx(expected))
	rig.preview_mode = TableEditorPreviewRig3D.PreviewMode.MAIN_MENU
	rig.refresh_preview()
	_check("preview can switch to the real main menu framing", preview_camera.transform.is_equal_approx(TableCameraGeometry.menu_transform(1080.0)))

	var camera_model := TableCamera.new()
	var screen_rect := Rect2(Vector2.ZERO, Vector2(1280.0, 800.0))
	camera_model.set_bounds(screen_rect)
	var stage := TableStage3D.new()
	root.add_child(stage)
	stage.configure(screen_rect, camera_model)
	_check("runtime camera consumes the shared preview geometry", stage.camera_3d.transform.is_equal_approx(TableCameraGeometry.gameplay_transform(800.0, 1.0, Vector2.ZERO)))
	var plugin_source := FileAccess.get_file_as_string("res://addons/grass_painter/plugin.gd")
	_check("grass painter exposes a locked live game camera view", plugin_source.contains("Game View") and plugin_source.contains("get_editor_viewport_3d") and plugin_source.contains("_sync_editor_camera"))

	print("EDITOR_GAME_PREVIEW_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
	print(("PASS " if condition else "FAIL ") + label)
