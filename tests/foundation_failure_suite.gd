extends SceneTree

class TestApp:
	extends "res://scripts/table_app.gd"

	func _run_qa(_path: String) -> void:
		pass

var checks := 0
var failures := 0
var child_checks := 0
var app: TestApp
var report_path := ""
var child_mode := ""


func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or "--qa" not in OS.get_cmdline_user_args():
		print("FOUNDATION_FAILURE_SUITE requires --headless and -- --qa")
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--failure-child="):
			child_mode = argument.trim_prefix("--failure-child=")
		elif argument.begins_with("--failure-report="):
			report_path = argument.trim_prefix("--failure-report=")
	create_timer(25.0, true).timeout.connect(func() -> void:
		print("FAIL foundation failure suite watchdog expired")
		quit(1)
	)
	_run.call_deferred()


func _run() -> void:
	app = TestApp.new()
	root.add_child(app)
	app.set_process(false)
	app.board.sound.enabled = false
	app.set_game_paused(true)
	var work_root := ProjectSettings.globalize_path("res://work").simplify_path().replace("\\", "/") + "/"
	var save_directory := app.save_store.directory.replace("\\", "/")
	if not app.qa_mode or not save_directory.begins_with(work_root):
		print("FAIL test profile is not isolated under work")
		quit(2)
		return
	if not report_path.is_empty() and not report_path.replace("\\", "/").begins_with(work_root):
		print("FAIL report path is not isolated under work")
		quit(2)
		return
	if child_mode == "exit_retry":
		await _exit_retry_child()
		return
	if child_mode == "settings_failure":
		await _settings_failure_child()
		return
	_test_transient_failure()
	_test_future_version_protection()
	_run_child("exit_retry")
	_run_child("settings_failure")
	print("FOUNDATION_FAILURE_SUITE: %d checks, %d child checks, %d failures" % [checks, child_checks, failures])
	quit(0 if failures == 0 else 1)


func _test_transient_failure() -> void:
	_check("initial automatic save succeeds", app.save_game("auto", false).ok)
	var primary := app.save_store.directory.path_join("auto.json")
	var previous_hash := FileAccess.get_sha256(primary)
	app.day_cycle.advance(2.5)
	var temporary := primary + ".tmp"
	_check("temporary write failure fixture is created", DirAccess.make_dir_absolute(temporary) == OK)
	_trigger_autosave()
	_check("automatic write failure preserves the previous save", FileAccess.get_sha256(primary) == previous_hash)
	_check("automatic write failure pauses repeated attempts", app._autosave_blocked and paused)
	_check("automatic write failure is visible on the saves page", app.overlay.current_page == "saves" and app.overlay._status_key == "SAVE_WRITE_FAILED" and app.overlay._status_label.is_visible_in_tree())
	_check("temporary failure fixture can be repaired", DirAccess.remove_absolute(temporary) == OK)
	app.day_cycle.advance(3.0)
	_check("manual save succeeds after the disk path recovers", app.save_game("slot_1", false).ok)
	_check("successful manual save resumes automatic saves", not app._autosave_blocked and app._startup_save_error.is_empty())
	app.day_cycle.advance(1.0)
	_trigger_autosave()
	var current := app.save_store.read_save("auto")
	_check("resumed automatic save writes new progress", current.ok and current.payload.day.elapsed == app.day_cycle.elapsed and FileAccess.get_sha256(primary) != previous_hash)
	_check("automatic saving stays enabled after recovery", not app._autosave_blocked)


func _test_future_version_protection() -> void:
	var compatible := GameSnapshot.capture(app.board.state, app.shop, app.day_cycle, app.board.camera, app.progress)
	_check("a compatible manual restore point is available", app.save_game("slot_1", false).ok)
	var future := compatible.duplicate(true)
	future.state_version = GameSnapshot.STATE_VERSION + 1
	var generic := SaveStore.new(app.save_store.directory)
	_check("generic writer can create future-version fixture", generic.write_save("auto", future).ok and generic.write_save("auto", future).ok)
	var primary := app.save_store.directory.path_join("auto.json")
	var backup := primary + ".bak"
	var primary_hash := FileAccess.get_sha256(primary)
	var backup_hash := FileAccess.get_sha256(backup)
	app._restore_automatic_save()
	_check("startup detects unsupported game-state version", app._startup_save_error == "SAVE_UNSUPPORTED_VERSION" and app._autosave_blocked)
	_check("startup failure leaves the current session intact", _canonical(GameSnapshot.capture(app.board.state, app.shop, app.day_cycle, app.board.camera, app.progress)) == _canonical(compatible))
	_check("startup failure appears on a visible saves page", app.overlay.current_page == "saves" and app.overlay._status_key == "SAVE_UNSUPPORTED_VERSION" and app.overlay._status_label.is_visible_in_tree())
	_check("manual save does not authorize replacement of bad startup data", app.save_game("slot_2", false).ok and not app._startup_save_error.is_empty() and app._autosave_blocked)
	_check("explicit compatible load can resume the session", app.load_game("slot_1").ok and app._startup_save_error.is_empty() and not app._autosave_blocked)
	app.day_cycle.advance(1.0)
	_trigger_autosave()
	_check("future auto target remains protected after compatible load", app._autosave_blocked and app.overlay._status_key == "SAVE_UNSUPPORTED_VERSION")
	_check("future main and backup remain byte-identical", FileAccess.get_sha256(primary) == primary_hash and FileAccess.get_sha256(backup) == backup_hash)
	var manual_attempt := app.save_game("auto", false)
	_check("explicit write API also protects future target", not manual_attempt.ok and manual_attempt.error_key == "SAVE_UNSUPPORTED_VERSION" and FileAccess.get_sha256(primary) == primary_hash and FileAccess.get_sha256(backup) == backup_hash)
	var unknown_content := compatible.duplicate(true)
	var first_card: String = unknown_content.table.cards.keys()[0]
	unknown_content.table.cards[first_card].definition_id = "card.future_unavailable"
	_check("generic writer creates unknown-content fixture", generic.write_save("slot_3", unknown_content).ok)
	var unknown_path := app.save_store.directory.path_join("slot_3.json")
	var unknown_hash := FileAccess.get_sha256(unknown_path)
	var unknown_write := app.save_game("slot_3", false)
	_check("unknown content IDs cannot be overwritten by older game", not unknown_write.ok and unknown_write.error_key == "SAVE_UNSUPPORTED_VERSION" and FileAccess.get_sha256(unknown_path) == unknown_hash)
	var listed: Dictionary = app.save_store.list_slots()[3]
	_check("unknown-content slot is not offered as compatible", listed.exists and not listed.valid and listed.error_key == "SAVE_UNSUPPORTED_VERSION")


