class_name GameSettings
extends RefCounted

signal changed

const DEFAULTS := {
	"window_mode": "windowed",
	"window_resolution": Vector2i.ZERO,
	"ui_scale": "auto",
	"master_volume": 0.8,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"muted": false,
	"hdr_output": false,
	"locale": "zh_CN",
}
const WINDOW_MODES := ["windowed", "borderless", "fullscreen"]
const LOCALES := ["zh_CN", "en"]
const MAX_CONFIG_BYTES := 65536
const VOLUME_BUSES := {"master_volume": "Master", "music_volume": "Music", "sfx_volume": "SFX"}

var values: Dictionary = DEFAULTS.duplicate(true)
var error_key := ""
var _path: String
var _windowed_size := Vector2i(1280, 800)
var _windowed_position := Vector2i.ZERO
var _has_windowed_geometry := false
var _applied_window_mode := ""
var _applied_resolution := Vector2i(-1, -1)
var _loaded_config := ConfigFile.new()


func _init(path: String = "user://settings.cfg") -> void:
	_path = ProjectSettings.globalize_path(path).simplify_path()


func load_settings() -> bool:
	error_key = ""
	values = DEFAULTS.duplicate(true)
	_loaded_config = ConfigFile.new()
	if not FileAccess.file_exists(_path):
		apply_all()
		changed.emit()
		return true
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return _load_failure("SETTINGS_READ_FAILED")
	var length := file.get_length()
	if length > MAX_CONFIG_BYTES or length == 0:
		file.close()
		return _load_failure("SETTINGS_READ_FAILED")
	var contents := file.get_buffer(length)
	file.close()
	if contents.size() != length:
		return _load_failure("SETTINGS_READ_FAILED")
	var config := ConfigFile.new()
	if config.parse(contents.get_string_from_utf8()) != OK:
		return _load_failure("SETTINGS_READ_FAILED")
	var scale_version: Variant = config.get_value("meta", "ui_scale_version", 1)
	if typeof(scale_version) != TYPE_INT or scale_version < 1 or scale_version > UiScale.CONFIG_VERSION:
		return _load_failure("SETTINGS_INVALID_VALUE")
	var candidate := DEFAULTS.duplicate(true)
	for key: String in DEFAULTS:
		var value: Variant = config.get_value("settings", key, DEFAULTS[key])
		if key == "ui_scale" and scale_version == 1:
			if typeof(value) != TYPE_STRING or value not in UiScale.LEGACY_OPTIONS:
				return _load_failure("SETTINGS_INVALID_VALUE")
			value = UiScale.migrate_legacy(value)
		if not _valid_value(key, value):
			return _load_failure("SETTINGS_INVALID_VALUE")
		candidate[key] = float(value) if key.ends_with("_volume") else value
	values = candidate
	_loaded_config = config
	var saved_size: Variant = config.get_value("window", "size") if config.has_section_key("window", "size") else null
	var saved_position: Variant = config.get_value("window", "position") if config.has_section_key("window", "position") else null
	if saved_size is Vector2i and saved_position is Vector2i and saved_size.x >= 64 and saved_size.y >= 64 and saved_size.x <= 32768 and saved_size.y <= 32768:
		_windowed_size = saved_size
		_windowed_position = saved_position
		_has_windowed_geometry = true
	_applied_window_mode = ""
	_applied_resolution = Vector2i(-1, -1)
	apply_all()
	changed.emit()
	return true


func set_value(key: String, value: Variant) -> bool:
	error_key = ""
	if not _valid_value(key, value):
		error_key = "SETTINGS_INVALID_VALUE"
		return false
	if key == "hdr_output":
		return _set_hdr_output(value)
	if VOLUME_BUSES.has(key):
		return set_volumes({key: value})
	var previous: Variant = values[key]
	values[key] = float(value) if key.ends_with("_volume") else value
	if not save_settings():
		values[key] = previous
		return false
	if key == "window_resolution":
		_applied_resolution = Vector2i(-1, -1)
	apply_all()
	changed.emit()
	return true


func get_value(key: String) -> Variant:
	return values.get(key)


func preview_volume(key: String, value: float) -> bool:
	if not VOLUME_BUSES.has(key) or not _valid_value(key, value):
		return false
	_apply_volume(key, value)
	return true


