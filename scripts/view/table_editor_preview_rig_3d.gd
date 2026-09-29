@tool
class_name TableEditorPreviewRig3D
extends Node3D

const CAMERA_GEOMETRY := preload("res://scripts/view/table_camera_geometry.gd")

enum PreviewMode {
	GAMEPLAY,
	MAIN_MENU,
}

@export_category("Game Camera Preview")
@export var preview_mode := PreviewMode.GAMEPLAY:
	set(value):
		preview_mode = value
		_queue_refresh()
@export var preview_resolution := Vector2i(1280, 800):
	set(value):
		preview_resolution = Vector2i(maxi(value.x, 320), maxi(value.y, 240))
		_queue_refresh()
@export_range(TableCamera.MIN_ZOOM, TableCamera.MAX_ZOOM, 0.01) var preview_zoom := 1.0:
	set(value):
		preview_zoom = clampf(value, TableCamera.MIN_ZOOM, TableCamera.MAX_ZOOM)
		_queue_refresh()
@export var preview_center_pixels := Vector2.ZERO:
	set(value):
		preview_center_pixels = value
		_queue_refresh()

@export_category("Pointer Light Preview")
@export var pointer_light_enabled := true:
	set(value):
		pointer_light_enabled = value
		_queue_refresh()
@export var pointer_logical_position := Vector2.ZERO:
	set(value):
		pointer_logical_position = value
		_queue_refresh()

var _refresh_queued := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(Engine.is_editor_hint())
	refresh_preview()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_environment_preview()


func refresh_preview() -> void:
	_refresh_queued = false
	var camera := get_preview_camera()
	if camera == null:
		return
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = CAMERA_GEOMETRY.FOV_DEGREES
	camera.near = 0.05
	camera.far = 1400.0
	camera.current = false
	camera.transform = get_expected_camera_transform()
	var pointer_light := get_node_or_null("PreviewPointerWarmLight") as OmniLight3D
	if pointer_light != null:
		pointer_light.position = FoldedTerrain.world_position(pointer_logical_position) + Vector3(0.0, 1.7, 0.0)
		pointer_light.visible = Engine.is_editor_hint() and pointer_light_enabled
	_apply_environment_preview()


func get_expected_camera_transform() -> Transform3D:
	if preview_mode == PreviewMode.MAIN_MENU:
		return CAMERA_GEOMETRY.menu_transform(float(preview_resolution.y))
	return CAMERA_GEOMETRY.gameplay_transform(
		float(preview_resolution.y),
		preview_zoom,
		preview_center_pixels
	)


func get_preview_camera() -> Camera3D:
	return get_node_or_null("EditorGamePreviewCamera") as Camera3D


func _apply_environment_preview() -> void:
	var camera := get_preview_camera()
	var vegetation := get_node_or_null("../EnvironmentRoot/EditableVegetation") as TablePaintedVegetation3D
	if camera == null or vegetation == null:
		return
	vegetation.set_camera_basis(camera.global_basis)
	var pointer_light := get_node_or_null("PreviewPointerWarmLight") as OmniLight3D
	var enabled := Engine.is_editor_hint() and pointer_light_enabled and pointer_light != null
	vegetation.set_pointer_light(
		pointer_light.global_position if pointer_light != null else Vector3.ZERO,
		pointer_light.omni_range if pointer_light != null else 4.5,
		pointer_light.light_energy if pointer_light != null else 0.0,
		pointer_light.light_color if pointer_light != null else Color("ffd7a0"),
		enabled
	)


func _queue_refresh() -> void:
	if not is_inside_tree() or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("refresh_preview")
