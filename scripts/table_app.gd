extends Node

const AUTOSAVE_INTERVAL := 30.0
const ONBOARDING_PAN_DISTANCE := 120.0
const ChapterPackageLoader = preload("res://scripts/content/chapter_package.gd")
const ChapterSnapshotCodec = preload("res://scripts/content/chapter_snapshot.gd")
const StorageWorkerScript = preload("res://scripts/services/storage_job_worker.gd")
var chapter: ChapterRuntime
var chapter_menu: ChapterActionMenu
var chapter_market: ChapterMarketDock
var _chapter_requested := false
var _chapter_translations: ModuleBundle
var _chapter_menu_context: Dictionary = {}
var board: TableInteraction
var day_cycle: DayCycle
var overlay: SessionOverlay
var journal: GameJournal
var opening: OpeningFlow
var exploration := LocationExploration.new()
var opening_overlay: OpeningOverlay
var dialogue: DialogueFlow
var dialogue_overlay: DialogueOverlay
var shop: ChapterCustomerQueue
var customer_lane: CustomerLane
var market: MarketDock
var settings: GameSettings
var save_store: SaveStore
var progress: PlayerProgress
var identity: PlayerIdentity
var main_menu: MainMenu
var name_entry: NameEntry
var onboarding: OnboardingGoals
var onboarding_panel: OnboardingGoalPanel
var vegetation: Node3D
var _last_plant_pointer_usec := 0
var table_stage: TableStage3D
var qa_mode := false
var _legacy_qa := false
var _at_main_menu := false
var _has_session := false
var _name_purpose := ""
var autosave_enabled := true
var _autosave_elapsed := 0.0
var _autosave_pending := false
var _autosave_blocked := false
var _startup_save_error := ""
var _loading := false
var _menu_paused := false
var _time_paused := false
var _game_speed := 1.0
var _hitch_report_path := "user://hitch-profile.json"
var _presentation_stage: StringName = &""
var _presentation_page := -1
var _tutorial_key := ""
var _exploration_started := false
var _scene_view_initialized := false
var _storage_thread: Thread
var _storage_worker: RefCounted
var _storage_job: Dictionary = {}
var _queued_storage: Dictionary = {}
var _pan_travel := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var arguments := OS.get_cmdline_user_args()
	HitchProbe.enabled = "--profile-hitches" in arguments
	if HitchProbe.enabled:
		HitchProbe.reset()
		for argument: String in arguments:
			if argument.begins_with("--hitch-report="):
				_hitch_report_path = argument.trim_prefix("--hitch-report=")
	var flow_qa := "--flow-qa" in arguments or "--flow-reopen" in arguments
	var chapter_qa := "--chapter-qa" in arguments
	var chapter_preview_smoke := "--chapter-preview-smoke" in arguments
	var legacy_requested := "--legacy-prototype" in arguments
	for flag: String in ["--qa", "--foundation-qa", "--foundation-reopen", "--opening-qa", "--opening-reopen",
		"--dialogue-qa", "--dialogue-reopen", "--flow-qa", "--flow-reopen"]:
		legacy_requested = legacy_requested or flag in arguments
	_chapter_requested = FileAccess.file_exists(ChapterPackageLoader.MANIFEST_PATH) and (chapter_qa or not legacy_requested)
	flow_qa = flow_qa or chapter_qa or chapter_preview_smoke
	qa_mode = flow_qa or "--qa" in arguments or "--foundation-qa" in arguments or "--foundation-reopen" in arguments or "--opening-qa" in arguments or "--opening-reopen" in arguments or "--dialogue-qa" in arguments or "--dialogue-reopen" in arguments
	_legacy_qa = qa_mode and not flow_qa
	_at_main_menu = not _legacy_qa
	_has_session = _legacy_qa
	var opening_session := not qa_mode or flow_qa or "--opening-qa" in arguments or "--opening-reopen" in arguments or "--dialogue-qa" in arguments or "--dialogue-reopen" in arguments
	var profile_root := "user://"
	if qa_mode:
		profile_root = "res://work/qa-profile-%d" % OS.get_process_id()
		for argument: String in arguments:
			if argument.begins_with("--qa-dir="):
				profile_root = argument.trim_prefix("--qa-dir=").path_join("profile")
	settings = GameSettings.new(profile_root.path_join("settings.cfg"))
	var settings_ok := settings.load_settings()
	GameArt.queue_card_preloads()
	save_store = SaveStore.new(profile_root.path_join("saves").path_join(ContentCatalog.content_generation()))
	save_store.payload_validator = GameSnapshot.decode
	progress = PlayerProgress.new()
	identity = PlayerIdentity.new()
	get_window().title = tr("GAME_TITLE_3D")
	var background_layer := CanvasLayer.new()
	background_layer.layer = -10
	background_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(background_layer)
	background_layer.add_child(TableBackground.new())
	var surface := Control.new()
	surface.name = "TableSurface"
	surface.clip_contents = true
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(surface)
	var world := Node2D.new()
	world.name = "World"
	surface.add_child(world)
	world.add_child(TableBackdrop.new())
	shop = ChapterCustomerQueue.new()
	add_child(shop)
	shop.setup(TableState.new())
	opening = OpeningFlow.new()
	dialogue = DialogueFlow.new()
	if opening_session:
		opening.start(shop.state)
	else:
		opening.deactivate(shop.state)
	var customer_layer := CanvasLayer.new()
	customer_layer.layer = 2
	customer_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(customer_layer)
	customer_lane = CustomerLane.new()
	customer_layer.add_child(customer_lane)
	customer_lane.set_viewport_size(get_viewport().get_visible_rect().size)
	customer_lane.configure(shop)
	market = MarketDock.new()
	customer_layer.add_child(market)
	market.set_viewport_size(get_viewport().get_visible_rect().size)
	chapter_market = ChapterMarketDock.new()
	customer_layer.add_child(chapter_market)
	chapter_market.hide()
	customer_lane.set_market_height(MarketDock.RESERVED_HEIGHT)
	var drag_layer := CanvasLayer.new()
	drag_layer.layer = 5
	drag_layer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(drag_layer)
	var drag_root := Node2D.new()
	drag_layer.add_child(drag_root)
	board = TableInteraction.new()
	board.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(board)
	board.shop = shop
	board.opening = opening
	board.exploration = exploration
	exploration.outputs_created.connect(_on_exploration_outputs)
	exploration.explored.connect(_on_location_explored)
	board.progress = progress
	board.full_table_mode = opening_session
	board.customer_lane = null if opening_session else customer_lane
	board.market = null if opening_session else market
	board.drag_root = drag_root
	board.setup(surface, world, shop.state)
	table_stage = TableStage3D.new()
	add_child(table_stage)
	table_stage.configure(board.camera.bounds, board.camera)
	table_stage.attach_world(world)
	board.camera.projection = table_stage
	board.projection_stage = table_stage
	vegetation = TableMeadow3D.new()
	vegetation.build_near_patches = false
	vegetation.build_near_landmarks = false
	vegetation.build_distant_environment = false
	table_stage.environment_root.add_child(vegetation)
	vegetation.configure_world(TableState.WORLD_BOUNDS)
	board._refresh_world_geometry()
	day_cycle = DayCycle.new()
	add_child(day_cycle)
	journal = GameJournal.new()
	add_child(journal)
	journal.configure(progress)
	journal.toggle_requested.connect(_toggle_journal)
	journal.open_state_changed.connect(func(value: bool) -> void: table_stage.set_cards_visible(not value))
	opening_overlay = OpeningOverlay.new()
	add_child(opening_overlay)
	opening_overlay.advance_requested.connect(opening.advance_intro)
	opening_overlay.finish_requested.connect(opening.finish_intro)
	dialogue_overlay = DialogueOverlay.new()
	add_child(dialogue_overlay)
	dialogue_overlay.configure(dialogue)
	dialogue_overlay.presentation_finished.connect(_apply_pause_state)
	dialogue.changed.connect(_on_dialogue_changed)
	dialogue.story_completed.connect(_on_dialogue_completed)
	board.dialogue_requested.connect(_on_dialogue_requested)
	board.stack_combined.connect(_on_chapter_stack_combined)
	chapter_menu = ChapterActionMenu.new()
	add_child(chapter_menu)
	chapter_menu.option_selected.connect(_on_chapter_option_selected)
	overlay = SessionOverlay.new()
	add_child(overlay)
	overlay.configure(settings, save_store)
	overlay.focus_hero_requested.connect(_focus_hero)
	overlay.time_cycle_requested.connect(cycle_time_mode)
	onboarding = OnboardingGoals.new()
	onboarding.changed.connect(func() -> void:
		if not _loading:
			_autosave_pending = true
	)
	onboarding_panel = OnboardingGoalPanel.new()
	add_child(onboarding_panel)
	onboarding_panel.configure(onboarding)
	board.camera_gesture.connect(_on_camera_gesture)
	journal.open_state_changed.connect(func(_open: bool) -> void: _refresh_onboarding_panel())
	main_menu = MainMenu.new()
	add_child(main_menu)
	name_entry = NameEntry.new()
	add_child(name_entry)
	main_menu.continue_requested.connect(_continue_journey)
	main_menu.new_journey_requested.connect(_start_new_journey)
	main_menu.load_requested.connect(_open_main_page.bind("saves"))
	main_menu.settings_requested.connect(_open_main_page.bind("settings"))
	main_menu.quit_requested.connect(_quit_game)
	table_stage.camera_transition_finished.connect(_on_scene_transition_finished)
	name_entry.confirmed.connect(_on_name_confirmed)
	name_entry.canceled.connect(_cancel_naming)
	day_cycle.progress_changed.connect(overlay.set_day)
	day_cycle.day_started.connect(shop.on_day_started)
	day_cycle.day_started.connect(func(_day: int) -> void: _autosave_pending = true)
	overlay.set_day(day_cycle.day, day_cycle.progress())
	overlay.resume_requested.connect(set_game_paused.bind(false))
	overlay.quit_requested.connect(_return_main_menu)
	overlay.new_journey_requested.connect(_start_new_journey)
	if overlay.has_signal("quit_without_save_requested"):
		overlay.connect("quit_without_save_requested", _quit_without_save)
	overlay.save_requested.connect(_request_manual_save)
	overlay.load_requested.connect(_request_manual_load)
	board.pointer_blocked = _pointer_blocked
	shop.changed.connect(board.refresh_content)
	shop.outputs_created.connect(board.queue_output_flights)
	shop.customer_arrived.connect(_on_customer_arrived)
	shop.transaction_completed.connect(_on_transaction_completed)
	opening.outputs_created.connect(_on_opening_outputs)
	opening.revealed.connect(_on_opening_revealed)
	opening.changed.connect(_on_opening_changed)
	settings.changed.connect(_refresh_localized_content)
	get_window().focus_exited.connect(_on_focus_lost)
	get_viewport().size_changed.connect(_refresh_narrative_table)
	get_viewport().size_changed.connect(_refresh_vegetation_layout)
	get_tree().auto_accept_quit = false
	_sync_identity()
	_sync_opening_presentation(true)
	if not qa_mode or flow_qa or "--foundation-reopen" in arguments or "--opening-reopen" in arguments or "--dialogue-reopen" in arguments:
		_restore_automatic_save()
	if not settings_ok:
		set_game_paused(true)
		overlay.open_page("settings")
		overlay.show_status(settings.error_key, true)



