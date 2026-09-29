@tool
extends EditorPlugin

const SURFACE_RESOLVER_SCRIPT := preload(
	"res://addons/grass_painter/grass_surface_resolver.gd"
)

const GRASS_INSPECTOR_PLUGIN := preload(
	"res://addons/grass_painter/grass_inspector_plugin.gd"
)

var _toolbar: HBoxContainer
var _game_view_button: Button
var _brush_button: Button
var _erase_button: Button
var _radius_input: SpinBox
var _density_input: SpinBox
var _minimum_spacing_input: SpinBox
var _minimum_scale_input: SpinBox
var _maximum_scale_input: SpinBox
var _patch: GrassPatch3D
var _surface_resolver := SURFACE_RESOLVER_SCRIPT.new()
var _stroke_before := {}
var _stroke_active := false
var _last_stamp := Vector3(INF, INF, INF)
var _grass_inspector_plugin: EditorInspectorPlugin


func _enter_tree() -> void:
	_grass_inspector_plugin = GRASS_INSPECTOR_PLUGIN.new()
	_grass_inspector_plugin.call(
		"setup",
		get_editor_interface().get_resource_filesystem()
	)
	add_inspector_plugin(_grass_inspector_plugin)
	_build_toolbar()
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.visible = false
	set_process(true)


func _exit_tree() -> void:
	if is_instance_valid(_patch):
		_patch.set_brush_preview(Vector3.ZERO, 1.0, false)
	if _toolbar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()
	if _grass_inspector_plugin != null:
		remove_inspector_plugin(_grass_inspector_plugin)
		_grass_inspector_plugin = null


func _handles(object: Object) -> bool:
	return object is GrassPatch3D


func _edit(object: Object) -> void:
	if object is GrassPatch3D:
		_patch = object as GrassPatch3D
		_sync_controls_from_patch()
	else:
		_patch = null


func _make_visible(visible: bool) -> void:
	if _toolbar != null:
		_toolbar.visible = visible
	if not visible and is_instance_valid(_patch):
		_patch.set_brush_preview(Vector3.ZERO, 1.0, false)


func _process(_delta: float) -> void:
	var source_camera := _find_game_preview_camera()
	if source_camera == null:
		if _game_view_button != null and _game_view_button.button_pressed:
			_on_game_view_toggled(false)
		return
	if _game_view_button != null and _game_view_button.button_pressed:
		_sync_editor_camera(source_camera)


