extends SceneTree

# 开场剧情实机走查：文字页 → 取名 → 主角在雪线边的独白（桌上是“你”和那把种子）→ 黑刺李林上桌 → 对林子的犹豫
# → 新手目标 → 探索黑刺李林 → 信使和溪边小道上桌 → 与信使相遇（含两次选项），说完他先走 → 沿溪边小道走
# → 信使追上来、背风地出现 → 介绍背风地、互通姓名。
# 截图写入 outputs/opening-story/；不写玩家存档。运行：Godot --path . --script tests/opening_story_capture.gd -- --flow-qa
class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass
	func save_game(_slot: String, _notify: bool = true) -> Dictionary:
		return {"ok": true, "error_key": ""}

const THAW := "story.hero.thaw_edge"
const DOUBT := "story.hero.wood_doubt"
const EDGE := "story.messenger.edge"
const CATCH := "story.messenger.catch_up"
const OUTPUT := "res://outputs/opening-story/"

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
	TranslationServer.set_locale("en")
	app = PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	app.opening_overlay.film_enabled = false  # 这里走查逐页序幕；开场动画另有 opening_film_capture.gd
	await create_timer(0.5).timeout
	TranslationServer.set_locale("en")  # 游戏启动时会套用用户设置里的语言，这里再设一次。
	# 新旅程直接进入序幕，名字在序幕之后才问。
	app._start_new_journey()
	_check("new journey skips naming at the menu", not app.name_entry.visible and app.identity.name.is_empty())
	_check("opening starts on the first page", await _wait_until(func() -> bool: return app.opening.stage == &"intro" and app.opening_overlay.intro_visible, 5.0))
	# 等镜头从主菜单转到牌桌（过渡期间开场文字框是隐藏的）。
	await _wait_until(func() -> bool: return not app.table_stage.is_camera_transitioning(), 6.0)
	await create_timer(2.0).timeout
	await _shot("01-chronicle-1-en.png")
	var chronicle: Control = app.opening_overlay._chronicle
	_check("chronicle shows full screen", app.opening_overlay.is_chronicle_showing() and not app.opening_overlay.text_panel.visible)
	_check("chronicle text is left aligned under the plate", chronicle._text.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT and is_equal_approx(chronicle._text.position.x, chronicle._art_clip.position.x))
	var block_top: float = chronicle._art_clip.position.y
	var block_bottom: float = chronicle._text.get_rect().end.y
	_check("chronicle block is vertically centred", absf(block_top - (chronicle.size.y - block_bottom)) <= 4.0)
	TranslationServer.set_locale("zh_CN")
	await create_timer(2.0).timeout
	await _shot("02-chronicle-1-zh.png")
	for page in [2, 3, 4, 5]:
		app.opening_overlay.advance()
		await create_timer(2.0).timeout
		await _shot("%02d-chronicle-%d-zh.png" % [page + 1, page])
	app.opening_overlay.advance()
	await create_timer(0.8).timeout
	_check("name is asked right after the chronicle", app.name_entry.visible and not app.name_entry.cancel_button.visible)
	_check("nothing else shows while naming", not app.opening_overlay.visible and not app.dialogue.is_active())
	_check("time stands still while naming", app.get_tree().paused)
	await _shot("07-name-entry-zh.png")
	app._cancel_naming()
	_check("story naming cannot be cancelled", app.name_entry.visible)
	app._on_name_confirmed("Rowan")
	await create_timer(0.6).timeout
	_check("name kept", app.identity.name == "Rowan" and not app.name_entry.visible)
	# 一、雪线边：牌桌上只有主角，他自言自语。
	_check("first monologue starts by itself", await _wait_until(func() -> bool: return app.dialogue.story_id == THAW, 3.0))
	_check("the hero and the seed are on the table: %s" % [_kinds()], _kinds() == ["hero", "winter_seed"])
	_check("nobody is in the journal yet", app.progress.npcs.is_empty())
	_check("no tutorial hint during the monologue", app._tutorial_key.is_empty())
	await _settle_text()
	_check("the hero speaks, with nobody opposite", not app.dialogue.presentation_info().narrator and app.dialogue_overlay.hero_portrait.visible and not app.dialogue_overlay.npc_portrait.visible)
	_check("his line is on screen in Chinese", app.dialogue_overlay.story_label.text == app.tr("DLG_HERO_THAW_01") and not app.dialogue_overlay.story_label.text.begins_with("DLG_"))
	await _shot("08-thaw-monologue-zh.png")
	TranslationServer.set_locale("en")
	await _step_until(func() -> bool: return String(app.dialogue.current_line().get("text_key", "")) == "DLG_HERO_THAW_08")
	await _shot("09-thaw-snow-gives-out-en.png")
	await _step_until(func() -> bool: return String(app.dialogue.current_line().get("text_key", "")) == "DLG_HERO_THAW_09")
	app.dialogue.advance()
	# 二、林子上桌：第一张出现的卡，从屏幕右边滑进来。
	_check("the wood arrives when he stops talking: %s" % [_kinds()], _kinds() == ["first_forest", "hero", "winter_seed"])
	_check("the wood is on its way in", await _wait_until(func() -> bool: return not app.board.flights.is_empty(), 2.0))
	await _wait_until(func() -> bool: return not app.dialogue_overlay.is_presenting(), 3.0)
	await create_timer(0.25).timeout
	await _shot("10-wood-arriving-en.png")
	_check("the second monologue waits for the card to land", not app.dialogue.is_active())
	await _wait_until(func() -> bool: return app.board.flights.is_empty(), 2.0)
	_check("no hint or goals while the next lines are due", app._tutorial_key.is_empty() and app._opening_scene_pending())
	_check("second monologue starts by itself", await _wait_until(func() -> bool: return app.dialogue.story_id == DOUBT, 4.0))
	_check("the wood has landed beside him", app.board.flights.is_empty())
	await _settle_text()
	await _shot("11-doubt-monologue-en.png")
	TranslationServer.set_locale("zh_CN")
	await _step_until(func() -> bool: return String(app.dialogue.current_line().get("text_key", "")) == "DLG_HERO_DOUBT_08")
	await _shot("12-doubt-do-i-chance-it-zh.png")
	await _step_until(func() -> bool: return not app.dialogue.is_active())
	# 三、新手目标：基础操作，加上把“你”拖到林子上。
	await create_timer(1.6).timeout
	_check("walk-the-wood hint shown", app._tutorial_key == "OPENING_HINT_WALK_WOOD")
	var stage: Dictionary = app.onboarding.current_stage()
	var goal_ids: Array[String] = []
	for goal: Dictionary in stage.get("goals", []):
		goal_ids.append(goal.id)
	_check("first goals are the basics and the wood: %s" % [goal_ids], goal_ids == ["pan_table", "zoom_table", "drag_card", "walk_wood"])
	_check("nothing is ticked yet and nobody else has turned up", app.onboarding.completed.is_empty() and _kinds() == ["first_forest", "hero", "winter_seed"])
	await _shot("13-board-goals-zh.png")
	var panel_rect: Rect2 = app.onboarding_panel.panel.get_global_rect()
	_check("the four goals fit above the time axis", panel_rect.position.y >= 0.0 and panel_rect.end.y <= app.overlay.day_progress.get_global_rect().position.y)
	TranslationServer.set_locale("en")
	await create_timer(0.5).timeout
	await _shot("13b-board-goals-en.png")
	var view := Rect2(Vector2.ZERO, Vector2(root.size))
	var all_in_view := true
	for kind: StringName in [&"hero", &"first_forest", &"winter_seed"]:
		var corner: Vector2 = app.board.camera.to_screen(app.board.state.card_position(_card_of(kind)))
		all_in_view = all_in_view and view.grow(-20.0).encloses(Rect2(corner, TableState.CARD_SIZE * app.board.camera.zoom))
	_check("the seed, the hero and the wood are all fully on screen", all_in_view)
	# 基础操作（这里直接上报镜头手势；拖卡用牌桌自己的信号）。
	app._on_camera_gesture(&"zoom", 1.0)
	app._on_camera_gesture(&"pan", 100000.0)
	app.board.card_dragged.emit(false)
	_check("basics tick off, the wood still to do", app.onboarding.is_goal_complete("pan_table") and app.onboarding.is_goal_complete("zoom_table") and app.onboarding.is_goal_complete("drag_card") and app.onboarding.stage_index == 0)
	await create_timer(2.2).timeout
	await _shot("13c-basics-ticked-en.png")
	_stack(&"hero", &"first_forest")
	await create_timer(3.0).timeout
	await _shot("14-exploring-en.png")
	_check("exploration completes", await _wait_until(func() -> bool: return app.opening.stage == &"complete", 12.0))
	_check("onboarding walk goal done", app.onboarding.is_goal_complete("walk_wood"))
	# 四、林中：信使和溪边小道上桌；要玩家自己去找他说话。
	_check("the messenger and the streamside path turn up: %s" % [_kinds()], _kinds() == ["hero", "messenger", "stream_path", "winter_seed"])
	await create_timer(2.2).timeout
	_check("nothing starts by itself", not app.dialogue.is_active() and not app._opening_scene_pending())
	_check("meet-the-messenger hint shown", app._tutorial_key == "OPENING_HINT_MEET_MESSENGER")
	_check("messenger recorded in journal", app.progress.npcs.has("npc.messenger"))
	await _shot("15-messenger-and-path-en.png")
	# 信使还在桌上时，小道走不了。
	_stack(&"hero", &"stream_path")
	await create_timer(1.5).timeout
	_check("the path waits while the messenger stands there", app.exploration.work_progress().is_empty() and not _card_of(&"stream_path").is_empty())
	app.board.state.take_from(_card_of(&"hero"), false)
	app.board.refresh_content()
	_stack(&"hero", &"messenger")
	app._on_dialogue_requested("npc.messenger")
	_check("the meeting starts on his card", await _wait_until(func() -> bool: return app.dialogue.story_id == EDGE, 3.0))
	_check("the meeting is narrated in the dialogue box", app.dialogue.presentation_info().narrator and app.dialogue_overlay.story_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT)
	await _settle_text()
	await _shot("16-edge-in-the-wood-en.png")
	_check("messenger unseen before he steps out", not app.dialogue_overlay.npc_portrait.visible)
	TranslationServer.set_locale("zh_CN")
	await _step_until(func() -> bool: return app.dialogue.awaiting_choice())
	await _shot("17-edge-first-choice-zh.png")
	app.dialogue_overlay._choose("stone")
	await _settle_text()
	await _shot("18-edge-stone-zh.png")
	TranslationServer.set_locale("en")
	await _step_until(func() -> bool: return String(app.dialogue.current_line().get("text_key", "")) == "DLG_MESSENGER_EDGE_26")
	await _shot("19-edge-recognise-en.png")
	_check("messenger visible once he steps out", app.dialogue_overlay.npc_portrait.visible)
	await _step_until(func() -> bool: return app.dialogue.awaiting_choice())
	app.dialogue_overlay._choose("not_sure")
	await _settle_text()
	await _step_until(func() -> bool: return not app.dialogue.is_active())
	await create_timer(1.6).timeout
	_check("the messenger's card leaves after the meeting: %s" % [_kinds()], _kinds() == ["hero", "stream_path", "winter_seed"])
	_check("onboarding messenger goal done", app.onboarding.is_goal_complete("meet_messenger"))
	_check("follow-the-stream hint shown", app._tutorial_key == "OPENING_HINT_FOLLOW_STREAM")
	await _shot("20-messenger-gone-en.png")
	# 五、沿溪边小道走：信使追上来，背风地出现。
	TranslationServer.set_locale("zh_CN")
	_stack(&"hero", &"stream_path")
	await create_timer(2.5).timeout
	_check("walking the path shows progress", app.exploration.work_progress().size() == 1)
	await _shot("21-walking-stream-zh.png")
	_check("the path leads to the Lee and he catches up: %s" % [_kinds()], await _wait_until(func() -> bool: return _kinds() == ["hero", "messenger", "the_lee", "winter_seed"], 10.0))
	await create_timer(2.0).timeout
	_check("onboarding path goal done", app.onboarding.is_goal_complete("follow_stream"))
	_check("catch-up hint shown", app._tutorial_key == "OPENING_HINT_CATCH_UP")
	await _shot("22-the-lee-in-sight-zh.png")
	_stack(&"hero", &"messenger")
	app._on_dialogue_requested("npc.messenger")
	_check("the catch-up talk starts", await _wait_until(func() -> bool: return app.dialogue.story_id == CATCH, 3.0))
	await _settle_text()
	await _shot("23-catch-up-start-zh.png")
	await _step_until(func() -> bool: return app.dialogue.awaiting_choice())
	await _shot("24-names-choice-zh.png")
	TranslationServer.set_locale("en")
	await create_timer(0.4).timeout
	await _shot("24b-names-choice-en.png")
	app.dialogue_overlay._choose("tell")
	await _settle_text()
	await _shot("25-names-told-en.png")
	await _step_until(func() -> bool: return not app.dialogue.is_active())
	await create_timer(1.8).timeout
	_check("he stays, with the Lee and the seed on the table: %s" % [_kinds()], _kinds() == ["hero", "messenger", "the_lee", "winter_seed"])
	_check("onboarding Lee goal done and the stage is finished", app.onboarding.is_goal_complete("hear_lee") and app.onboarding.stage_index == 2)
	_check("no hint afterwards", app._tutorial_key.is_empty())
	await _shot("26-end-of-opening-en.png")
	var snapshot: Dictionary = app._capture_session()
	_check("final state saves and loads", GameSnapshot.decode(JSON.parse_string(JSON.stringify(snapshot))).ok)
	print("OPENING_STORY_CAPTURE failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func _stack(first: StringName, second: StringName) -> void:
	app.board.state.merge(app.board.state.stack_for(_card_of(first)), app.board.state.stack_for(_card_of(second)))
	app.board.refresh_content()


func _kinds() -> Array[String]:
	var kinds: Array[String] = []
	for id: String in app.board.state.cards:
		kinds.append(String(app.board.state.card_kind(id)))
	kinds.sort()
	return kinds


func _card_of(kind: StringName) -> String:
	for id: String in app.board.state.cards:
		if app.board.state.card_kind(id) == kind:
			return id
	return ""


func _settle_text() -> void:
	await create_timer(0.45).timeout
	app.dialogue_overlay._characters = 100000.0
	await create_timer(0.3).timeout


func _step_until(done: Callable) -> void:
	var guard := 0
	while not done.call() and guard < 120 and app.dialogue.is_active():
		guard += 1
		if app.dialogue.awaiting_choice():
			app.dialogue.choose(String(app.dialogue.presentation_info().choices[0].id))
		else:
			app.dialogue.advance()
		await create_timer(0.05).timeout
	await _settle_text()


func _wait_until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return bool(predicate.call())


func _shot(file_name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + file_name))


func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