func _process(delta: float) -> void:
	_poll_storage_job()
	if not qa_mode:
		HitchProbe.frame(delta)
	GameArt.poll_preloads()
	if _loading or _at_main_menu or not is_instance_valid(board):
		return
	_refresh_vegetation_layout()
	if chapter != null:
		if get_tree().paused:
			chapter.advance(delta, true)
		elif not _time_paused:
			_advance_chapter_clock(delta * _game_speed)
		chapter_market.day = day_cycle.day
	elif not get_tree().paused and not _time_paused:
		day_cycle.advance(delta * _game_speed)
		if opening.stage == &"inactive":
			shop.advance(delta * _game_speed)
	if not get_tree().paused and not _time_paused and opening != null:
		opening.output_bounds = shop.output_bounds
		var opening_started := HitchProbe.stamp()
		opening.advance(delta * _game_speed, not board.pressed_id.is_empty() or board.panning or not board.flights.is_empty())
		HitchProbe.record("opening_advance", opening_started)
		if chapter == null or opening.stage != &"complete":
			_update_opening_tutorial()
		# 开场那一次探索结束后，由通用的地点探索接手（章节模式有自己的工作系统）。
		if chapter == null and opening.stage == &"complete":
			exploration.state = board.state
			exploration.advance(delta * _game_speed, not board.pressed_id.is_empty() or board.panning or not board.flights.is_empty())
	if not autosave_enabled or _autosave_blocked:
		return
	if not get_tree().paused and not _time_paused:
		_autosave_elapsed += delta
	if _autosave_elapsed >= AUTOSAVE_INTERVAL:
		_autosave_pending = true
	if _autosave_pending and _storage_thread == null and not get_tree().paused and not _time_paused and board.pressed_id.is_empty() and not board.panning and board.flights.is_empty():
		_autosave_pending = false
		_autosave_elapsed = 0.0
		var autosave_started := HitchProbe.stamp()
		var result := _begin_async_save("auto", false)
		HitchProbe.record("autosave_on_frame", autosave_started)
		if not result.ok:
			_autosave_blocked = true
			set_game_paused(true)
			overlay.open_page("saves")
			overlay.show_status(result.error_key, true)


func _advance_chapter_clock(delta: float) -> void:
	var remaining := maxf(delta, 0.0)
	while remaining > 0.000001:
		var until_midnight := maxf(day_cycle.seconds_per_day - day_cycle.elapsed, 0.000001)
		var step := minf(remaining, until_midnight)
		chapter.current_day = day_cycle.day
		chapter.advance(step, not board.pressed_id.is_empty() or board.panning or not board.flights.is_empty())
		if opening.stage == &"complete":
			var shop_id := chapter._shop_card_id()
			if not shop_id.is_empty():
				shop.arrival_screen_origin = board.camera.to_screen(chapter.table.card_position(shop_id) + TableState.CARD_SIZE * 0.5)
			shop.advance(step)
		day_cycle.advance(step)
		remaining -= step


func _input(event: InputEvent) -> void:
	if is_instance_valid(vegetation) and not _at_main_menu and not get_tree().paused:
		if event is InputEventMouseMotion:
			var now := Time.get_ticks_usec()
			var interval := clampf((now - _last_plant_pointer_usec) / 1000000.0, 0.001, 0.05) if _last_plant_pointer_usec > 0 else maxf(get_process_delta_time(), 0.001)
			_last_plant_pointer_usec = now
			if not _pointer_blocked(event.position):
				var at := table_stage.to_terrain(event.position)
				var start := table_stage.to_terrain(event.position - event.relative)
				if not at.is_finite() or not start.is_finite():
					return
				var velocity := (at - start) / interval
				vegetation.set_pointer(at, velocity, false, start)
				if is_instance_valid(table_stage.painted_vegetation) and table_stage.painted_vegetation.has_method("set_pointer"):
					table_stage.painted_vegetation.call("set_pointer", at, velocity, false, start)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if not _pointer_blocked(event.position):
				var point := table_stage.to_terrain(event.position)
				if point.is_finite():
					vegetation.set_pointer(point, Vector2.ZERO, true)
					if is_instance_valid(table_stage.painted_vegetation) and table_stage.painted_vegetation.has_method("set_pointer"):
						table_stage.painted_vegetation.call("set_pointer", point, Vector2.ZERO, true)
	if not event is InputEventKey or not event.pressed or overlay == null:
		return
	if HitchProbe.enabled and event.keycode == KEY_F9 and not event.echo:
		if HitchProbe.save(_hitch_report_path):
			print("Hitch report saved: " + _hitch_report_path)
		get_viewport().set_input_as_handled()
		return
	if _story_naming():
		return
	if _at_main_menu:
		if event.keycode == KEY_ESCAPE:
			if not event.echo:
				if name_entry.visible:
					_cancel_naming()
				elif _menu_paused:
					if not overlay.back():
						set_game_paused(false)
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		if not event.echo:
			if journal.is_open():
				journal.close()
			elif not _menu_paused:
				set_game_paused(true)
			elif not overlay.back():
				set_game_paused(false)
		get_viewport().set_input_as_handled()
	elif dialogue.is_active() and not _menu_paused and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and not event.echo:
		dialogue_overlay.advance()
		get_viewport().set_input_as_handled()
	elif opening.stage == &"intro" and not _menu_paused and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and not event.echo:
		opening_overlay.advance()
		get_viewport().set_input_as_handled()
	elif not _at_main_menu and opening.stage != &"intro" and not _menu_paused and not event.echo and event.keycode == KEY_P:
		set_time_paused(not _time_paused)
		get_viewport().set_input_as_handled()
	elif not _at_main_menu and not _menu_paused and not event.echo and event.keycode in [KEY_1, KEY_3]:
		set_game_speed(3.0 if event.keycode == KEY_3 else 1.0)
		get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_R, KEY_N] and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not get_tree().paused:
		_toggle_journal("recipes" if event.keycode == KEY_R else "npcs")
		get_viewport().set_input_as_handled()


