extends SceneTree

const Settings = preload("res://scripts/services/game_settings.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		print("SETTINGS_HDR_TEST requires --headless")
		quit(2)
		return
	var audio := AudioServer.generate_bus_layout()
	var locale := TranslationServer.get_locale()
	var directory := "res://work/settings-hdr-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join("settings.cfg")
	var settings := Settings.new(path)
	_check("local HDR request API exists", DisplayServer.has_method("window_request_hdr_output"))
	_check("local HDR support API exists", DisplayServer.has_method("window_is_hdr_output_supported"))
	_check("local HDR status API exists", DisplayServer.has_method("window_is_hdr_output_enabled"))
	_check("fresh config defaults to disabled", settings.load_settings() and settings.get_value("hdr_output") == false)
	_check("default is not active", not settings.is_hdr_active())
	var config := ConfigFile.new()
	config.set_value("settings", "master_volume", 0.43)
	config.save(path)
	_check("older config without HDR loads", settings.load_settings() and settings.get_value("hdr_output") == false and is_equal_approx(settings.get_value("master_volume"), 0.43))
	_check("disabled HDR persists", settings.set_value("hdr_output", false))
	config.load(path)
	_check("HDR bool roundtrips", config.get_value("settings", "hdr_output") == false and Settings.new(path).load_settings())
	var hash_before := FileAccess.get_sha256(path)
	for invalid: Variant in ["true", 1, 0.0, null]:
		_check("invalid HDR value rejected type %d" % typeof(invalid), not settings.set_value("hdr_output", invalid) and settings.error_key == "SETTINGS_INVALID_VALUE")
	_check("invalid values do not modify persisted config", FileAccess.get_sha256(path) == hash_before)
	var reason := settings.get_hdr_unavailable_reason()
	_check("unsupported environment has a reason", not reason.is_empty())
	_check("unsupported enable rejected", not settings.set_value("hdr_output", true) and settings.error_key == reason)
	_check("failed enable leaves state and file unchanged", settings.get_value("hdr_output") == false and not settings.is_hdr_active() and FileAccess.get_sha256(path) == hash_before)
	config.set_value("settings", "hdr_output", true)
	config.save(path)
	var saved_enabled_hash := FileAccess.get_sha256(path)
	_check("unavailable persisted request falls back to SDR", settings.load_settings() and settings.get_value("hdr_output") == false and not settings.is_hdr_active())
	_check("loading does not overwrite stored config", FileAccess.get_sha256(path) == saved_enabled_hash)
	config.set_value("settings", "hdr_output", "invalid")
	config.save(path)
	_check("invalid stored HDR rejected", not settings.load_settings() and settings.error_key == "SETTINGS_INVALID_VALUE" and settings.get_value("hdr_output") == false)
	AudioServer.set_bus_layout(audio)
	TranslationServer.set_locale(locale)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	print("SETTINGS_HDR_TEST: %d checks, %d failures; engine=%s; reason=%s" % [checks, failures, Engine.get_version_info().string, reason])
	quit(0 if failures == 0 else 1)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print("%s: %s" % ["PASS" if passed else "FAIL", label])
