extends SceneTree

# 运行时验证新手目标栏：登场时机、勾选动画、阶段切换、遮挡与离场；截图写入 outputs。
class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass
	func save_game(_slot: String, _notify: bool = true) -> Dictionary:
		return {"ok": true, "error_key": ""}

var app: Node
var failures := 0
const OUTPUT := "res://outputs/onboarding-goals/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1672, 941)
	TranslationServer.set_locale("zh_CN")
	app = PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	var panel: OnboardingGoalPanel = app.onboarding_panel
	await create_timer(0.5).timeout
	_check("hidden on main menu", not panel.is_shown())
	app._commit_new_journey("QA")
	await create_timer(0.3).timeout
	_check("waits before appearing", not panel.is_shown())
	_check("appears in game", await _wait_until(panel.is_shown, 6.0))
	await create_timer(0.3).timeout
	await _shot("01-entering.png")
	await _wait_until(func() -> bool: return not panel._busy, 3.0)
	await create_timer(0.3).timeout
	await _shot("02-first-stage.png")
	var rect := panel.panel.get_global_rect()
	var column: Rect2 = app.overlay.day_progress.get_global_rect()
	_check("sits above time axis", rect.end.y <= column.position.y and rect.position.y >= 0.0)
	_check("right edge aligned with time axis", absf(rect.end.x - column.end.x) < 2.0)
	_check("blocks board pointer", app._pointer_blocked(rect.get_center()))
	app._on_camera_gesture(&"pan", 200.0)
	await create_timer(0.28).timeout
	await _shot("03-checking.png")
	_check("pan row checked", await _wait_until(func() -> bool: return not panel._busy and panel.rows[0].done_shown, 3.0))
	app._on_camera_gesture(&"zoom", 1.0)
	await _wait_until(func() -> bool: return not panel._busy, 3.0)
	app.overlay.focus_hero_requested.emit()
	await _wait_until(func() -> bool: return panel._seal_t >= 0.98, 4.0)
	await create_timer(0.2).timeout
	await _shot("04-stage-seal.png")
	_check("second stage displayed", await _wait_until(func() -> bool: return panel.displayed_stage == 1 and not panel._busy, 5.0))
	await _shot("05-second-stage.png")
	app.set_game_paused(true)
	await create_timer(0.4).timeout
	_check("hidden while paused", not panel.is_shown() and not panel.panel.visible)
	app.set_game_paused(false)
	await create_timer(0.6).timeout
	_check("returns after pause", panel.is_shown())
	app.cycle_time_mode()
	await _wait_until(func() -> bool: return not panel._busy, 3.0)
	app._toggle_journal("recipes")
	await create_timer(0.4).timeout
	_check("hidden while journal open", not panel.is_shown())
	app._toggle_journal("npcs")
	app.journal.close()
	_check("model finished", app.onboarding.is_finished())
	_check("panel replays after journal closes", await _wait_until(panel.is_shown, 2.0))
	await _wait_until(func() -> bool: return panel._seal_t >= 0.98, 5.0)
	await create_timer(0.2).timeout
	await _shot("06-all-done.png")
	_check("panel leaves after finishing", await _wait_until(func() -> bool: return not panel.is_shown() and not panel.panel.visible, 5.0))
	var finished_save: Dictionary = app._capture_session()
	_check("save carries onboarding progress", finished_save.get("onboarding", {}).get("completed", []).size() == 6)
	var partial := OnboardingGoals.new()
	partial.report(&"camera_panned")
	var partial_save := finished_save.duplicate(true)
	partial_save["onboarding"] = partial.to_data()
	var legacy_save := finished_save.duplicate(true)
	legacy_save.erase("onboarding")
	app._commit_new_journey("QA2")
	_check("new journey restarts goals", app.onboarding.stage_index == 0 and app.onboarding.completed.is_empty())
	_check("panel returns on new journey", await _wait_until(func() -> bool: return panel.is_shown() and not panel._busy, 8.0))
	app.apply_snapshot(GameSnapshot.decode(finished_save))
	await create_timer(1.4).timeout
	_check("loading finished save keeps panel away", app.onboarding.is_finished() and not panel.is_shown())
	app.apply_snapshot(GameSnapshot.decode(partial_save))
	# 读档后立即比对，避免窗口收到真实鼠标输入时把后续目标也勾上。
	_check("partial save restored", app.onboarding.is_goal_complete("pan_table") and app.onboarding.completed.size() == 1)
	_check("restored goal shown as checked", await _wait_until(func() -> bool: return panel.is_shown() and not panel._busy, 6.0) and panel.rows[0].done_shown)
	await _shot("09-partial-save.png")
	var legacy_decoded := GameSnapshot.decode(legacy_save)
	_check("old save without field still loads", legacy_decoded.ok)
	app.apply_snapshot(legacy_decoded)
	_check("old save starts goals fresh", app.onboarding.stage_index == 0 and app.onboarding.completed.is_empty())
	root.size = Vector2i(960, 640)
	await _wait_until(func() -> bool: return panel.is_shown() and not panel._busy, 5.0)
	await create_timer(0.2).timeout
	var small := panel.panel.get_global_rect()
	print("small rect=%s viewport=%s column=%s" % [small, root.get_visible_rect(), app.overlay.day_progress.get_global_rect()])
	_check("small window inside viewport", root.get_visible_rect().encloses(small) and small.end.y <= app.overlay.day_progress.get_global_rect().position.y)
	await _shot("07-small-window.png")
	TranslationServer.set_locale("en")
	await create_timer(0.4).timeout
	await _shot("08-english.png")
	print(app.onboarding.debug_text())
	print("ONBOARDING_PANEL failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return bool(condition.call())


func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check("capture " + filename, root.get_texture().get_image().save_png(OUTPUT + filename) == OK)