func _toggle_journal(page: String) -> void:
	if _at_main_menu or _menu_paused:
		return
	board.cancel_gesture()
	board.hovered_id = ""
	board._update_view_flags()
	journal.toggle(page)
	if journal.current_page == page:
		onboarding.report(StringName("journal_%s_opened" % page))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(overlay):
		_quit_game()


func set_game_paused(value: bool) -> void:
	var probe_started := HitchProbe.stamp()
	_menu_paused = value
	if value:
		if chapter_menu != null:
			chapter_menu.close()
		var gesture_started := HitchProbe.stamp()
		board.cancel_gesture()
		board.hovered_id = ""
		board._update_view_flags()
		HitchProbe.record("menu_pause_cancel_gesture", gesture_started)
	_apply_pause_state()
	HitchProbe.record("menu_pause_toggle", probe_started)


func _exit_tree() -> void:
	if _storage_thread != null:
		_storage_thread.wait_to_finish()
		_storage_thread = null
		_storage_worker = null


func cycle_time_mode() -> void:
	if _at_main_menu or get_tree().paused:
		return
	if _time_paused:
		set_game_speed(1.0)
		set_time_paused(false)
	elif _game_speed < 3.0:
		set_game_speed(3.0)
	else:
		set_time_paused(true)


func set_time_paused(value: bool) -> void:
	if _at_main_menu or opening.stage == &"intro" or _menu_paused:
		return
	if _time_paused == value:
		return
	var probe_started := HitchProbe.stamp()
	_time_paused = value
	board.simulation_paused = value
	overlay.set_time_controls(_game_speed, _time_paused, true)
	onboarding.report(&"time_mode_changed", "paused" if value else "resumed")
	HitchProbe.record("time_pause_toggle", probe_started)


func set_game_speed(value: float) -> void:
	if _at_main_menu or _menu_paused:
		return
	var previous_speed := _game_speed
	_game_speed = 3.0 if value >= 3.0 else 1.0
	board.simulation_speed = _game_speed
	if previous_speed != _game_speed:
		onboarding.report(&"time_mode_changed", "speed=%d" % int(_game_speed))
	overlay.set_time_controls(_game_speed, _time_paused, true)


func _apply_pause_state() -> void:
	var probe_started := HitchProbe.stamp()
	table_stage.set_menu_view(_at_main_menu, not _scene_view_initialized)
	_scene_view_initialized = true
	table_stage.freeze_camera_transition(_menu_paused)
	var moving := table_stage.is_camera_transitioning()
	var reading := opening.stage == &"intro" or dialogue.is_active() or dialogue_overlay.is_presenting() or _story_naming()
	_refresh_narrative_table()
	get_tree().paused = _at_main_menu or _menu_paused or reading or moving
	board.simulation_paused = _time_paused
	var ui_started := HitchProbe.stamp()
	var main_context_started := HitchProbe.stamp()
	overlay.set_main_menu_context(_at_main_menu)
	HitchProbe.record("menu_pause_context", main_context_started)
	var overlay_started := HitchProbe.stamp()
	overlay.set_paused(_menu_paused)
	HitchProbe.record("menu_pause_overlay", overlay_started)
	var time_controls_started := HitchProbe.stamp()
	overlay.set_time_controls(_game_speed, _time_paused, not _at_main_menu and not _menu_paused and not reading and not moving)
	HitchProbe.record("menu_pause_time_controls", time_controls_started)
	var journal_started := HitchProbe.stamp()
	journal.visible = not _at_main_menu
	journal.set_game_paused(_at_main_menu or _menu_paused or moving)
	HitchProbe.record("menu_pause_journal", journal_started)
	var story_ui_started := HitchProbe.stamp()
	opening_overlay.set_menu_paused(_at_main_menu or _menu_paused or moving)
	dialogue_overlay.set_menu_paused(_at_main_menu or _menu_paused or moving)
	HitchProbe.record("menu_pause_story_ui", story_ui_started)
	var main_ui_started := HitchProbe.stamp()
	main_menu.set_continue_available(_has_session)
	main_menu.set_interactive(_at_main_menu and not _menu_paused and not name_entry.visible)
	main_menu.set_active(_at_main_menu)
	HitchProbe.record("menu_pause_main_ui", main_ui_started)
	HitchProbe.record("menu_pause_ui", ui_started)
	var scene_started := HitchProbe.stamp()
	table_stage.set_active(true)
	_refresh_vegetation_layout()
	board.surface.visible = not _at_main_menu
	board.drag_root.visible = not _at_main_menu
	dialogue_overlay.visible = not _at_main_menu and not moving
	opening_overlay.visible = not _at_main_menu and not moving and not _story_naming()
	# 全屏序幕期间也收起右侧栏，保持暗场。
	var sidebar_visible := not _at_main_menu and not moving and not dialogue_overlay.is_presenting() and not dialogue.is_active() and not opening_overlay.is_chronicle_showing()
	journal.set_entries_visible(sidebar_visible)
	if overlay.has_method("set_hud_visible"):
		overlay.call("set_hud_visible", sidebar_visible)
	else:
		overlay.day_root.visible = not _at_main_menu
	if _at_main_menu:
		opening_overlay.hide_all()
		customer_lane.hide()
		market.hide()
	_refresh_chapter_market()
	_refresh_chapter_customer_lane()
	_refresh_onboarding_panel()
	HitchProbe.record("menu_pause_scene", scene_started)
	HitchProbe.record("menu_pause_apply", probe_started)


# 新手目标只在玩家能直接操作桌面时出现：避开主菜单、暂停、序章、对白、镜头过渡与手账。
func _refresh_onboarding_panel() -> void:
	if not is_instance_valid(onboarding_panel):
		return
	var reading := opening.stage == &"intro" or dialogue.is_active() or dialogue_overlay.is_presenting() or _story_naming()
	var blocked := _at_main_menu or _menu_paused or reading or table_stage.is_camera_transitioning() or journal.is_open()
	onboarding_panel.set_available(not blocked)


# 每个存档独立的新手进度：读档/新旅程时整体替换，目标栏随之从该存档的进度重新呈现。
func _restore_onboarding(data: Variant) -> void:
	if not onboarding.restore(data):
		onboarding.restore(OnboardingGoals.fresh_data())
	_pan_travel = 0.0
	onboarding_panel.resync()


func _on_camera_gesture(kind: StringName, amount: float) -> void:
	if kind == &"zoom":
		onboarding.report(&"camera_zoomed")
	elif kind == &"pan":
		_pan_travel += amount
		if _pan_travel >= ONBOARDING_PAN_DISTANCE:
			onboarding.report(&"camera_panned")


func _refresh_vegetation_layout() -> void:
	if not is_instance_valid(vegetation) or not is_instance_valid(board) or not is_instance_valid(overlay):
		return
	vegetation.visible = true
	vegetation.configure_world(TableState.WORLD_BOUNDS)