func set_volumes(updates: Dictionary) -> bool:
	error_key = ""
	for key: String in updates:
		if not VOLUME_BUSES.has(key) or not _valid_value(key, updates[key]):
			error_key = "SETTINGS_INVALID_VALUE"
			return false
	var previous := values.duplicate()
	var has_change := false
	for key: String in updates:
		has_change = has_change or not is_equal_approx(float(values[key]), float(updates[key]))
		values[key] = float(updates[key])
	var success := not has_change or save_settings()
	if not success:
		values = previous
	for key: String in updates:
		_apply_volume(key, float(values[key]))
	if has_change:
		changed.emit()
	return success


func _apply_volume(key: String, value: float) -> void:
	var index := AudioServer.get_bus_index(VOLUME_BUSES[key])
	if index < 0:
		_ensure_audio_buses()
		index = AudioServer.get_bus_index(VOLUME_BUSES[key])
	AudioServer.set_bus_volume_linear(index, value)


func save_settings() -> bool:
	error_key = ""
	for key: String in DEFAULTS:
		if not _valid_value(key, values.get(key)):
			error_key = "SETTINGS_INVALID_VALUE"
			return false
	_remember_windowed_geometry()
	var config := ConfigFile.new()
	config.parse(_loaded_config.encode_to_text())
	config.set_value("meta", "ui_scale_version", UiScale.CONFIG_VERSION)
	for key: String in DEFAULTS:
		config.set_value("settings", key, values[key])
	if _has_windowed_geometry:
		config.set_value("window", "size", _windowed_size)
		config.set_value("window", "position", _windowed_position)
	if not _make_directory(_path.get_base_dir()):
		error_key = "SETTINGS_WRITE_FAILED"
		return false
	var temporary := _path + ".tmp"
	if config.save(temporary) != OK or DirAccess.rename_absolute(temporary, _path) != OK:
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)
		error_key = "SETTINGS_WRITE_FAILED"
		return false
	_loaded_config = config
	return true


func apply_all() -> void:
	_ensure_audio_buses()
	for bus_name: String in ["Master", "Music", "SFX"]:
		var key := {"Master": "master_volume", "Music": "music_volume", "SFX": "sfx_volume"}[bus_name] as String
		AudioServer.set_bus_volume_linear(AudioServer.get_bus_index(bus_name), float(values[key]))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), bool(values.muted))
	TranslationServer.set_locale(str(values.locale))
	_apply_window_mode()
	_apply_hdr_output()
	UiScale.configure(str(values.ui_scale))


func _valid_value(key: String, value: Variant) -> bool:
	match key:
		"ui_scale":
			return typeof(value) == TYPE_STRING and value in UiScale.OPTIONS
		"window_resolution":
			return value is Vector2i and (value == Vector2i.ZERO or (value.x >= 960 and value.y >= 640 and value.x <= 16384 and value.y <= 16384))
		"window_mode":
			return typeof(value) == TYPE_STRING and WINDOW_MODES.has(value)
		"locale":
			return typeof(value) == TYPE_STRING and LOCALES.has(value)
		"muted", "hdr_output":
			return typeof(value) == TYPE_BOOL
		"master_volume", "music_volume", "sfx_volume":
			return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 1.0
	return false


func get_hdr_unavailable_reason() -> String:
	if RenderingServer.get_current_rendering_method() not in ["mobile", "forward_plus"]:
		return "SETTINGS_HDR_RENDERER_UNSUPPORTED"
	if DisplayServer.get_name() == "headless" or not DisplayServer.window_is_hdr_output_supported():
		return "SETTINGS_HDR_DEVICE_UNSUPPORTED"
	return ""


func is_hdr_active() -> bool:
	return DisplayServer.get_name() != "headless" and DisplayServer.window_is_hdr_output_enabled()


func _set_hdr_output(enabled: bool) -> bool:
	if enabled:
		error_key = get_hdr_unavailable_reason()
		if not error_key.is_empty():
			return false
	var previous := bool(values.hdr_output)
	_request_hdr_output(enabled)
	if enabled and not is_hdr_active():
		_request_hdr_output(previous)
		error_key = "SETTINGS_HDR_OUTPUT_UNAVAILABLE"
		return false
	values.hdr_output = enabled
	if not save_settings():
		values.hdr_output = previous
		_request_hdr_output(previous)
		return false
	changed.emit()
	return true


func _apply_hdr_output() -> void:
	if bool(values.hdr_output) and not get_hdr_unavailable_reason().is_empty():
		values.hdr_output = false
	_request_hdr_output(bool(values.hdr_output))
	if bool(values.hdr_output) and not is_hdr_active():
		values.hdr_output = false
		_request_hdr_output(false)