func _exit_retry_child() -> void:
	_check("exit fixture writes an initial save", app.save_game("auto", false).ok)
	var primary := app.save_store.directory.path_join("auto.json")
	var temporary := primary + ".tmp"
	app.day_cycle.advance(5.5)
	_check("exit fixture blocks temporary writes", DirAccess.make_dir_absolute(temporary) == OK)
	_trigger_autosave()
	_check("exit fixture has a transient autosave failure", app._autosave_blocked)
	_check("exit fixture repairs the path without reloading", DirAccess.remove_absolute(temporary) == OK)
	app.day_cycle.advance(1.0)
	app._quit_game()
	var saved := app.save_store.read_save("auto")
	_check("quit retries and saves current progress", saved.ok and saved.payload.day.elapsed == app.day_cycle.elapsed)
	_check("successful quit retry clears the temporary block", not app._autosave_blocked)
	_write_report("exit_retry_requested")
	print("FOUNDATION_EXIT_CHILD: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		quit(1)
		return
	await create_timer(2.0, true).timeout
	print("FAIL successful app quit did not terminate its process")
	quit(1)


func _settings_failure_child() -> void:
	var settings_path := app.save_store.directory.get_base_dir().path_join("settings.cfg")
	_check("settings fixture profile directory exists", DirAccess.make_dir_recursive_absolute(settings_path.get_base_dir()) == OK)
	_check("settings target is blocked without affecting saves", DirAccess.make_dir_absolute(settings_path) == OK)
	app.day_cycle.advance(7.75)
	app._quit_game()
	await process_frame
	_check("settings write failure keeps the app running and paused", is_instance_valid(app) and paused)
	_check("settings write error is shown on the visible settings page", app.settings.error_key == "SETTINGS_WRITE_FAILED" and app.overlay.current_page == "settings" and app.overlay._status_key == "SETTINGS_WRITE_FAILED" and app.overlay._status_label.is_visible_in_tree())
	_check("settings failure requires explicit exit confirmation", app.overlay.confirmation_dialog.visible and app.overlay._pending_action == "quit_without_save")
	var saved := app.save_store.read_save("auto")
	_check("game progress was saved despite independent settings failure", saved.ok and saved.payload.day.elapsed == app.day_cycle.elapsed)
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		await process_frame
		var dialog: ConfirmationDialog = app.overlay.confirmation_dialog
		_check("exit failure title is localized in " + locale, not dialog.title.is_empty() and dialog.title != "QUIT_SAVE_FAILED_TITLE")
		_check("exit failure explanation is localized in " + locale, not dialog.dialog_text.is_empty() and dialog.dialog_text != "QUIT_SAVE_FAILED_BODY")
		_check("explicit discard action is localized in " + locale, not dialog.ok_button_text.is_empty() and dialog.ok_button_text != "QUIT_WITHOUT_SAVE")
	_write_report("settings_failure_intercepted")
	print("FOUNDATION_SETTINGS_CHILD: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _run_child(mode: String) -> void:
	var child_directory := app.save_store.directory.get_base_dir().path_join("failure-child-" + mode)
	var child_report := child_directory.path_join("report.json")
	var arguments := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "tests/foundation_failure_suite.gd", "--", "--qa",
		"--qa-dir=" + child_directory,
		"--failure-child=" + mode,
		"--failure-report=" + child_report,
	])
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), arguments, output, true)
	_check("child process exits cleanly for " + mode, exit_code == 0)
	var engine_errors := false
	for text: Variant in output:
		engine_errors = engine_errors or str(text).contains("ERROR:")
	_check("child reports no engine errors for " + mode, not engine_errors)
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(child_report)) if FileAccess.file_exists(child_report) else null
	_check("child reached its assertions for " + mode, report is Dictionary and report.get("failures", -1) == 0 and int(report.get("checks", 0)) >= 6)
	if report is Dictionary:
		child_checks += int(report.get("checks", 0))
		var expected := "exit_retry_requested" if mode == "exit_retry" else "settings_failure_intercepted"
		_check("child confirms expected quit behavior for " + mode, report.get("phase") == expected)
	if exit_code != 0 or engine_errors or not report is Dictionary:
		for text: Variant in output:
			print(str(text))


func _trigger_autosave() -> void:
	app.autosave_enabled = true
	app._autosave_pending = true
	app._process(0.0)


func _write_report(phase: String) -> void:
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"phase": phase, "checks": checks, "failures": failures}))
		file.close()


func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL " + label)
