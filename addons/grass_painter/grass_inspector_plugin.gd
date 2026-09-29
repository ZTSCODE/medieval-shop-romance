@tool
extends EditorInspectorPlugin

const TEXTURE_PROPERTY := preload(
	"res://addons/grass_painter/grass_texture_property.gd"
)

var _filesystem: EditorFileSystem


func setup(filesystem: EditorFileSystem) -> void:
	_filesystem = filesystem


func _can_handle(object: Object) -> bool:
	return object is GrassPatch3D


func _parse_property(
	_object: Object,
	_type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if name != "static_texture":
		return false
	var property := TEXTURE_PROPERTY.new()
	property.setup(_filesystem)
	add_property_editor(name, property)
	return true
