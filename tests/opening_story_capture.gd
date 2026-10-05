extends SceneTree

# 开场剧情实机走查：文字页 → 林边遇到信使（含两次选项）→ 探索黑刺李林 → 信使追上来讲规矩 → 留下獾道。
# 截图写入 outputs/opening-story/；不写玩家存档。运行：Godot --path . --script tests/opening_story_capture.gd -- --flow-qa
class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass
	func save_game(_slot: String, _notify: bool = true) -> Dictionary:
		return {"ok": true, "error_key": ""}

const EDGE := "story.messenger.edge"
const RULES := "story.messenger.thorn_rules"
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
	_check("messenger scene starts by itself", await _wait_until(func() -> bool: return app.dialogue.story_id == EDGE, 3.0))
	_check("the flight is narrated in the dialogue box", app.dialogue.presentation_info().narrator and app.dialogue_overlay.story_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT)
	_check("no messenger card yet", _card_of(&"messenger").is_empty())
	_check("no tutorial hint during dialogue", app._tutorial_key.is_empty())
	_check("messenger recorded in journal", app.progress.npcs.has("npc.messenger"))
	await _settle_text()
	await _shot("07-edge-flight-zh.png")
	_check("messenger unseen before he steps out", not app.dialogue_overlay.npc_portrait.visible)
	await _step_until(func() -> bool: return app.dialogue.awaiting_choice())
	await _shot("08-edge-first-choice-zh.png")
	app.dialogue_overlay._choose("stone")
	await _settle_text()
	await _shot("09-edge-stone-zh.png")
	TranslationServer.set_locale("en")
	await _step_until(func() -> bool: return String(app.dialogue.current_line().get("text_key", "")) == "DLG_MESSENGER_EDGE_26")
	await _shot("10-edge-recognise-en.png")
	_check("messenger visible once he steps out", app.dialogue_overlay.npc_portrait.visible)
	await _step_until(func() -> bool: return app.dialogue.awaiting_choice())
	app.dialogue_overlay._choose("not_sure")
	await _settle_text()
	await _shot("11-edge-reply-en.png")
	await _step_until(func() -> bool: return not app.dialogue.is_active())
	await create_timer(1.2).timeout
	_check("walk-the-wood hint shown", app._tutorial_key == "OPENING_HINT_WALK_WOOD")
	await _shot("12-board-hint-en.png")
	var stacks: Array = app.board.state.stacks.keys()
	app.board.state.merge(stacks[0], stacks[1])
	app.board.refresh_content()
	await create_timer(3.0).timeout
	await _shot("13-exploring-en.png")
	_check("exploration completes", await _wait_until(func() -> bool: return app.opening.stage == &"complete", 12.0))
	await create_timer(1.6).timeout
	_check("messenger hint shown", app._tutorial_key == "OPENING_HINT_MEET_MESSENGER")
	_check("onboarding walk goal done", app.onboarding.is_goal_complete("walk_wood"))
	await _shot("14-messenger-caught-up-en.png")
	TranslationServer.set_locale("zh_CN")
	var hero := _card_of(&"hero")
	var messenger := _card_of(&"messenger")
	app.board.state.merge(app.board.state.stack_for(messenger), app.board.state.stack_for(hero))
	app.board.refresh_content()
	app._on_dialogue_requested("npc.messenger")
	_check("rules talk starts", await _wait_until(func() -> bool: return app.dialogue.story_id == RULES, 3.0))
	await _settle_text()
	await _shot("15-rules-start-zh.png")
	await _step_until(func() -> bool: return app.dialogue.line_index >= 3)
	await _shot("16-rules-one-zh.png")
	await _step_until(func() -> bool: return not app.dialogue.is_active())
	await create_timer(1.5).timeout
	var kinds: Array[String] = []
	for id: String in app.board.state.cards:
		kinds.append(String(app.board.state.card_kind(id)))
	kinds.sort()
	_check("messenger leaves the badger track: %s" % [kinds], kinds == ["badger_track", "hero", "sloes"])
	_check("onboarding messenger goal done", app.onboarding.is_goal_complete("meet_messenger"))
	_check("follow-the-track hint shown", app._tutorial_key == "OPENING_HINT_FOLLOW_TRACK")
	await _shot("17-badger-track-zh.png")
	TranslationServer.set_locale("en")
	app.board.state.merge(app.board.state.stack_for(_card_of(&"badger_track")), app.board.state.stack_for(_card_of(&"hero")))
	app.board.refresh_content()
	await create_timer(2.5).timeout
	_check("walking the track shows progress", app.exploration.work_progress().size() == 1)
	await _shot("18-walking-track-en.png")
	_check("the track leads to the stones", await _wait_until(func() -> bool: return not _card_of(&"the_stones").is_empty(), 10.0))
	await create_timer(1.8).timeout
	_check("track consumed", _card_of(&"badger_track").is_empty())
	_check("onboarding track goal done", app.onboarding.is_goal_complete("follow_track"))
	_check("no hint afterwards", app._tutorial_key.is_empty())
	await _shot("19-the-stones-en.png")
	var snapshot: Dictionary = app._capture_session()
	_check("final state saves and loads", GameSnapshot.decode(JSON.parse_string(JSON.stringify(snapshot))).ok)
	print("OPENING_STORY_CAPTURE failures=%d" % failures)
	quit(0 if failures == 0 else 1)


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
