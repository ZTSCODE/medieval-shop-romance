extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	if DisplayServer.get_name() != "headless":
		print("UI_SCALE_SETTINGS_SUITE requires --headless")
		quit(2)
		return
	var path := "res://work/ui-scale-settings-%d.cfg" % OS.get_process_id()
	var old_config := ConfigFile.new()
	old_config.set_value("settings", "locale", "en")
	old_config.set_value("settings", "master_volume", 0.35)
	old_config.set_value("future", "preserved", "untouched")
	old_config.save(path)
	var settings := GameSettings.new(path)
	var original_hash := FileAccess.get_sha256(path)
	_check("old config loads with auto scale", settings.load_settings() and settings.get_value("ui_scale") == "auto")
	_check("old config other preferences survive", settings.get_value("locale") == "en" and is_equal_approx(settings.get_value("master_volume"),0.35))
	_check("loading old config does not rewrite it", FileAccess.get_sha256(path) == original_hash)
	for legacy: String in UiScale.LEGACY_OPTIONS.slice(1):
		old_config.set_value("settings", "ui_scale", legacy)
		old_config.save(path)
		original_hash = FileAccess.get_sha256(path)
		_check("legacy manual scale capped to new maximum " + legacy, settings.load_settings() and settings.get_value("ui_scale") == "120")
		_check("migration remains read only " + legacy, FileAccess.get_sha256(path) == original_hash)
	for value: String in UiScale.OPTIONS:
		_check("valid scale saved " + value, settings.set_value("ui_scale", value))
		var reloaded := GameSettings.new(path)
		_check("new instance restores scale " + value, reloaded.load_settings() and reloaded.get_value("ui_scale") == value)
	var migrated := ConfigFile.new()
	migrated.load(path)
	_check("saved config identifies new scale semantics", migrated.get_value("meta", "ui_scale_version") == 2)
	_check("unknown config sections survive next save", migrated.get_value("future", "preserved") == "untouched")
	_check("other preferences survive migration and save", migrated.get_value("settings", "locale") == "en" and is_equal_approx(migrated.get_value("settings", "master_volume"), 0.35))
	var saved_hash := FileAccess.get_sha256(path)
	for value: Variant in ["150", "0", "", 1.0, 85, false]:
		_check("invalid scale rejected " + str(value), not settings.set_value("ui_scale", value))
	_check("invalid scale preserves config", FileAccess.get_sha256(path) == saved_hash)
	_check("new maximum equals old seventy five percent", is_equal_approx(UiScale.factor_for_pixels(Vector2i(1920,1080),"120"), 0.75))
	_check("new hundred maps to sixty two and half percent", is_equal_approx(UiScale.factor_for_pixels(Vector2i(1920,1080),"100"), 0.625))
	_check("auto 720 and 1080 use capped maximum", UiScale.factor_for_pixels(Vector2i(1280,720),"auto") == 0.75 and UiScale.factor_for_pixels(Vector2i(1920,1080),"auto") == 0.75)
	_check("auto 4k shrinks by twenty two percent from maximum", is_equal_approx(UiScale.factor_for_pixels(Vector2i(3840,2160),"auto"),0.585))
	_check("ultrawide uses height not horizontal pixel count", UiScale.factor_for_pixels(Vector2i(3840,1080),"auto") == 0.75)
	_check("manual scale independent of resolution", UiScale.factor_for_pixels(Vector2i(1280,720),"90") == UiScale.factor_for_pixels(Vector2i(3840,2160),"90"))
	var previous := 0.0
	for option: String in UiScale.OPTIONS.slice(1):
		var factor := UiScale.factor_for_pixels(Vector2i(1920,1080), option)
		_check("manual scale strictly increasing within cap " + option, factor > previous and factor <= UiScale.MAX_FACTOR)
		previous = factor
	print("UI scale settings checks: %d, failures: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, result: bool) -> void:
	checks += 1
	if not result:
		failures += 1
	print(("PASS " if result else "FAIL ") + label)
