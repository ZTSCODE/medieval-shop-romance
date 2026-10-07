extends SceneTree

# 开场动画实机走查：新旅程 → 动画全屏播放（英文、中文字幕各截一张）→ 点“跳过” → 进入取名。
# 截图写入 outputs/opening-film-qa/；不写玩家存档。
# 运行：pwsh -File tools/run_hidden_capture.ps1 tests/opening_film_capture.gd
class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass
	func save_game(_slot: String, _notify: bool = true) -> Dictionary:
		return {"ok": true, "error_key": ""}

const OUTPUT := "res://outputs/opening-film-qa/"

var app: Node
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	var output_dir := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_dir)
	for old: String in DirAccess.get_files_at(output_dir):
		DirAccess.remove_absolute(output_dir.path_join(old))
	root.size = Vector2i(1672, 941)
	app = PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	AudioServer.set_bus_mute(0, true)  # 走查不出声
	await create_timer(0.5).timeout
	TranslationServer.set_locale("en")
	app._start_new_journey()
	var overlay: OpeningOverlay = app.opening_overlay
	_check("the prologue starts as the film", await _wait_until(func() -> bool: return app.opening.stage == &"intro" and overlay.is_film_showing(), 8.0))
	var film: Control = overlay._film
	_check("the page-by-page prologue is hidden", not overlay.text_panel.visible and not overlay._chronicle.is_showing())
	_check("the film is playing", await _wait_until(func() -> bool: return film.playback_seconds() > 1.5, 20.0))
	_check("the picture keeps its shape inside the window", absf(film._player.size.x / film._player.size.y - film._aspect) < 0.01 and film._player.size.x <= film.size.x + 1.0 and film._player.size.y <= film.size.y + 1.0)
	_check("the skip button has appeared", film._skip.visible and film._skip.text == "Hold to skip")
	await _shot("01-film-caption-en.png")
	_check("an English caption is on screen", film._caption.text == tr("OPENING_FILM_LINE_01"))
	await create_timer(1.2).timeout
	await _shot("01b-film-3s.png")
	var from_position: float = film.playback_seconds()
	var from_clock := Time.get_ticks_msec()
	await create_timer(4.0).timeout
	var rate: float = (film.playback_seconds() - from_position) / ((Time.get_ticks_msec() - from_clock) / 1000.0)
	print("playback rate %.2f, fps %.0f" % [rate, Engine.get_frames_per_second()])
	_check("the film plays at normal speed", rate > 0.93 and rate < 1.07)
	overlay.advance()
	await create_timer(0.3).timeout
	_check("Enter or a click does not page through the film", app.opening.stage == &"intro" and app.opening.intro_index == 0)
	_check("a later caption follows the narration", await _wait_until(func() -> bool: return film.playback_seconds() > 7.0, 20.0))
	TranslationServer.set_locale("zh_CN")
	await create_timer(0.4).timeout
	await _shot("02-film-caption-zh.png")
	_check("captions follow the language", film._skip.text == "长按跳过" and film._caption.text in [tr("OPENING_FILM_LINE_03"), tr("OPENING_FILM_LINE_04")] and not film._caption.text.begins_with("OPENING_"))
	app.set_game_paused(true)
	await create_timer(0.3).timeout
	var held: float = film.playback_seconds()
	await create_timer(0.8).timeout
	_check("the film pauses with the menu", absf(film.playback_seconds() - held) < 0.1)
	app.set_game_paused(false)
	await create_timer(0.5).timeout
	# 结尾浮现的游戏名：直接跳到最后一个镜头看（跳不过去就把出现时间挪到现在，只验画面）。
	film._player.stream_position = 180.4
	await create_timer(0.5).timeout
	if film.playback_seconds() < 179.0:
		print("seek not supported here; showing the title at the current time instead")
		film._title_start = film.playback_seconds()
	else:
		await _wait_until(func() -> bool: return film.playback_seconds() > 182.3, 6.0)
		_check("the name is rising while the last shot is still on screen", film._title.modulate.a > 0.5 and film._title.modulate.a < 1.0)
		await _shot("03a-title-rising-over-last-shot.png")
	await create_timer(2.0).timeout
	_check("the game's name has risen over the last shot", film._title.modulate.a > 0.95 and film._title.text == "融雪之前")
	await _shot("03-title-zh.png")
	TranslationServer.set_locale("en")
	await create_timer(0.4).timeout
	_check("the name follows the language", film._title.text == "Before the Thaw")
	await _shot("04-title-en.png")
	if film.playback_seconds() > 150.0:
		film._player.stream_position = 30.0   # 回到片中，免得接下来几秒里片子自己播完
		await create_timer(0.8).timeout
	# 跳过要按住：点一下不算。
	# 输入事件用窗口坐标：界面有整体缩放，要把按钮中心换算过去。
	var at: Vector2 = root.get_final_transform() * (film._skip.get_global_transform_with_canvas() * (film._skip.size * 0.5))
	await _mouse(at, true)
	await create_timer(0.3).timeout
	await _mouse(at, false)
	await create_timer(0.8).timeout
	_check("a short click does not skip", app.opening.stage == &"intro" and overlay.is_film_showing())
	await _mouse(at, true)
	await create_timer(0.6).timeout
	_check("holding fills the bar", film._skip_progress > 0.3 and film._skip_progress < 1.0 and film._skip_bar.visible)
	await _shot("05-skip-held.png")
	_check("holding to the end skips the prologue", await _wait_until(func() -> bool: return app.opening.stage != &"intro", 3.0))
	await _mouse(at, false)
	_check("the film is gone", await _wait_until(func() -> bool: return not overlay.is_film_showing(), 2.0))
	_check("naming follows, as after the pages", await _wait_until(func() -> bool: return app.name_entry.visible, 4.0))
	await create_timer(1.0).timeout
	await _shot("06-after-skip-naming.png")
	print("OPENING_FILM_CAPTURE failures: %d" % failures)
	quit(0 if failures == 0 else 1)


func _wait_until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return bool(predicate.call())


func _mouse(at: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await process_frame
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = pressed
	button.position = at
	button.global_position = at
	Input.parse_input_event(button)
	await process_frame


func _shot(file_name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + file_name))


func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