func _focus_hero() -> void:
	if _at_main_menu or get_tree().paused:
		return
	onboarding.report(&"hero_focused")
	for card_id: String in board.state.cards:
		if board.state.card_kind(card_id) == &"hero":
			board.cancel_gesture()
			board.selected_id = card_id
			board._update_view_flags()
			board.camera.focus_card(board.state.card_position(card_id) + TableState.CARD_SIZE * 0.5)
			return


func _refresh_narrative_table() -> void:
	if not is_instance_valid(board) or not is_instance_valid(board.world):
		return
	board.set_narrative_width_ratio(1.0)


func _on_scene_transition_finished() -> void:
	_sync_opening_presentation(true)
	dialogue_overlay.sync()
	_apply_pause_state()


func _set_board_mode() -> void:
	var is_opening := opening.stage != &"inactive" or ContentCatalog.card_ids().is_empty()
	if chapter != null:
		day_cycle.set_process(false)
		board.full_table_mode = true
		_refresh_chapter_customer_lane()
		market.hide()
		market.set_process(false)
		shop.set_process(false)
		_refresh_chapter_market()
		return
	board.full_table_mode = is_opening
	day_cycle.set_process(false)
	board.customer_lane = null if is_opening else customer_lane
	board.market = null if is_opening else market
	customer_lane.visible = not is_opening and not _at_main_menu
	customer_lane.set_process(not is_opening)
	market.visible = not is_opening and not _at_main_menu
	market.set_process(not is_opening)
	shop.set_process(false)


func _sync_opening_presentation(force: bool = false) -> void:
	if not is_instance_valid(opening_overlay) or not is_instance_valid(overlay):
		return
	var changed_stage := _presentation_stage != opening.stage
	_set_board_mode()
	board._layout()
	board._refresh_world_geometry()
	if _at_main_menu:
		_apply_pause_state()
		return
	_start_opening_prologue()
	if opening.stage == &"intro":
		if force or changed_stage or _presentation_page != opening.intro_index:
			opening_overlay.show_intro(opening.intro_index, OpeningFlow.intro_page_count())
		_tutorial_key = ""
	elif opening.stage == &"inactive":
		opening_overlay.hide_all()
		_tutorial_key = ""
	elif force or changed_stage:
		_tutorial_key = ""
		_update_opening_tutorial()
	_presentation_stage = opening.stage
	_presentation_page = opening.intro_index
	_request_story_name_if_needed()
	_apply_pause_state()


# 序章文字读完后自动进入的一段对话（此时人物还没上桌，不需要叠卡触发）。
func _start_opening_prologue() -> void:
	if _loading or chapter != null or opening.stage == &"intro" or opening.stage == &"inactive" or dialogue.is_active() or _story_name_pending():
		return
	var story_id := String(ContentCatalog.opening_definition().get("prologue_story_id", ""))
	var npc_id := String(ContentCatalog.story_definition(story_id).get("npc_id", ""))
	if not story_id.is_empty() and story_id not in dialogue.completed and dialogue.next_story(npc_id) == story_id:
		# 先记入人物关系：读档要求进行中的对话人物已在手账里。
		progress.meet_npc(npc_id, day_cycle.day)
		dialogue.start_for_npc(npc_id)


func _update_opening_tutorial() -> void:
	var key := _opening_tutorial_key()
	if key.is_empty() or dialogue.is_active():
		_tutorial_key = ""
		opening_overlay.hide_all()
	elif key != _tutorial_key:
		_tutorial_key = key
		opening_overlay.show_tutorial(key)


# 开场提示按顺序给出：每条在其完成条件达成后让位给下一条；全部完成后不再提示。
func _opening_tutorial_key() -> String:
	if opening.stage == &"intro" or opening.stage == &"inactive":
		return ""
	var definition := ContentCatalog.opening_definition()
	var hints: Variant = definition.get("tutorials", [])
	if not hints is Array or hints.is_empty():
		return String(definition.get("tutorial_key", ""))
	for hint: Variant in hints:
		if not hint is Dictionary:
			continue
		var until_stage := String(hint.get("until_stage", ""))
		var until_story := String(hint.get("until_story", ""))
		if not until_stage.is_empty() and opening.stage == StringName(until_stage):
			continue
		if not until_story.is_empty() and until_story in dialogue.completed:
			continue
		var until_kind_gone := StringName(hint.get("until_kind_gone", ""))
		if not until_kind_gone.is_empty() and not _board_has_kind(until_kind_gone):
			continue
		return String(hint.get("key", ""))
	return ""


func _on_opening_changed() -> void:
	if _loading:
		return
	var probe_started := HitchProbe.stamp()
	_sync_opening_presentation()
	_autosave_pending = true
	HitchProbe.record("opening_changed", probe_started)


func _on_opening_outputs(cards: Array[String], source: StringName) -> void:
	board.queue_output_flights(cards, source)
	board.refresh_content()
	board.sound.play_cue(&"stack")
	onboarding.report(&"opening_explored")


func _board_has_kind(kind: StringName) -> bool:
	for id: String in board.state.cards:
		if board.state.card_kind(id) == kind:
			return true
	return false


func _on_exploration_outputs(cards: Array[String], source_position: Vector2, source_id: String) -> void:
	board.queue_world_output_flights(cards, source_position, source_id)
	board.refresh_content()
	board.sound.play_cue(&"stack")
	_autosave_pending = true


func _on_location_explored(card_definition_id: String) -> void:
	onboarding.report(StringName("explore_completed:" + card_definition_id))


func _on_opening_revealed() -> void:
	for card_id: String in board.state.cards:
		var npc_id := String(board.state.cards[card_id].metadata.get("npc_id", ""))
		if not npc_id.is_empty():
			progress.meet_npc(npc_id, day_cycle.day)
	var bounds := Rect2()
	for stack: String in board.state.stacks:
		var rect := board.state.stack_rect(stack)
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	var visible := Rect2(board.camera.to_world(board.camera.bounds.position), board.camera.bounds.size / board.camera.zoom)
	if not visible.encloses(bounds.grow(16.0)):
		board.camera.focus(bounds)
	_autosave_pending = true


func _on_dialogue_requested(npc_id: String) -> void:
	if _at_main_menu or _menu_paused or dialogue.is_active() or opening.stage == &"intro":
		return
	board.cancel_gesture()
	board._sync_views(true)
	if chapter != null:
		var npc_instance := _chapter_npc_instance(npc_id)
		var options := chapter.story_options(npc_id)
		if options.size() == 1:
			chapter.request_story(options[0].id, npc_instance)
		elif not options.is_empty():
			_chapter_menu_context = {"kind": "story", "source": npc_instance}
			chapter_menu.open(options, board.camera.to_screen(board.state.card_position(npc_instance)))
		return
	dialogue.start_for_npc(npc_id)


func _on_dialogue_changed() -> void:
	if _loading:
		return
	if dialogue.is_active():
		opening_overlay.hide_all()
	else:
		_sync_opening_presentation(true)
	_apply_pause_state()
	_autosave_pending = true


func _on_dialogue_completed(completed_story_id: String, npc_id: String) -> void:
	if _loading:
		return
	if chapter != null:
		return
	onboarding.report(StringName("story_completed:" + completed_story_id))
	var result := dialogue.resolve_story_consequences(completed_story_id, npc_id, board.state)
	if not result.ok:
		push_error("Cannot resolve completed story: " + String(result.reason))
		return
	if result.departed.is_empty():
		return
	if not result.created.is_empty():
		var source: Dictionary = result.sources[0]
		board.queue_world_output_flights(result.created, source.world_center - TableState.CARD_SIZE * 0.5, String(source.card_id))
		board.sound.play_cue(&"stack")
	for card: String in result.departed:
		shop.customers.erase(card)
	board.refresh_content()
	customer_lane._sync_views()
	_autosave_pending = true


func _start_new_journey() -> void:
	if _legacy_qa:
		_commit_new_journey(identity.name)
	elif int(ContentCatalog.opening_definition().get("name_entry_page", -1)) >= 0:
		_commit_new_journey("")
	else:
		_request_name("new")


