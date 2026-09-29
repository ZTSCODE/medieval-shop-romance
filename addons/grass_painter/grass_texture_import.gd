@tool
extends RefCounted

const DEFAULT_IMPORT_DIRECTORY := "res://assets/props/grass_types"
const SUPPORTED_EXTENSIONS := ["png", "webp", "jpg", "jpeg"]


static func import_external_file(
	source_path: String,
	destination_directory: String = DEFAULT_IMPORT_DIRECTORY
) -> Dictionary:
	var source_absolute := _absolute_path(source_path)
	if source_absolute.is_empty() or not FileAccess.file_exists(source_absolute):
		return _failure("Grass texture source file does not exist")
	var extension := source_absolute.get_extension().to_lower()
	if not SUPPORTED_EXTENSIONS.has(extension):
		return _failure("Grass texture type is not supported")
	var localized_source := ProjectSettings.localize_path(source_absolute)
	if localized_source.begins_with("res://"):
		return {
			"status": "ok",
			"resource_path": localized_source,
			"copied": false,
		}
	if not (
		destination_directory.begins_with("res://")
		or destination_directory.begins_with("user://")
	):
		return _failure("Grass texture destination must use res:// or user://")
	var destination_absolute := ProjectSettings.globalize_path(destination_directory)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(destination_absolute)
	if mkdir_error != OK:
		return _failure("Cannot create grass texture destination (error %d)" % mkdir_error)
	var destination_path := _unique_destination_path(
		destination_directory,
		source_absolute.get_file().get_basename(),
		extension
	)
	var copy_error := DirAccess.copy_absolute(
		source_absolute,
		ProjectSettings.globalize_path(destination_path)
	)
	if copy_error != OK:
		return _failure("Cannot copy grass texture into project (error %d)" % copy_error)
	return {
		"status": "ok",
		"resource_path": destination_path,
		"copied": true,
	}


static func _absolute_path(path: String) -> String:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		return ProjectSettings.globalize_path(normalized).replace("\\", "/")
	return normalized.simplify_path()


static func _unique_destination_path(
	destination_directory: String,
	base_name: String,
	extension: String
) -> String:
	var candidate := destination_directory.path_join("%s.%s" % [base_name, extension])
	var suffix := 2
	while FileAccess.file_exists(candidate):
		candidate = destination_directory.path_join(
			"%s_%03d.%s" % [base_name, suffix, extension]
		)
		suffix += 1
	return candidate


static func _failure(message: String) -> Dictionary:
	return {
		"status": "error",
		"errors": PackedStringArray([message]),
	}
