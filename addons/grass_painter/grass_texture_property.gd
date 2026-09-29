@tool
extends EditorProperty

const TEXTURE_IMPORT := preload(
	"res://addons/grass_painter/grass_texture_import.gd"
)

var _picker: EditorResourcePicker
var _drop_hint: Label
var _filesystem: EditorFileSystem
var _pending_resource_path := ""
var _pending_object_id := 0
var _updating_picker := false


func _init() -> void:
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(content)
	_picker = EditorResourcePicker.new()
	_picker.base_type = "Texture2D"
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.resource_changed.connect(_on_resource_changed)
	content.add_child(_picker)
	add_focusable(_picker)
	_drop_hint = Label.new()
	_drop_hint.text = "可从 Windows 资源管理器直接拖入 PNG/WebP"
	_drop_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_drop_hint.modulate = Color(0.72, 0.78, 0.88)
	content.add_child(_drop_hint)


func setup(filesystem: EditorFileSystem) -> void:
	_filesystem = filesystem


func _ready() -> void:
	var window := get_window()
	if window != null and not window.files_dropped.is_connected(_on_files_dropped):
		window.files_dropped.connect(_on_files_dropped)
	if _filesystem != null:
		if not _filesystem.resources_reimported.is_connected(_on_resources_reimported):
			_filesystem.resources_reimported.connect(_on_resources_reimported)
		if not _filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
			_filesystem.filesystem_changed.connect(_on_filesystem_changed)


func _exit_tree() -> void:
	var window := get_window()
	if window != null and window.files_dropped.is_connected(_on_files_dropped):
		window.files_dropped.disconnect(_on_files_dropped)
	if _filesystem != null and is_instance_valid(_filesystem):
		if _filesystem.resources_reimported.is_connected(_on_resources_reimported):
			_filesystem.resources_reimported.disconnect(_on_resources_reimported)
		if _filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
			_filesystem.filesystem_changed.disconnect(_on_filesystem_changed)


func _update_property() -> void:
	var edited := get_edited_object()
	if edited == null:
		return
	_updating_picker = true
	_picker.edited_resource = edited.get(get_edited_property()) as Resource
	_updating_picker = false


func _on_resource_changed(resource: Resource) -> void:
	if _updating_picker:
		return
	emit_changed(get_edited_property(), resource)


func _on_files_dropped(files: PackedStringArray) -> void:
	if not is_visible_in_tree() or not _is_mouse_over_property():
		return
	if files.size() != 1:
		_set_status("一次只能拖入一张草图片。", true)
		return
	var edited := get_edited_object()
	if not edited is GrassPatch3D:
		_set_status("当前属性没有连接 GrassField。", true)
		return
	var import_result := TEXTURE_IMPORT.import_external_file(files[0])
	if import_result.get("status") != "ok":
		var errors := import_result.get("errors", PackedStringArray()) as PackedStringArray
		_set_status("导入失败：%s" % "; ".join(errors), true)
		return
	_pending_resource_path = String(import_result.get("resource_path", ""))
	_pending_object_id = edited.get_instance_id()
	_set_status("正在导入：%s" % _pending_resource_path.get_file(), false)
	if _try_apply_pending_texture():
		return
	if _filesystem == null:
		_set_status("无法取得 Godot 资源导入器。", true)
		_clear_pending()
		return
	_filesystem.scan()
	_try_apply_pending_texture.call_deferred()


func _on_resources_reimported(resources: PackedStringArray) -> void:
	if _pending_resource_path.is_empty():
		return
	if resources.has(_pending_resource_path):
		_try_apply_pending_texture.call_deferred()


func _on_filesystem_changed() -> void:
	if not _pending_resource_path.is_empty():
		_try_apply_pending_texture.call_deferred()


func _try_apply_pending_texture() -> bool:
	if _pending_resource_path.is_empty() or not ResourceLoader.exists(
		_pending_resource_path,
		"Texture2D"
	):
		return false
	var texture := ResourceLoader.load(
		_pending_resource_path,
		"Texture2D",
		ResourceLoader.CACHE_MODE_REPLACE
	) as Texture2D
	if texture == null:
		return false
	var edited := instance_from_id(_pending_object_id)
	if not edited is GrassPatch3D:
		_set_status("草层已关闭，图片已导入但没有替换属性。", true)
		_clear_pending()
		return false
	if get_edited_object() != edited:
		_set_status("当前选择已改变，图片已导入但没有替换其他草层。", true)
		_clear_pending()
		return false
	emit_changed(get_edited_property(), texture)
	_updating_picker = true
	_picker.edited_resource = texture
	_updating_picker = false
	_set_status("已导入并替换：%s" % _pending_resource_path, false)
	_clear_pending()
	return true


func _is_mouse_over_property() -> bool:
	return Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())


func _set_status(message: String, is_error: bool) -> void:
	_drop_hint.text = message
	_drop_hint.modulate = (
		Color(1.0, 0.55, 0.50)
		if is_error
		else Color(0.58, 0.90, 0.66)
	)


func _clear_pending() -> void:
	_pending_resource_path = ""
	_pending_object_id = 0