# 开场读到 name_entry_page 页时请玩家取名（等于页数即“序幕读完之后”）；新旅程不在主菜单取名。
func _story_name_pending() -> bool:
	var page := int(ContentCatalog.opening_definition().get("name_entry_page", -1))
	if page < 0 or not identity.name.is_empty() or opening.stage == &"inactive":
		return false
	return opening.stage != &"intro" or opening.intro_index >= page


func _story_naming() -> bool:
	return name_entry.visible and _name_purpose == "story"


# 取名期间不能取消，不回主菜单；名字定下之前，林边那段对话不开始。
func _request_story_name_if_needed() -> void:
	if _at_main_menu or name_entry.visible or not _story_name_pending():
		return
	board.cancel_gesture()
	_name_purpose = "story"
	name_entry.open("", false, false)
	_apply_pause_state()


func _request_name(purpose: String) -> void:
	board.cancel_gesture()
	_at_main_menu = true
	_menu_paused = false
	_name_purpose = purpose
	_apply_pause_state()
	name_entry.open(identity.name if purpose == "continue" else "", purpose == "continue")
	main_menu.set_interactive(false)


func _cancel_naming() -> void:
	if _name_purpose == "story":
		return
	name_entry.close()
	_name_purpose = ""
	_menu_paused = false
	_apply_pause_state()


func _on_name_confirmed(player_name: String) -> void:
	if _name_purpose.is_empty():
		return
	var error := PlayerIdentity.name_error(player_name)
	if not error.is_empty():
		name_entry.show_status(error)
		return
	if _name_purpose == "new":
		_commit_new_journey(player_name)
		return
	if _name_purpose == "story":
		identity.set_name(player_name)
		_sync_identity()
		var saved := save_game("auto", false)
		if not saved.ok:
			identity.name = ""
			_sync_identity()
			name_entry.show_status(saved.error_key)
			return
		name_entry.close()
		_name_purpose = ""
		_sync_opening_presentation(true)
		return
	var previous_name := identity.name
	identity.set_name(player_name)
	_sync_identity()
	var result := save_game("auto", false)
	if not result.ok:
		identity.name = previous_name
		_sync_identity()
		name_entry.show_status(result.error_key)
		return
	_enter_game()


func _commit_new_journey(player_name: String) -> bool:
	if _storage_thread != null:
		_flush_storage_job()
	if _chapter_requested:
		return _commit_chapter_journey(player_name)
	board.cancel_gesture()
	var previous := _capture_session()
	var previous_error := _startup_save_error
	var previous_blocked := _autosave_blocked
	var previous_session := _has_session
	_loading = true
	_leave_chapter()
	var table := TableState.new()
	shop.setup(table)
	opening.output_bounds = TableState.WORLD_BOUNDS
	opening.start(table)
	dialogue.reset()
	dialogue_overlay.sync()
	identity.restore({"name": ""})
	if not player_name.is_empty():
		identity.set_name(player_name)
	_restore_onboarding(OnboardingGoals.fresh_data())
	day_cycle.day = 1
	day_cycle.elapsed = 0.0
	progress.restore({"recipes": [], "npcs": {}})
	_set_board_mode()
	board.replace_state(table)
	board.camera.zoom = 1.0
	board.camera.target_zoom = 1.0
	var opening_center := Vector2(0,-350)
	board.camera.offset = board.camera.bounds.get_center()-opening_center*board.camera.zoom
	board.camera.target_offset = board.camera.offset
	customer_lane.restore_session(shop)
	_exploration_started = false
	exploration.reset()
	_startup_save_error = ""
	_autosave_blocked = false
	_has_session = true
	_loading = false
	_sync_identity()
	var result := save_game("auto", false)
	if not result.ok:
		apply_snapshot(GameSnapshot.decode(previous))
		_startup_save_error = previous_error
		_autosave_blocked = previous_blocked
		_has_session = previous_session
		if name_entry.visible:
			name_entry.show_status(result.error_key)
			_apply_pause_state()
		else:
			set_game_paused(true)
			overlay.open_page("saves")
			overlay.show_status(result.error_key, true)
		return false
	overlay.set_day(day_cycle.day, day_cycle.progress())
	_time_paused = false
	_game_speed = 1.0
	board.simulation_paused = false
	board.simulation_speed = 1.0
	_enter_game()
	return true


func _continue_journey() -> void:
	if not _has_session:
		main_menu.show_status("MAIN_MENU_NO_SAVE")
		return
	if identity.name.is_empty() and not _legacy_qa:
		_request_name("continue")
	else:
		_enter_game()


func _enter_game() -> void:
	name_entry.close()
	_name_purpose = ""
	_at_main_menu = false
	_menu_paused = false
	_time_paused = false
	_sync_identity()
	_sync_opening_presentation(true)
	if dialogue.is_active():
		opening_overlay.hide_all()
	dialogue_overlay.sync()


func _open_main_page(page: String) -> void:
	if not _at_main_menu or name_entry.visible:
		return
	set_game_paused(true)
	overlay.open_page(page)


func _return_main_menu() -> void:
	if _at_main_menu:
		set_game_paused(false)
		return
	set_game_paused(true)
	var result := save_game("auto", false)
	if not result.ok:
		overlay.open_page("saves")
		overlay.show_status(result.error_key, true)
		return
	_at_main_menu = true
	_menu_paused = false
	_time_paused = false
	main_menu.show_status("MAIN_MENU_SAVED")
	_apply_pause_state()


func _request_manual_save(slot: String) -> void:
	if _storage_thread != null:
		_queued_storage = {"kind": "save", "slot": slot}
		overlay.show_status("SAVE_IN_PROGRESS", false)
		return
	var result := _begin_async_save(slot, true)
	if not result.ok:
		overlay.show_status(result.error_key, true)


func _request_manual_load(slot: String) -> void:
	if _storage_thread != null:
		_queued_storage = {"kind": "load", "slot": slot}
		overlay.show_status("LOAD_IN_PROGRESS", false)
		return
	var result := _begin_async_load(slot)
	if not result.ok:
		overlay.show_status(result.error_key, true)


func _begin_async_save(slot: String, notify: bool) -> Dictionary:
	if _loading or not _has_session or not SaveStore.SLOTS.has(slot):
		return {"ok": false, "error_key": "SAVE_WRITE_FAILED"}
	if slot == "auto" and not _startup_save_error.is_empty():
		return {"ok": false, "error_key": _startup_save_error}
	if _storage_thread != null:
		return {"ok": false, "error_key": "SAVE_WRITE_FAILED"}
	var capture_started := HitchProbe.stamp()
	var prepared: Dictionary
	if chapter == null:
		prepared = GameSnapshot.capture(board.state, shop, day_cycle, board.camera, progress, opening, dialogue, identity)
		prepared["onboarding"] = onboarding.to_data()
	else:
		var checkpoint: Dictionary = chapter.checkpoint_fast()
		if not checkpoint.get("table") is Dictionary:
			return {"ok": false, "error_key": "SAVE_INVALID_DATA"}
		var center := (board.camera.bounds.get_center() - board.camera.offset) / board.camera.zoom
		prepared = ChapterSnapshotCodec.prepare_capture(checkpoint,
			{"day": day_cycle.day, "elapsed": day_cycle.elapsed, "seconds_per_day": day_cycle.seconds_per_day},
			{"zoom": board.camera.zoom, "center": [center.x, center.y]},
			progress.to_data(), opening.to_data(), identity.to_data(), chapter.director_data(), chapter.package.package_fingerprint)
		prepared["onboarding"] = onboarding.to_data()
	HitchProbe.record("async_save_prepare", capture_started)
	_storage_worker = StorageWorkerScript.new()
	_storage_thread = Thread.new()
	_storage_job = {"kind": "save", "slot": slot, "notify": notify}
	var started := _storage_thread.start(Callable(_storage_worker, "validate_and_write").bind(prepared, save_store.directory, slot), Thread.PRIORITY_LOW)
	if started != OK:
		_storage_thread = null
		_storage_worker = null
		_storage_job.clear()
		return {"ok": false, "error_key": "SAVE_WRITE_FAILED"}
	if notify:
		overlay.show_status("SAVE_IN_PROGRESS", false)
	return {"ok": true, "error_key": ""}