func _forward_3d_gui_input(
	viewport_camera: Camera3D,
	event: InputEvent
) -> int:
	if not is_instance_valid(_patch) or not _brush_button.button_pressed:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var hit := _ground_hit(viewport_camera, motion.position)
		if hit == null:
			_patch.set_brush_preview(Vector3.ZERO, _radius_input.value, false)
			return AFTER_GUI_INPUT_PASS
		var hit_position: Vector3 = hit
		_patch.set_brush_preview(hit_position, _radius_input.value, true)
		if _stroke_active and (
			_last_stamp == Vector3(INF, INF, INF)
			or _last_stamp.distance_to(hit_position) >= _radius_input.value * 0.22
		):
			_apply_stamp(hit_position, motion.ctrl_pressed)
		return AFTER_GUI_INPUT_STOP if _stroke_active else AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return AFTER_GUI_INPUT_PASS
		var hit := _ground_hit(viewport_camera, button.position)
		if button.pressed:
			if hit == null:
				return AFTER_GUI_INPUT_PASS
			_patch.materialize_default_fill()
			_stroke_before = _patch.snapshot_distribution()
			_stroke_active = true
			_last_stamp = Vector3(INF, INF, INF)
			_apply_stamp(hit, button.ctrl_pressed)
		else:
			_finish_stroke()
		return AFTER_GUI_INPUT_STOP

	return AFTER_GUI_INPUT_PASS


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "GrassPainterToolbar"
	_game_view_button = Button.new()
	_game_view_button.text = "Game View"
	_game_view_button.toggle_mode = true
	_game_view_button.tooltip_text = "Lock the editor viewport to the exact gameplay camera while painting."
	_game_view_button.toggled.connect(_on_game_view_toggled)
	_toolbar.add_child(_game_view_button)

	_brush_button = Button.new()
	_brush_button.text = "Grass Brush"
	_brush_button.toggle_mode = true
	_brush_button.tooltip_text = "Paint in the 3D viewport. Hold Ctrl to erase."
	_brush_button.toggled.connect(_on_brush_toggled)
	_toolbar.add_child(_brush_button)

	_erase_button = Button.new()
	_erase_button.text = "Erase"
	_erase_button.toggle_mode = true
	_erase_button.tooltip_text = "Use the active brush as an eraser."
	_toolbar.add_child(_erase_button)

	var radius_label := Label.new()
	radius_label.text = "Radius"
	_toolbar.add_child(radius_label)
	_radius_input = SpinBox.new()
	_radius_input.min_value = 0.25
	_radius_input.max_value = 16.0
	_radius_input.step = 0.25
	_radius_input.value = 2.5
	_radius_input.suffix = " m"
	_toolbar.add_child(_radius_input)

	var density_label := Label.new()
	density_label.text = "Density"
	_toolbar.add_child(density_label)
	_density_input = SpinBox.new()
	_density_input.min_value = 0.01
	_density_input.max_value = 100.0
	_density_input.allow_greater = true
	_density_input.step = 0.05
	_density_input.value = 0.65
	_density_input.tooltip_text = "Instances per square meter. Values above the shown range are allowed."
	_toolbar.add_child(_density_input)

	var minimum_spacing_label := Label.new()
	minimum_spacing_label.text = "Spacing"
	_toolbar.add_child(minimum_spacing_label)
	_minimum_spacing_input = SpinBox.new()
	_minimum_spacing_input.min_value = 0.0
	_minimum_spacing_input.max_value = 10.0
	_minimum_spacing_input.allow_greater = true
	_minimum_spacing_input.step = 0.05
	_minimum_spacing_input.value = 0.58
	_minimum_spacing_input.suffix = " m"
	_minimum_spacing_input.tooltip_text = "Minimum distance between new and existing grass. Set to 0 to allow overlap."
	_toolbar.add_child(_minimum_spacing_input)

	var minimum_scale_label := Label.new()
	minimum_scale_label.text = "Size Min"
	_toolbar.add_child(minimum_scale_label)
	_minimum_scale_input = SpinBox.new()
	_minimum_scale_input.min_value = 0.05
	_minimum_scale_input.max_value = 4.0
	_minimum_scale_input.allow_greater = true
	_minimum_scale_input.step = 0.05
	_minimum_scale_input.value = 0.72
	_minimum_scale_input.tooltip_text = "Smallest random grass scale for new painted instances."
	_toolbar.add_child(_minimum_scale_input)

	var maximum_scale_label := Label.new()
	maximum_scale_label.text = "Size Max"
	_toolbar.add_child(maximum_scale_label)
	_maximum_scale_input = SpinBox.new()
	_maximum_scale_input.min_value = 0.05
	_maximum_scale_input.max_value = 4.0
	_maximum_scale_input.allow_greater = true
	_maximum_scale_input.step = 0.05
	_maximum_scale_input.value = 1.18
	_maximum_scale_input.tooltip_text = "Largest random grass scale for new painted instances."
	_toolbar.add_child(_maximum_scale_input)

	var fill_button := Button.new()
	fill_button.text = "Fill"
	fill_button.tooltip_text = "Bake the deterministic clustered base fill."
	fill_button.pressed.connect(_on_fill_pressed)
	_toolbar.add_child(fill_button)

	var clear_button := Button.new()
	clear_button.text = "Clear"
	clear_button.tooltip_text = "Remove all painted grass."
	clear_button.pressed.connect(_on_clear_pressed)
	_toolbar.add_child(clear_button)


func _find_game_preview_camera() -> Camera3D:
	var edited_root := get_editor_interface().get_edited_scene_root()
	if edited_root == null:
		return null
	return edited_root.find_child("EditorGamePreviewCamera", true, false) as Camera3D

func _sync_editor_camera(source_camera: Camera3D) -> void:
	var editor_viewport := get_editor_interface().get_editor_viewport_3d(0)
	if editor_viewport == null:
		return
	var editor_camera := editor_viewport.get_camera_3d()
	if editor_camera == null:
		return
	_copy_camera(source_camera, editor_camera)


