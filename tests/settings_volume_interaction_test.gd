extends SceneTree

class MeasuredSettings extends GameSettings:
	var writes := 0
	var applies := 0
	var fail_writes := false
	func save_settings() -> bool:
		writes += 1
		if fail_writes:
			error_key = "SETTINGS_WRITE_FAILED"
			return false
		return super.save_settings()
	func apply_all() -> void:
		applies += 1
		super.apply_all()
	func legacy_volume(value: float) -> void:
		values.master_volume = value
		save_settings()
		apply_all()
		changed.emit()

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://work/volume-test-%d.cfg" % OS.get_process_id()
	var audio := AudioServer.generate_bus_layout()
	var settings := MeasuredSettings.new(path)
	settings.apply_all()
	var panel := SettingsPanel.new()
	panel.configure(settings)
	root.add_child(panel)
	panel.size = Vector2(960, 700)
	panel.select_category("audio")
	await process_frame
	var started := Time.get_ticks_usec()
	for i in 60:
		settings.legacy_volume(float(i + 1) / 100.0)
	var legacy_usec := Time.get_ticks_usec() - started
	settings.writes = 0
	settings.applies = 0
	var slider: HSlider = panel.volume_sliders.master_volume
	slider.drag_started.emit()
	started = Time.get_ticks_usec()
	for i in 60:
		slider.value = i + 2
	var preview_usec := Time.get_ticks_usec() - started
	_check("drag previews without disk writes", settings.writes == 0)
	_check("drag avoids global apply", settings.applies == 0)
	_check("audio bus updates before commit", is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.61))
	_check("persistent value waits for commit", is_equal_approx(settings.get_value("master_volume"), 0.6))
	slider.drag_ended.emit(true)
	_check("drag commits exactly once", settings.writes == 1)
	var config := ConfigFile.new()
	config.load(path)
	_check("final value persisted", is_equal_approx(config.get_value("settings", "master_volume"), 0.61))
	settings.writes = 0
	slider.value = 45
	slider.value = 46
	await create_timer(0.4).timeout
	_check("keyboard edits coalesce and persist", settings.writes == 1 and is_equal_approx(settings.get_value("master_volume"), 0.46))
	settings.writes = 0
	slider.value = 47
	panel.select_category("display")
	_check("category switch flushes", settings.writes == 1 and is_equal_approx(settings.get_value("master_volume"), 0.47))
	settings.fail_writes = true
	slider.drag_started.emit()
	slider.value = 12
	slider.drag_ended.emit(true)
	_check("failed save restores value", is_equal_approx(settings.get_value("master_volume"), 0.47))
	_check("failed save restores bus", is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.47))
	_check("failed save restores slider", slider.value == 47)
	_check("failed save preserves file", config.load(path) == OK and is_equal_approx(config.get_value("settings", "master_volume"), 0.47))
	settings.fail_writes = false
	slider.value = 52
	panel.hide()
	_check("hide flushes", is_equal_approx(settings.get_value("master_volume"), 0.52))
	slider.value = 53
	panel.free()
	_check("node exit flushes", is_equal_approx(settings.get_value("master_volume"), 0.53))
	AudioServer.set_bus_layout(audio)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("VOLUME_PROFILE old_60_steps_us=%d new_60_steps_us=%d" % [legacy_usec, preview_usec])
	print("SETTINGS_VOLUME_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print("%s %s" % ["PASS" if passed else "FAIL", label])
