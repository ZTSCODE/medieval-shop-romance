extends SceneTree

class ProfileApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

var app: Node
var results: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1672, 941)
	TranslationServer.set_locale("zh_CN")
	app = ProfileApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	await create_timer(1.0).timeout
	app._commit_new_journey("Profile")
	await create_timer(2.0).timeout
	print("PROFILE entries recipes=%d npcs=%d" % [app.journal.recipes_panel.entry_controls.size(), app.journal.npcs_panel.entry_controls.size()])
	if "--warm-edge" in OS.get_cmdline_user_args():
		var start := Time.get_ticks_usec()
		LegacyForestPaperStyle._texture("paper-light-edge-v2.png")
		print("PROFILE edge_preparation_ms=%.3f" % ((Time.get_ticks_usec() - start) / 1000.0))
	var pages := ["npcs", "recipes", "npcs", "recipes"] if "--reverse" in OS.get_cmdline_user_args() else ["recipes", "npcs", "recipes", "npcs"]
	for page: String in pages:
		await RenderingServer.frame_post_draw
		var start := Time.get_ticks_usec()
		app.journal.buttons[page].pressed.emit()
		var handler_us := Time.get_ticks_usec() - start
		var intervals: Array = []
		var last := start
		for frame in 12:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			intervals.append((now - last) / 1000.0)
			last = now
		var row := {"page": page, "handler_ms": handler_us / 1000.0, "frames_ms": intervals}
		results.append(row)
		print("PROFILE " + JSON.stringify(row))
		app.journal.close()
		await create_timer(0.4).timeout
	var output := "res://outputs/journal-profile-20260929/"
	DirAccess.make_dir_recursive_absolute(output)
	var suffix := "warm" if "--warm-edge" in OS.get_cmdline_user_args() else ("reverse" if "--reverse" in OS.get_cmdline_user_args() else "cold")
	var file := FileAccess.open(output + suffix + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	quit()
