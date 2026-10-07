extends SceneTree

# 新旅程必须能真的存下第一份自动存档（别的走查脚本都把 save_game 换成了空操作，所以这条路径单独查）。
# 存档写在隔离的走查目录（--flow-qa 时是 work/qa-profile-<进程号>），不碰玩家的存档。
# 运行：pwsh -File tools/run_hidden_capture.ps1 tests/new_journey_save_capture.gd
class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1672, 941)
	var app := PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	AudioServer.set_bus_mute(0, true)
	await create_timer(0.5).timeout
	var directory: String = app.save_store.directory
	_check("saves go to a folder named after the content generation", directory.get_file() == ContentCatalog.content_generation() and "qa-profile" in directory)
	app._start_new_journey()
	await create_timer(0.5).timeout
	_check("a new journey leaves the main menu", not app._at_main_menu and app.opening.stage == &"intro")
	_check("no save page is forced open", not app._menu_paused and not app._autosave_blocked)
	_check("the first automatic save is on disk", FileAccess.file_exists(directory.path_join("auto.json")))
	var read: Dictionary = app.save_store.read_save("auto")
	_check("and it reads back: %s" % [read.get("error_key", "")], read.get("ok", false))
	# 再开一次新旅程：要能覆盖刚才那份。
	app._commit_new_journey("Rowan")
	await create_timer(0.3).timeout
	_check("a second new journey overwrites it", app.identity.name == "Rowan" and not app._menu_paused and app.save_store.read_save("auto").get("ok", false))
	print("NEW_JOURNEY_SAVE failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
