extends SceneTree

const SettingsScript = preload("res://scripts/services/game_settings.gd")
const StoreScript = preload("res://scripts/services/save_store.gd")

var checks := 0
var failures := 0
var test_root := ""


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		print("STORAGE_SETTINGS_SUITE requires --headless to isolate display settings")
		quit(2)
		return
	var initial_audio := AudioServer.generate_bus_layout()
	var initial_locale := TranslationServer.get_locale()
	test_root = ProjectSettings.globalize_path("res://work/storage-settings-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(test_root)
	_test_save_store()
	_test_settings()
	AudioServer.set_bus_layout(initial_audio)
	TranslationServer.set_locale(initial_locale)
	_check("audio environment restored", AudioServer.bus_count == _layout_count(initial_audio))
	print("STORAGE_SETTINGS_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_save_store() -> void:
	var store := StoreScript.new(test_root.path_join("saves"))
	var slots: Array[Dictionary] = store.list_slots()
	_check("four fixed empty slots", slots.size() == 4 and slots.map(func(entry: Dictionary) -> String: return entry.slot) == ["auto", "slot_1", "slot_2", "slot_3"])
	_check("empty slots are absent and invalid", slots.all(func(entry: Dictionary) -> bool: return not entry.exists and not entry.valid and not entry.recovered))
	_check("missing save has a clear error", store.read_save("auto").error_key == "SAVE_NOT_FOUND")
	for slot in ["../outside", "slot_4", "", "auto.json", "C:/outside"]:
		_check("slot whitelist rejects read " + slot, store.read_save(slot).error_key == "SAVE_INVALID_SLOT")
		_check("slot whitelist rejects write " + slot, store.write_save(slot, {}).error_key == "SAVE_INVALID_SLOT")
	var payload := _payload(3)
	var written: Dictionary = store.write_save("slot_1", payload)
	_check("first save writes successfully", written.ok and written.error_key.is_empty())
	var primary := store.directory.path_join("slot_1.json")
	var loaded: Dictionary = store.read_save("slot_1")
	_check("save is data-only JSON", JSON.parse_string(FileAccess.get_file_as_string(primary)) is Dictionary)
	_check("complete nested payload roundtrips", loaded.ok and _normalized(loaded.payload) == _normalized(payload))
	_check("first load does not claim recovery", not loaded.recovered)
	_check("UTC timestamp is explicit", loaded.saved_at.length() == 20 and loaded.saved_at.ends_with("Z"))
	var listed: Dictionary = store.list_slots()[1]
	_check("slot header reflects saved payload", listed.valid and listed.exists and listed.day == 3 and listed.card_count == 2 and listed.saved_at == loaded.saved_at)
	_check("second save rotates a previous valid backup", store.write_save("slot_1", _payload(4)).ok and FileAccess.file_exists(primary + ".bak"))
	var latest_text := FileAccess.get_file_as_string(primary)
	_write_text(primary, "{")
	loaded = store.read_save("slot_1")
	_check("corrupt main recovers the prior valid save", loaded.ok and loaded.recovered and int(loaded.payload.day.day) == 3)
	listed = store.list_slots()[1]
	_check("recovered header is marked and uses backup day", listed.valid and listed.recovered and listed.day == 3)
	_check("saving after recovery succeeds", store.write_save("slot_1", _payload(5)).ok)
	_check("corrupt main never replaces the valid backup", int(JSON.parse_string(FileAccess.get_file_as_string(primary + ".bak")).payload.day.day) == 3)
	_check("fresh saved main clears recovery flag", store.read_save("slot_1").ok and not store.read_save("slot_1").recovered)
	DirAccess.remove_absolute(primary)
	_check("missing main recovers known backup", store.read_save("slot_1").ok and store.read_save("slot_1").recovered)
	var future: Dictionary = JSON.parse_string(latest_text)
	future.schema = 999
	_write_text(primary, JSON.stringify(future))
	var future_hash := FileAccess.get_sha256(primary)
	_check("future main is not silently replaced by old backup", store.read_save("slot_1").error_key == "SAVE_UNSUPPORTED_VERSION")
	_check("future main is protected from writes", store.write_save("slot_1", _payload(6)).error_key == "SAVE_UNSUPPORTED_VERSION" and FileAccess.get_sha256(primary) == future_hash)
	_write_text(primary, latest_text)
	_write_text(primary + ".bak", JSON.stringify(future))
	_check("future backup is also protected from overwrite", store.write_save("slot_1", _payload(6)).error_key == "SAVE_UNSUPPORTED_VERSION" and FileAccess.get_sha256(primary) == latest_text.sha256_text())
	DirAccess.remove_absolute(primary + ".bak")
	var original_hash := FileAccess.get_sha256(primary)
	DirAccess.make_dir_absolute(primary + ".tmp")
	_check("failed temporary write preserves current save", store.write_save("slot_1", _payload(7)).error_key == "SAVE_WRITE_FAILED" and FileAccess.get_sha256(primary) == original_hash)
	DirAccess.remove_absolute(primary + ".tmp")
	_check("save succeeds after transient path failure", store.write_save("slot_1", _payload(7)).ok)
	var other := store.directory.path_join("slot_2.json")
	_check("isolated second slot writes", store.write_save("slot_2", _payload(8)).ok)
	var original_text := FileAccess.get_file_as_string(other)
	var corrupted: Dictionary = JSON.parse_string(original_text)
	corrupted.payload.day.day = 90
	_write_text(other, JSON.stringify(corrupted))
	_check("payload tampering fails checksum", store.read_save("slot_2").error_key == "SAVE_CORRUPT")
	corrupted = JSON.parse_string(original_text)
	corrupted.saved_at = "2001-01-01T00:00:00Z"
	_write_text(other, JSON.stringify(corrupted))
	_check("header tampering fails checksum", store.read_save("slot_2").error_key == "SAVE_CORRUPT")
	for invalid_text: String in ["[]", "null", "0", "{}", "{\"format\":\"other_game\",\"schema\":1}", "{\"format\":\"medieval_shop_romance\",\"schema\":true}", "{\"format\":\"medieval_shop_romance\",\"schema\":1,\"payload\":[]}"]:
		_write_text(other, invalid_text)
		_check("malformed envelope is rejected " + invalid_text, store.read_save("slot_2").error_key == "SAVE_CORRUPT")
	_write_text(other, "x".repeat(StoreScript.MAX_SAVE_BYTES + 1))
	_check("oversized read is bounded", store.read_save("slot_2").error_key == "SAVE_TOO_LARGE")
	_write_text(other, original_text)
	original_hash = FileAccess.get_sha256(other)
	var invalid_values: Array = [Vector2.ONE, PackedStringArray(["unsafe"]), NAN, INF, 9007199254740992, {1: "integer key"}]
	for invalid: Variant in invalid_values:
		_check("non-JSON data rejected type %d" % typeof(invalid), store.write_save("slot_2", {"value": invalid}).error_key == "SAVE_INVALID_DATA")
	var object := RefCounted.new()
	_check("objects are not serialized", store.write_save("slot_2", {"object": object}).error_key == "SAVE_INVALID_DATA")
	var recursive: Array = []
	recursive.append(recursive)
	_check("recursive containers are rejected without serialization", store.write_save("slot_2", {"cycle": recursive}).error_key == "SAVE_INVALID_DATA")
	recursive.clear()
	_check("invalid saves preserve previous bytes", FileAccess.get_sha256(other) == original_hash)
	_check("oversized payload is rejected before write", store.write_save("slot_2", {"text": "x".repeat(StoreScript.MAX_SAVE_BYTES)}).error_key == "SAVE_TOO_LARGE")
	_check("oversized payload leaves previous save intact", FileAccess.get_sha256(other) == original_hash)
	_check("empty JSON-safe payload allowed by generic store", store.write_save("slot_3", {}).ok and store.list_slots()[3].day == 0 and store.list_slots()[3].card_count == 0)
	_check("all successful writes consume staging files", not FileAccess.file_exists(primary + ".tmp") and not FileAccess.file_exists(primary + ".bak.tmp"))
	var blocked := test_root.path_join("blocked")
	_write_text(blocked, "not a directory")
	var blocked_store := StoreScript.new(blocked.path_join("saves"))
	_check("unwritable parent returns a save error", blocked_store.write_save("auto", _payload(1)).error_key == "SAVE_WRITE_FAILED")


func _test_settings() -> void:
	var path := test_root.path_join("settings.cfg")
	var settings := SettingsScript.new(path)
	var signals: Array[int] = []
	settings.changed.connect(func() -> void: signals.append(1))
	_check("missing settings load defaults successfully", settings.load_settings() and settings.values == SettingsScript.DEFAULTS)
	_check("default load does not create an unnecessary file", not FileAccess.file_exists(path))
	_check("required audio buses exist", AudioServer.get_bus_index("Master") >= 0 and AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0)
	_check("audio sub-buses route to Master", AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == &"Master" and AudioServer.get_bus_send(AudioServer.get_bus_index("SFX")) == &"Master")
	_check("initial master volume applied", is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Master")), 0.8))
	_check("valid master value persists and applies", settings.set_value("master_volume", 0.25) and is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.25))
	_check("mute applies to Master", settings.set_value("muted", true) and AudioServer.is_bus_mute(0))
	_check("mute preserves slider levels", is_equal_approx(float(settings.get_value("master_volume")), 0.25) and is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.25))
	_check("slider remains editable while muted", settings.set_value("master_volume", 0.35) and AudioServer.is_bus_mute(0) and is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.35))
	_check("music value applies to Music", settings.set_value("music_volume", 0.43) and is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.43))
	_check("effects value applies to SFX", settings.set_value("sfx_volume", 0.66) and is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("SFX")), 0.66))
	_check("language applies immediately", settings.set_value("locale", "en") and TranslationServer.get_locale() == "en")
	for mode: String in SettingsScript.WINDOW_MODES:
		_check("window mode persists headlessly " + mode, settings.set_value("window_mode", mode) and settings.get_value("window_mode") == mode)
	_check("unmute restores chosen level", settings.set_value("muted", false) and not AudioServer.is_bus_mute(0) and is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.35))
	var restored := SettingsScript.new(path)
	_check("preferences survive a new settings instance", restored.load_settings() and restored.values == settings.values)
	var original_hash := FileAccess.get_sha256(path)
	var before := settings.values.duplicate(true)
	var signal_count := signals.size()
	var invalid_cases := [
		["master_volume", -0.1], ["master_volume", 1.1], ["master_volume", true],
		["music_volume", "0.5"], ["sfx_volume", NAN], ["sfx_volume", INF],
		["locale", "ja"], ["locale", 4], ["window_mode", "maximized"],
		["muted", 1], ["unknown", 0.3],
	]
	for item: Array in invalid_cases:
		_check("invalid preference rejected " + str(item[0]), not settings.set_value(item[0], item[1]) and settings.error_key == "SETTINGS_INVALID_VALUE")
	_check("rejected values do not mutate preferences or disk", settings.values == before and FileAccess.get_sha256(path) == original_hash)
	_check("rejected values do not emit changed", signals.size() == signal_count)
	_check("unknown setting read is null", settings.get_value("unknown") == null)
	_check("subsequent success clears last error", settings.set_value("locale", "zh_CN") and settings.error_key.is_empty() and TranslationServer.get_locale() == "zh_CN")
	_check("zero volume is supported", settings.set_value("sfx_volume", 0) and is_zero_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("SFX")) ))
	var config := ConfigFile.new()
	config.set_value("settings", "master_volume", "wrong type")
	var invalid_path := test_root.path_join("invalid-settings.cfg")
	config.save(invalid_path)
	var invalid_settings := SettingsScript.new(invalid_path)
	_check("invalid stored type falls back to defaults with error", not invalid_settings.load_settings() and invalid_settings.error_key == "SETTINGS_INVALID_VALUE" and invalid_settings.values == SettingsScript.DEFAULTS)
	_check("invalid stored file is not rewritten on load", FileAccess.get_file_as_string(invalid_path).contains("wrong type"))
	_write_text(invalid_path, "")
	_check("empty settings return read error", not invalid_settings.load_settings() and invalid_settings.error_key == "SETTINGS_READ_FAILED")
	_write_text(invalid_path, "x".repeat(SettingsScript.MAX_CONFIG_BYTES + 1))
	_check("oversized settings are bounded", not invalid_settings.load_settings() and invalid_settings.error_key == "SETTINGS_READ_FAILED")
	var blocked_path := test_root.path_join("unwritable.cfg")
	DirAccess.make_dir_absolute(blocked_path)
	var blocked := SettingsScript.new(blocked_path)
	var volume_before := AudioServer.get_bus_volume_linear(0)
	_check("failed setting write reports error", not blocked.set_value("master_volume", 0.1) and blocked.error_key == "SETTINGS_WRITE_FAILED")
	_check("failed setting write does not change applied audio or values", blocked.values == SettingsScript.DEFAULTS and is_equal_approx(AudioServer.get_bus_volume_linear(0), volume_before))
	_check("settings staging file is removed", not FileAccess.file_exists(blocked_path + ".tmp") and not FileAccess.file_exists(path + ".tmp"))


func _payload(day: int) -> Dictionary:
	return {
		"day": {"day": day, "elapsed": 42.25},
		"table": {"cards": {
			"card_001": {"kind": "hero", "metadata": {}},
			"card_002": {"kind": "coin", "metadata": {"sample": "quote \" slash \\ line\nend"}},
		}, "stacks": []},
		"progress": {"recipes": ["recipe_001"], "npcs": {"npc_001": {"affinity": 1, "met": true, "extra": null}}},
	}


func _normalized(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _layout_count(layout: AudioBusLayout) -> int:
	var result := 0
	for property: Dictionary in layout.get_property_list():
		if str(property.name).begins_with("bus/") and str(property.name).ends_with("/name"):
			result += 1
	return result


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL " + label)