func _request_hdr_output(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() not in ["mobile", "forward_plus"]:
		return
	DisplayServer.window_request_hdr_output(enabled)


func _load_failure(key: String) -> bool:
	error_key = key
	apply_all()
	changed.emit()
	return false


func _ensure_audio_buses() -> void:
	if AudioServer.bus_count == 0:
		AudioServer.add_bus()
	if AudioServer.get_bus_index("Master") < 0:
		AudioServer.set_bus_name(0, "Master")
	for bus_name: String in ["Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


func _remember_windowed_geometry() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED or DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		return
	_windowed_size = DisplayServer.window_get_size()
	_windowed_position = DisplayServer.window_get_position()
	_has_windowed_geometry = true


func _make_directory(path: String) -> bool:
	var ancestor := path
	while not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor):
			return false
		var parent := ancestor.get_base_dir()
		if parent == ancestor or parent.is_empty():
			break
		ancestor = parent
	return DirAccess.make_dir_recursive_absolute(path) == OK


func _apply_window_mode() -> void:
	var mode := str(values.window_mode)
	var resolution: Vector2i = values.window_resolution
	if DisplayServer.get_name() == "headless" or (mode == _applied_window_mode and resolution == _applied_resolution):
		return
	if _applied_window_mode == "windowed" or not _has_windowed_geometry:
		_remember_windowed_geometry()
	match mode:
		"windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			if resolution != Vector2i.ZERO:
				_windowed_size = resolution
			_restore_windowed_geometry()
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	_applied_window_mode = mode
	_applied_resolution = resolution


func get_resolution_options() -> Array[Vector2i]:
	var maximum := Vector2i(3840, 2160)
	if DisplayServer.get_name() != "headless":
		maximum = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
		maximum -= Vector2i(16, 48)
	var result: Array[Vector2i] = []
	for dimensions: Vector2i in [Vector2i(960, 640), Vector2i(1024, 768), Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1366, 768), Vector2i(1440, 900), Vector2i(1600, 900), Vector2i(1680, 1050), Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2560, 1440), Vector2i(2560, 1600), Vector2i(3440, 1440), Vector2i(3840, 2160)]:
		if dimensions.x <= maximum.x and dimensions.y <= maximum.y:
			result.append(dimensions)
	return result


func _restore_windowed_geometry() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var desired := Rect2i(_windowed_position, _windowed_size)
	var best_area := 0
	for candidate: int in DisplayServer.get_screen_count():
		var candidate_rect := DisplayServer.screen_get_usable_rect(candidate)
		var overlap := desired.intersection(candidate_rect)
		var area := overlap.size.x * overlap.size.y
		if area > best_area:
			best_area = area
			screen = candidate
	var work_area := DisplayServer.screen_get_usable_rect(screen)
	if work_area.size.x <= 0 or work_area.size.y <= 0:
		return
	var decoration_size := DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	var decoration_offset := DisplayServer.window_get_position() - DisplayServer.window_get_position_with_decorations()
	decoration_size = Vector2i(maxi(0, decoration_size.x), maxi(0, decoration_size.y))
	decoration_offset = Vector2i(maxi(0, decoration_offset.x), maxi(0, decoration_offset.y))
	var maximum := work_area.size - decoration_size
	var project_minimum := Vector2i(int(ProjectSettings.get_setting("display/window/size/min_width", 960)), int(ProjectSettings.get_setting("display/window/size/min_height", 640)))
	var minimum := Vector2i(mini(project_minimum.x, maximum.x), mini(project_minimum.y, maximum.y))
	_windowed_size = Vector2i(clampi(_windowed_size.x, minimum.x, maximum.x), clampi(_windowed_size.y, minimum.y, maximum.y))
	var first_position := work_area.position + decoration_offset
	var last_position := first_position + maximum - _windowed_size
	if best_area == 0 or not _has_windowed_geometry:
		_windowed_position = first_position + (maximum - _windowed_size) / 2
	_windowed_position = Vector2i(clampi(_windowed_position.x, first_position.x, last_position.x), clampi(_windowed_position.y, first_position.y, last_position.y))
	DisplayServer.window_set_min_size(minimum)
	DisplayServer.window_set_size(_windowed_size)
	DisplayServer.window_set_position(_windowed_position)
	_has_windowed_geometry = true