func _copy_camera(source: Camera3D, target: Camera3D) -> void:
	target.global_transform = source.global_transform
	target.projection = source.projection
	target.keep_aspect = source.keep_aspect
	target.fov = source.fov
	target.near = source.near
	target.far = source.far
	target.cull_mask = source.cull_mask


func _on_game_view_toggled(enabled: bool) -> void:
	if _game_view_button != null:
		_game_view_button.set_pressed_no_signal(enabled)
	if enabled:
		var source_camera := _find_game_preview_camera()
		if source_camera != null:
			_sync_editor_camera(source_camera)


func _on_brush_toggled(enabled: bool) -> void:
	if not enabled and is_instance_valid(_patch):
		_patch.set_brush_preview(Vector3.ZERO, _radius_input.value, false)
		_finish_stroke()


func _on_fill_pressed() -> void:
	if not is_instance_valid(_patch):
		return
	var before := _patch.snapshot_distribution()
	var surface: Node = _surface_resolver.find_related(_patch)
	var surface_sampler := Callable()
	if surface != null:
		surface_sampler = Callable(
			_surface_resolver,
			"sample_surface"
		).bind(surface)
	_patch.bake_default_fill_with_parameters(
		_density_input.value,
		_minimum_spacing_input.value,
		_minimum_scale_input.value,
		_maximum_scale_input.value,
		surface_sampler
	)
	_commit_distribution_action("Fill grass", before, _patch.snapshot_distribution())


func _on_clear_pressed() -> void:
	if not is_instance_valid(_patch):
		return
	_patch.materialize_default_fill()
	var before := _patch.snapshot_distribution()
	_patch.clear_distribution()
	_commit_distribution_action("Clear grass", before, _patch.snapshot_distribution())


func _apply_stamp(world_position: Vector3, control_erase: bool) -> void:
	var erase := _erase_button.button_pressed or control_erase
	var surface: Node = _surface_resolver.find_related(_patch)
	var surface_sampler := Callable()
	if surface != null:
		surface_sampler = Callable(
			_surface_resolver,
			"sample_surface"
		).bind(surface)
	_patch.paint_stamp(
		world_position,
		_radius_input.value,
		_density_input.value,
		_minimum_spacing_input.value,
		_minimum_scale_input.value,
		_maximum_scale_input.value,
		erase,
		surface_sampler
	)
	_last_stamp = world_position


func _finish_stroke() -> void:
	if not _stroke_active or not is_instance_valid(_patch):
		_stroke_active = false
		return
	_stroke_active = false
	var label := "Erase grass" if _erase_button.button_pressed else "Paint grass"
	_commit_distribution_action(label, _stroke_before, _patch.snapshot_distribution())
	_stroke_before = {}


func _commit_distribution_action(
	label: String,
	before: Dictionary,
	after: Dictionary
) -> void:
	var undo_redo := get_undo_redo()
	undo_redo.create_action(label, UndoRedo.MERGE_DISABLE, _patch)
	undo_redo.add_do_method(_patch, "restore_distribution", after)
	undo_redo.add_undo_method(_patch, "restore_distribution", before)
	undo_redo.commit_action(false)


func _ground_hit(viewport_camera: Camera3D, mouse_position: Vector2) -> Variant:
	var ray_origin := viewport_camera.project_ray_origin(mouse_position)
	var ray_direction := viewport_camera.project_ray_normal(mouse_position)
	var surface: Node = _surface_resolver.find_related(_patch)
	if surface != null:
		return _surface_resolver.raycast_surface(
			viewport_camera,
			mouse_position,
			surface
		)
	var ground_plane := Plane(Vector3.UP, _patch.global_position.y)
	return ground_plane.intersects_ray(ray_origin, ray_direction)


func _sync_controls_from_patch() -> void:
	if not is_instance_valid(_patch):
		return
	if _minimum_scale_input != null:
		_minimum_scale_input.value = _patch.minimum_scale
	if _maximum_scale_input != null:
		_maximum_scale_input.value = _patch.maximum_scale
	if _minimum_spacing_input != null:
		_minimum_spacing_input.value = _patch.minimum_spacing