func _begin_async_load(slot: String) -> Dictionary:
	if _storage_thread != null or not SaveStore.SLOTS.has(slot):
		return {"ok": false, "error_key": "SAVE_INVALID_SLOT"}
	_storage_worker = StorageWorkerScript.new()
	_storage_thread = Thread.new()
	_storage_job = {"kind": "load", "slot": slot, "from_main": _at_main_menu}
	var started := _storage_thread.start(Callable(_storage_worker, "read_slot").bind(save_store.directory, slot), Thread.PRIORITY_LOW)
	if started != OK:
		_storage_thread = null
		_storage_worker = null
		_storage_job.clear()
		return {"ok": false, "error_key": "SAVE_READ_FAILED"}
	overlay.show_status("LOAD_IN_PROGRESS", false)
	return {"ok": true, "error_key": ""}


func _poll_storage_job() -> void:
	if _storage_thread != null and not _storage_thread.is_alive():
		_complete_storage_job()


func _flush_storage_job() -> void:
	while _storage_thread != null:
		_complete_storage_job()


func _complete_storage_job() -> void:
	if _storage_thread == null:
		return
	var completion_started := HitchProbe.stamp()
	var result: Variant = _storage_thread.wait_to_finish()
	var job := _storage_job.duplicate()
	_storage_thread = null
	_storage_worker = null
	_storage_job.clear()
	var outcome: Dictionary = result if result is Dictionary else {"ok": false, "error_key": "SAVE_READ_FAILED"}
	if job.kind == "save":
		var stored: Dictionary = outcome if outcome.get("ok", false) and outcome.get("payload") is Dictionary else {"ok": false, "error_key": outcome.get("error_key", "SAVE_INVALID_DATA")}
		if stored.ok:
			var note_started := HitchProbe.stamp()
			save_store.note_external_write(job.slot, stored.payload, stored.saved_at)
			HitchProbe.record("async_save_note", note_started)
			_autosave_blocked = not _startup_save_error.is_empty()
			if job.slot == "auto":
				_autosave_elapsed = 0.0
		else:
			if job.slot == "auto":
				_autosave_blocked = true
				set_game_paused(true)
				overlay.open_page("saves")
		var slots_started := HitchProbe.stamp()
		overlay.refresh_slots()
		HitchProbe.record("async_save_slots", slots_started)
		if job.notify or not stored.ok:
			overlay.show_status("SAVE_SUCCESS" if stored.ok else stored.error_key, not stored.ok)
	else:
		if outcome.get("ok", false):
			var decoded: Dictionary = outcome.decoded if outcome.get("decoded") is Dictionary else GameSnapshot.decode(outcome.payload)
			if decoded.ok:
				var apply_started := HitchProbe.stamp()
				apply_snapshot(decoded)
				HitchProbe.record("async_load_apply", apply_started)
				_has_session = true
				_startup_save_error = ""
				_autosave_blocked = false
				if identity.name.is_empty() and not _legacy_qa:
					_request_name("continue")
				elif job.from_main:
					_enter_game()
				else:
					set_game_paused(true)
				overlay.refresh_slots()
				if outcome.recovered and overlay.current_page == "main":
					overlay.open_page("saves")
				overlay.show_status("SAVE_RECOVERED" if outcome.recovered else "LOAD_SUCCESS", false)
			else:
				overlay.show_status(decoded.error_key, true)
		else:
			overlay.show_status(outcome.get("error_key", "SAVE_READ_FAILED"), true)
	if not _queued_storage.is_empty():
		var next := _queued_storage.duplicate()
		_queued_storage.clear()
		if next.kind == "save":
			_request_manual_save(next.slot)
		else:
			_request_manual_load(next.slot)
	HitchProbe.record("async_storage_complete", completion_started)


func save_game(slot: String, notify: bool = true) -> Dictionary:
	if _storage_thread != null:
		_flush_storage_job()
	if _loading or not _has_session:
		return {"ok": false, "error_key": "SAVE_WRITE_FAILED"}
	if slot == "auto" and not _startup_save_error.is_empty():
		return {"ok": false, "error_key": _startup_save_error}
	var probe_started := HitchProbe.stamp()
	board.cancel_gesture()
	var capture_started := HitchProbe.stamp()
	var payload := _capture_session()
	HitchProbe.record("save_capture", capture_started)
	# 首章 capture 已做完整校验；写盘服务仍独立校验最终载荷与备份。
	var checked := {"ok": true} if chapter != null and payload.get("state_version") == 9 else GameSnapshot.decode(payload)
	var result: Dictionary
	if checked.ok:
		var write_started := HitchProbe.stamp()
		result = save_store.write_save(slot, payload, true)
		HitchProbe.record("save_write", write_started)
	else:
		result = {"ok": false, "error_key": checked.error_key}
	if result.ok:
		_autosave_blocked = not _startup_save_error.is_empty()
		if slot == "auto":
			_autosave_elapsed = 0.0
			_autosave_pending = false
	var slots_started := HitchProbe.stamp()
	overlay.refresh_slots()
	HitchProbe.record("save_refresh_slots", slots_started)
	if notify:
		overlay.show_status("SAVE_SUCCESS" if result.ok else result.error_key, not result.ok)
	HitchProbe.record("save_total", probe_started)
	return result


func load_game(slot: String) -> Dictionary:
	if _storage_thread != null:
		_flush_storage_job()
	var probe_started := HitchProbe.stamp()
	var from_main := _at_main_menu
	var read_started := HitchProbe.stamp()
	var record := save_store.read_save(slot)
	HitchProbe.record("load_read", read_started)
	if not record.ok:
		overlay.show_status(record.error_key, true)
		return record
	var decode_started := HitchProbe.stamp()
	var decoded: Dictionary = record.decoded if record.get("decoded") is Dictionary else GameSnapshot.decode(record.payload)
	HitchProbe.record("load_decode", decode_started)
	if not decoded.ok:
		overlay.show_status(decoded.error_key, true)
		return decoded
	var apply_started := HitchProbe.stamp()
	apply_snapshot(decoded)
	HitchProbe.record("load_apply", apply_started)
	_has_session = true
	_startup_save_error = ""
	_autosave_blocked = false
	if identity.name.is_empty() and not _legacy_qa:
		_request_name("continue")
	elif from_main:
		_enter_game()
	else:
		set_game_paused(true)
	var slots_started := HitchProbe.stamp()
	overlay.refresh_slots()
	HitchProbe.record("load_refresh_slots", slots_started)
	if record.recovered and overlay.current_page == "main":
		overlay.open_page("saves")
	overlay.show_status("SAVE_RECOVERED" if record.recovered else "LOAD_SUCCESS", false)
	HitchProbe.record("load_total", probe_started)
	return {"ok": true, "error_key": "", "recovered": record.recovered}


func apply_snapshot(decoded: Dictionary) -> void:
	if decoded.get("session_mode") == "chapter_01" or decoded.has("chapter_world"):
		_apply_chapter_snapshot(decoded)
		return
	_loading = true
	_leave_chapter()
	board.cancel_gesture()
	shop.state = decoded.state
	shop.is_open = bool(decoded.shop.is_open)
	shop.customers.assign(decoded.shop.customers)
	shop.arrival_remaining = float(decoded.shop.arrival_remaining)
	shop.arrivals_today = int(decoded.shop.arrivals_today)
	shop.sales_count = int(decoded.shop.sales_count)
	shop.next_ticket = int(decoded.shop.next_ticket)
	day_cycle.day = int(decoded.day.day)
	day_cycle.elapsed = float(decoded.day.elapsed)
	day_cycle.seconds_per_day = float(decoded.day.seconds_per_day)
	if chapter != null:
		chapter.current_day = day_cycle.day
	progress.restore(decoded.progress)
	opening.restore(decoded.opening, decoded.state)
	dialogue.restore(decoded.dialogue)
	identity.restore(decoded.identity)
	_restore_onboarding(decoded.get("onboarding", {}))
	_sync_identity()
	dialogue_overlay.sync()
	_set_board_mode()
	board.replace_state(decoded.state)
	board.camera.zoom = float(decoded.camera.zoom)
	board.camera.target_zoom = board.camera.zoom
	var center := Vector2(float(decoded.camera.center[0]), float(decoded.camera.center[1]))
	board.camera.offset = board.camera.bounds.get_center() - center * board.camera.zoom
	board.camera.target_offset = board.camera.offset
	board._refresh_world_geometry()
	board._sync_views(true)
	customer_lane.restore_session(shop)
	overlay.set_day(day_cycle.day, day_cycle.progress())
	journal.refresh()
	_exploration_started = opening.elapsed > 0.0
	exploration.reset()
	_sync_opening_presentation(true)
	if dialogue.is_active():
		opening_overlay.hide_all()
	_autosave_elapsed = 0.0
	_autosave_pending = false
	_loading = false


func _restore_automatic_save() -> void:
	var record := save_store.read_save("auto")
	if not record.ok and record.error_key == "SAVE_NOT_FOUND":
		return
	if _at_main_menu:
		var decoded: Dictionary = GameSnapshot.decode(record.payload) if record.ok else record
		if decoded.ok:
			apply_snapshot(decoded)
			_has_session = true
			_startup_save_error = ""
			_autosave_blocked = false
			main_menu.show_status("SAVE_RECOVERED" if record.recovered else "")
		else:
			_startup_save_error = decoded.error_key
			_autosave_blocked = true
			main_menu.show_status(decoded.error_key, true)
		_apply_pause_state()
		return
	var result := load_game("auto")
	if not result.ok:
		_startup_save_error = result.error_key
		_autosave_blocked = true
		set_game_paused(true)
		overlay.open_page("saves")
		overlay.show_status(result.error_key, true)


func _on_customer_arrived(npc_id: StringName) -> void:
	if chapter != null:
		return
	progress.meet_npc(String(npc_id), day_cycle.day)


func _on_transaction_completed(action: StringName, npc_id: StringName) -> void:
	if chapter != null:
		return
	var recipe_id := ContentCatalog.recipe_for_action(action)
	if not recipe_id.is_empty():
		progress.discover_recipe(recipe_id)
	if action == &"sell" and not npc_id.is_empty():
		progress.complete_order(String(npc_id), day_cycle.day)


func _refresh_localized_content() -> void:
	get_window().title = tr("GAME_TITLE_3D")
	_sync_identity()
	if is_instance_valid(board):
		board._update_view_flags()
	if is_instance_valid(market):
		market.queue_redraw()
	if is_instance_valid(customer_lane):
		customer_lane._content_tickets.clear()
		customer_lane._sync_views()
		customer_lane.queue_redraw()


func _on_focus_lost() -> void:
	if is_instance_valid(overlay) and not _at_main_menu:
		set_game_paused(true)


func _sync_identity() -> void:
	if identity == null:
		return
	if is_instance_valid(board):
		board.player_name = identity.name
	if is_instance_valid(overlay):
		overlay.set_identity(identity.name)
	if is_instance_valid(dialogue_overlay):
		dialogue_overlay.set_player_name(identity.name)


func _pointer_blocked(point: Vector2) -> bool:
	var portrait := overlay.player_hud.portrait
	var over_portrait := portrait.is_visible_in_tree() and portrait.get_global_rect().has_point(point)
	return get_tree().paused or over_portrait or overlay.blocks_time_control(point) or journal.blocks_pointer(point) or onboarding_panel.blocks_pointer(point) or opening_overlay.blocks_pointer(point) or (chapter_menu != null and chapter_menu.blocks_pointer(point))


func _quit_game() -> void:
	set_game_paused(true)
	var settings_ok := settings.save_settings()
	var result := save_game("auto", false) if _has_session else {"ok": true, "error_key": ""}
	if result.ok and settings_ok:
		get_tree().quit()
	else:
		name_entry.close()
		_name_purpose = ""
		_apply_pause_state()
		overlay.open_page("saves" if not result.ok else "settings")
		overlay.show_status(result.error_key if not result.ok else settings.error_key, true)
		if overlay.has_method("confirm_quit_without_save"):
			overlay.call("confirm_quit_without_save")


func _quit_without_save() -> void:
	get_tree().quit()


func _capture_session() -> Dictionary:
	if chapter == null:
		var legacy := GameSnapshot.capture(board.state, shop, day_cycle, board.camera, progress, opening, dialogue, identity)
		legacy["onboarding"] = onboarding.to_data()
		return legacy
	var relationships_started := HitchProbe.stamp()
	_sync_chapter_relationships()
	HitchProbe.record("save_capture_relationships", relationships_started)
	var center := (board.camera.bounds.get_center() - board.camera.offset) / board.camera.zoom
	var checkpoint_started := HitchProbe.stamp()
	var checkpoint: Dictionary = chapter.checkpoint()
	HitchProbe.record("save_capture_checkpoint", checkpoint_started)
	var director_started := HitchProbe.stamp()
	var director: Dictionary = chapter.director_data()
	HitchProbe.record("save_capture_director", director_started)
	var snapshot_started := HitchProbe.stamp()
	var payload: Dictionary = GameSnapshot.capture_chapter(board.state,
		{"day": day_cycle.day, "elapsed": day_cycle.elapsed, "seconds_per_day": day_cycle.seconds_per_day},
		{"zoom": board.camera.zoom, "center": [center.x, center.y]},
		progress.to_data(), opening.to_data(), identity.to_data(), checkpoint, director)
	HitchProbe.record("save_capture_snapshot", snapshot_started)
	if payload.has("state_version"):
		payload["onboarding"] = onboarding.to_data()
	return payload


func _commit_chapter_journey(player_name: String) -> bool:
	if _storage_thread != null:
		_flush_storage_job()
	_game_speed = 1.0
	_time_paused = false
	board.simulation_speed = 1.0
	var package := ChapterPackageLoader.load_package()
	var runtime := ChapterRuntime.new()
	var prepared := runtime.configure(package)
	if not prepared.ok:
		push_error("Chapter setup failed: " + str(prepared.get("error", "")))
		name_entry.show_status("SAVE_UNSUPPORTED_VERSION")
		return false
	var initial_opening := OpeningFlow.new()
	initial_opening.start(runtime.table)
	var payload := GameSnapshot.capture_chapter(runtime.table,
		{"day": 1, "elapsed": 0.0, "seconds_per_day": 120.0},
		{"zoom": 1.0, "center": [0.0, -350.0]},
		{"recipes": [], "npcs": {}}, initial_opening.to_data(), {"name": player_name},
		runtime.checkpoint(), runtime.director_data())
	payload["onboarding"] = OnboardingGoals.fresh_data()
	var checked := GameSnapshot.decode(payload)
	if not checked.ok:
		push_error("Chapter initial save refused: " + str(checked.get("reason", "")))
		name_entry.show_status(checked.error_key)
		return false
	# 新局完整校验并写入成功后才替换当前会话；失败保留旧局和当前目录。
	var saved := save_store.write_save("auto", payload)
	if not saved.ok:
		name_entry.show_status(saved.error_key)
		return false
	_apply_chapter_snapshot(checked)
	_startup_save_error = ""
	_autosave_blocked = false
	_has_session = true
	_enter_game()
	return true


func _replace_dialogue(next: DialogueFlow) -> void:
	if dialogue != null:
		if dialogue.changed.is_connected(_on_dialogue_changed):
			dialogue.changed.disconnect(_on_dialogue_changed)
		if dialogue.story_completed.is_connected(_on_dialogue_completed):
			dialogue.story_completed.disconnect(_on_dialogue_completed)
	dialogue = next
	dialogue.changed.connect(_on_dialogue_changed)
	dialogue.story_completed.connect(_on_dialogue_completed)
	dialogue_overlay.configure(dialogue)


func _leave_chapter() -> void:
	if chapter == null:
		return
	chapter_menu.close()
	chapter_market.hide()
	chapter_market.configure(null, board)
	board.chapter_runtime = null
	_replace_dialogue(DialogueFlow.new())
	chapter.dispose()
	chapter = null
	shop.configure_chapter(null)
	if _chapter_translations != null:
		_chapter_translations.uninstall_translations()
		_chapter_translations = null
	ContentCatalog.disable_module("chapter_01")
	progress.chapter_relationships.clear()


func _apply_chapter_snapshot(decoded: Dictionary) -> void:
	var runtime := ChapterRuntime.new()
	var prepared := runtime.configure(decoded.package, decoded.chapter_world, decoded.director, decoded.get("checkpoint_template", {}))
	if not prepared.ok:
		push_error("Validated chapter could not be adopted: " + str(prepared.get("error", "")))
		return
	_loading = true
	_time_paused = false
	_game_speed = 1.0
	board.simulation_speed = 1.0
	board.cancel_gesture()
	chapter_menu.close()
	if _chapter_translations != null:
		_chapter_translations.uninstall_translations()
	if "chapter_01" not in ContentCatalog.enabled_module_ids():
		var registered := ContentCatalog.enable_module("chapter_01", decoded.package.bundle.content)
		if not registered.ok:
			_loading = false
			push_error("Cannot activate validated chapter catalog: " + str(registered.error))
			return
	_chapter_translations = ModuleBundle.new()
	_chapter_translations.install_translations(decoded.package.bundle)
	if chapter != null:
		_replace_dialogue(DialogueFlow.new())
		chapter.dispose()
	chapter = runtime
	board.chapter_runtime = chapter
	shop.state = chapter.table
	shop.is_open = chapter.shop_open()
	var queue_result := shop.configure_chapter(chapter, int(decoded.day.day))
	if not queue_result.ok:
		push_error("Chapter customer queue: " + str(queue_result.error))
	_replace_dialogue(chapter.dialogue)
	chapter.changed.connect(_on_chapter_changed)
	chapter.outputs_created.connect(board.queue_world_output_flights)
	chapter.market_outputs_created.connect(_on_chapter_market_outputs)
	chapter.recipe_completed.connect(progress.discover_recipe)
	chapter.npc_encountered.connect(_on_chapter_npc_encountered)
	chapter.failed.connect(func(reason: String) -> void: push_error("Chapter runtime: " + reason))
	chapter_market.configure(chapter, board, day_cycle)
	day_cycle.day = int(decoded.day.day)
	day_cycle.elapsed = float(decoded.day.elapsed)
	day_cycle.seconds_per_day = float(decoded.day.seconds_per_day)
	chapter.current_day = day_cycle.day
	progress.restore(decoded.progress)
	_sync_chapter_relationships()
	# v9 已校验完整章节；旧 OpeningFlow 的 complete 校验只允许初始三/四张牌。
	opening.state = chapter.table
	opening.stage = StringName(decoded.opening.stage)
	opening.intro_index = int(decoded.opening.intro_index)
	opening.elapsed = float(decoded.opening.elapsed)
	identity.restore(decoded.identity)
	_restore_onboarding(decoded.get("onboarding", {}))
	chapter.reconcile_npc_presence()
	board.replace_state(chapter.table)
	board.camera.zoom = float(decoded.camera.zoom)
	board.camera.target_zoom = board.camera.zoom
	var center := Vector2(float(decoded.camera.center[0]), float(decoded.camera.center[1]))
	board.camera.offset = board.camera.bounds.get_center() - center * board.camera.zoom
	board.camera.target_offset = board.camera.offset
	board._refresh_world_geometry()
	customer_lane.restore_session(shop)
	_sync_identity()
	dialogue_overlay.sync()
	overlay.set_day(day_cycle.day, day_cycle.progress())
	journal.refresh()
	_exploration_started = opening.elapsed > 0.0
	exploration.reset()
	_autosave_elapsed = 0.0
	_autosave_pending = false
	_loading = false
	_sync_opening_presentation(true)


func _on_chapter_changed() -> void:
	if _loading or chapter == null:
		return
	var probe_started := HitchProbe.stamp()
	_update_opening_tutorial()
	var relation_started := HitchProbe.stamp()
	_sync_chapter_relationships()
	HitchProbe.record("chapter_relationships", relation_started)
	var presence_started := HitchProbe.stamp()
	chapter.reconcile_npc_presence()
	HitchProbe.record("chapter_npc_presence", presence_started)
	shop.sync_chapter_state()
	var view_started := HitchProbe.stamp()
	board.refresh_content()
	HitchProbe.record("chapter_refresh_cards", view_started)
	board._sync_stack_progress()
	var ui_started := HitchProbe.stamp()
	_refresh_chapter_market()
	_refresh_chapter_customer_lane()
	HitchProbe.record("chapter_refresh_market_ui", ui_started)
	_autosave_pending = true
	HitchProbe.record("chapter_changed", probe_started)


func _refresh_chapter_market() -> void:
	if not is_instance_valid(chapter_market) or not is_instance_valid(board):
		return
	var enabled := chapter != null and chapter.runtime_permission("market_unlock_fact")
	chapter_market.visible = enabled and not _at_main_menu and not _menu_paused and not dialogue.is_active() and not dialogue_overlay.is_presenting() and not table_stage.is_camera_transitioning()
	chapter_market.day = day_cycle.day if day_cycle != null else 1
	chapter_market.set_viewport_size(get_viewport().get_visible_rect().size)
	if chapter != null:
		board.market = chapter_market if enabled else null


func _refresh_chapter_customer_lane() -> void:
	if not is_instance_valid(board) or not is_instance_valid(customer_lane):
		return
	var enabled := chapter != null and opening.stage == &"complete" and chapter.runtime_permission("shop_unlock_fact")
	board.customer_lane = customer_lane if enabled else null
	customer_lane.visible = enabled and not _at_main_menu and not _menu_paused and not dialogue.is_active() and not dialogue_overlay.is_presenting()
	customer_lane.set_process(enabled)
	board._layout()


func _on_chapter_market_outputs(ids: Array[String], source_id: String) -> void:
	var side: StringName = &"supply" if source_id == chapter_market.source_for(&"supply") else &"sell"
	board.queue_screen_output_flights(ids, chapter_market.slot_origin(side), source_id)


func _on_chapter_npc_encountered(npc_id: String) -> void:
	# 同次来访的连续场次不是重复来访，也不会反复刷好感。
	if not progress.npcs.has(npc_id):
		progress.meet_npc(npc_id, day_cycle.day)
	_sync_chapter_relationships()


func _sync_chapter_relationships() -> void:
	if chapter == null:
		return
	var projection_started := HitchProbe.stamp()
	var projected: Dictionary = chapter.relationship_projection()
	HitchProbe.record("relationship_projection", projection_started)
	var apply_started := HitchProbe.stamp()
	if not projected.ok or not progress.apply_chapter_relationships(projected):
		push_error("Chapter relationship projection failed: " + str(projected.get("error", "invalid_projection")))
	HitchProbe.record("relationship_apply", apply_started)


func _chapter_npc_instance(npc_id: String) -> String:
	for id: String in board.state.cards:
		if board.state.cards[id].metadata.get("npc_id") == npc_id:
			return id
	return ""


func _on_chapter_stack_combined(stack_id: String) -> void:
	if chapter == null or _at_main_menu or _menu_paused:
		return
	var probe_started := HitchProbe.stamp()
	chapter.current_day = day_cycle.day
	# 拆分重叠可能在一帧内完成，先释放已失效工序的锁再计算本次选择。
	chapter.advance(0.0, true)
	var options := chapter.options_for_stack(stack_id)
	if options.size() == 1:
		chapter.begin_option(options[0], stack_id, true)
	elif not options.is_empty():
		_chapter_menu_context = {"kind": "work", "source": stack_id}
		chapter_menu.open(options, board.stack_screen_rect(stack_id).end + Vector2(12, 0))
	HitchProbe.record("stack_combined_callback", probe_started)


func _on_chapter_option_selected(option: Dictionary) -> void:
	if chapter == null or _chapter_menu_context.is_empty() or _menu_paused:
		return
	chapter.current_day = day_cycle.day
	var context := _chapter_menu_context.duplicate()
	_chapter_menu_context.clear()
	if context.kind == "story":
		chapter.request_story(option.id, context.source)
	else:
		chapter.begin_option(option, context.source)


func _run_qa(path: String) -> void:
	var qa_script: Script = load(path)
	var qa: Node = qa_script.new()
	add_child(qa)
	qa.call_deferred("run", self)
