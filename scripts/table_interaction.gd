class_name TableInteraction
extends Node

signal dialogue_requested(npc_id: String)
signal stack_combined(stack_id: String)
signal camera_gesture(kind: StringName, amount: float)

var chapter_runtime: ChapterRuntime

const DRAG_THRESHOLD := 5.0
const CONVERSATION_PREPARE_SECONDS := 1.5
var conversation_preparation: Dictionary = {}
var state := TableState.new()
var camera := TableCamera.new()
var world: Node2D
var projection_stage: Control
var surface: Control
var preview: TableDropPreview
var stack_progress: StackProgressView
var _extra_stack_progress: Array[StackProgressView] = []
var sound: TableSound
var views: Dictionary = {}
var selected_id := ""
var hovered_id := ""
var mouse_screen := Vector2(-10000, -10000)
var pressed_id := ""
var press_at := Vector2.ZERO
var press_whole := false
var press_button := MOUSE_BUTTON_NONE
var pressed_snapshot: Dictionary = {}
var dragging_id := ""
var drag_offset := Vector2.ZERO
var drag_velocity := Vector2.ZERO
var _drag_screen_offset := Vector2.ZERO
var _drag_screen_scale := 1.0
var target_id := ""
var panning := false
var pan_button := MOUSE_BUTTON_NONE
var reduced_motion := false
var simulation_speed := 1.0
var simulation_paused := false
var pointer_blocked := Callable()
var shop: ShopSession
var opening: OpeningFlow
var exploration: LocationExploration
var progress: PlayerProgress
var full_table_mode := false
var customer_lane: CustomerLane
var market: MarketDock
var drag_root: Node2D
var customer_target := ""
var market_target: StringName = &""
var target_card := ""
var drop_action: StringName = &"stack"
var combination_targets: Dictionary = {}
var flights: Dictionary = {}
var _pending_flights: Dictionary = {}
var player_name: String = "":
	set(value):
		if player_name == value:
			return
		player_name = value
		if is_instance_valid(world) and not views.is_empty():
			_sync_views()


func setup(board_surface: Control, board_world: Node2D, initial_state: TableState = null) -> void:
	surface = board_surface
	world = board_world
	preview = TableDropPreview.new()
	preview.visible = false
	world.add_child(preview)
	stack_progress = StackProgressView.new()
	if drag_root != null:
		drag_root.add_child(stack_progress)
	else:
		var progress_layer := CanvasLayer.new()
		progress_layer.layer = 5
		add_child(progress_layer)
		progress_layer.add_child(stack_progress)
	sound = TableSound.new()
	add_child(sound)
	get_window().focus_exited.connect(cancel_gesture)
	get_window().mouse_exited.connect(cancel_gesture)
	if initial_state == null:
		state.seed()
	else:
		state = initial_state
	_reclamp_stacks()
	_layout()
	_sync_views(true)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	Input.use_accumulated_input = false


func _process(delta: float) -> void:
	if not is_instance_valid(world):
		return
	_layout()
	camera.update(delta, reduced_motion)
	_refresh_world_geometry()
	_advance_flights(delta)
	_advance_conversation_preparation(delta * simulation_speed)
	if not dragging_id.is_empty():
		_move_drag(mouse_screen)
	elif not panning:
		hovered_id = pick_card(mouse_screen) if _is_board_point(mouse_screen) else ""
	_update_view_flags()
	drag_velocity = drag_velocity.lerp(Vector2.ZERO, 1.0 - exp(-12.0 * delta))


var narrative_width_ratio := 1.0


func set_narrative_width_ratio(value: float) -> void:
	narrative_width_ratio = clampf(value, 0.35, 1.0)
	_refresh_world_geometry()


func _refresh_world_geometry() -> void:
	if is_instance_valid(projection_stage):
		projection_stage.call("configure", get_viewport().get_visible_rect(), camera)
		projection_stage.call("set_narrative_ratio", narrative_width_ratio)
		projection_stage.call("refresh_camera")
		world.position = Vector2(1600, 1100)
		world.scale = Vector2.ONE
		if shop != null:
			shop.output_bounds = _screen_rect_to_world(camera.bounds.grow(-10.0)).intersection(TableState.WORLD_BOUNDS)
		return
	if shop != null:
		shop.output_bounds = Rect2(camera.to_world(camera.bounds.position + Vector2.ONE * 10.0), (camera.bounds.size - Vector2.ONE * 20.0) / camera.zoom).intersection(TableState.WORLD_BOUNDS)
	# 阅读时只调整呈现，不修改镜头存档和卡牌实际坐标。
	world.position = camera.offset - surface.position
	world.scale = Vector2.ONE * camera.zoom
	if narrative_width_ratio < 0.99:
		var content := Rect2()
		var has_content := false
		for stack_id: String in state.stacks:
			var stack_bounds := state.stack_rect(stack_id)
			var on_screen := Rect2(camera.to_screen(stack_bounds.position), stack_bounds.size * camera.zoom)
			if not camera.bounds.intersects(on_screen):
				continue
			content = content.merge(stack_bounds) if has_content else stack_bounds
			has_content = true
		if has_content:
			var available := Vector2(surface.size.x * narrative_width_ratio - 100.0, surface.size.y - 70.0)
			var fit := minf(1.7, minf(available.x / maxf(content.size.x, 1.0), available.y / maxf(content.size.y, 1.0)))
			world.scale = Vector2.ONE * maxf(fit, 0.25)
			world.position = Vector2(surface.size.x * narrative_width_ratio * 0.5, surface.size.y * 0.5) - content.get_center() * world.scale


func _on_viewport_size_changed() -> void:
	if not is_instance_valid(world):
		return
	if not pressed_id.is_empty() or panning:
		cancel_gesture()
	_layout()
	_refresh_world_geometry()
	if customer_lane != null:
		customer_lane.snap_resized_layout()
	_advance_flights(0.0)
	_sync_stack_progress()


func _layout() -> void:
	var area := get_viewport().get_visible_rect()
	if full_table_mode:
		area = Rect2(Vector2(24, 128), Vector2(maxf(area.size.x - 48.0, 1.0), maxf(area.size.y - 292.0, 1.0)))
	if market != null:
		market.set_viewport_size(area.size)
	if customer_lane != null:
		customer_lane.set_viewport_size(area.size)
		if chapter_runtime == null:
			area = customer_lane.board_rect()
	if area != camera.bounds:
		camera.set_bounds(area)
		surface.position = area.position
		surface.size = area.size


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_screen = event.position
		if panning:
			camera.pan(event.relative)
			camera_gesture.emit(&"pan", event.relative.length())
			get_viewport().set_input_as_handled()
		elif not pressed_id.is_empty():
			if dragging_id.is_empty() and press_at.distance_to(event.position) >= DRAG_THRESHOLD:
				_start_drag()
			if not dragging_id.is_empty():
				var sample_velocity: Vector2 = event.velocity if event.velocity.length_squared() > 0.0 else event.relative / maxf(get_process_delta_time(), 0.001)
				var velocity_scale := _drag_screen_scale if is_instance_valid(projection_stage) else camera.zoom
				drag_velocity = (sample_velocity / maxf(velocity_scale, 0.01)).limit_length(2500.0)
				_move_drag(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		mouse_screen = event.position
		if not event.pressed and event.button_index == press_button and not pressed_id.is_empty():
			_finish_drag(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and panning and event.button_index == pan_button:
			panning = false
			pan_button = MOUSE_BUTTON_NONE
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(world):
		return
	if event is InputEventMouseButton and event.pressed:
		if not _is_board_point(event.position):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom_at(event.position, 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
			camera_gesture.emit(&"zoom", 1.0)
		elif event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SPACE)):
			_begin_pan(event.button_index)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if not pressed_id.is_empty() or panning:
				return
			var card := pick_card(event.position)
			if card.is_empty():
				if event.button_index == MOUSE_BUTTON_RIGHT:
					_begin_pan(event.button_index)
				else:
					selected_id = ""
			else:
				selected_id = card
				pressed_id = card
				press_button = event.button_index
				press_at = event.position
				press_whole = event.shift_pressed or event.button_index == MOUSE_BUTTON_RIGHT
				pressed_snapshot = state.stacks[state.stack_for(card)].duplicate(true)
				_freeze_pending_cards()
		get_viewport().set_input_as_handled()


func _is_board_point(point: Vector2) -> bool:
	if not get_viewport().get_visible_rect().has_point(point):
		return false
	if market != null and market.visible and not market.slot_at(point).is_empty():
		return false
	if customer_lane != null and customer_lane.visible and not customer_lane.customer_at(point).is_empty():
		return false
	return not pointer_blocked.is_valid() or not pointer_blocked.call(point)


func _begin_pan(button: int) -> void:
	if not pressed_id.is_empty():
		return
	panning = true
	pan_button = button


func _freeze_pending_cards() -> void:
	var source := state.stack_for(pressed_id)
	var cards: Array = state.stacks[source].cards
	var first: int = 0 if press_whole else cards.find(pressed_id)
	for index in range(first, cards.size()):
		var view: TableCardView = views[cards[index]]
		view.target_position = view.position


func _start_drag() -> void:
	var probe_started := HitchProbe.stamp()
	_start_drag_impl()
	HitchProbe.record("drag_start", probe_started)


func _start_drag_impl() -> void:
	var source := state.stack_for(pressed_id)
	if source.is_empty():
		return
	var index: int = state.stacks[source].cards.find(pressed_id)
	var first_pos: Vector2 = views[pressed_id].position - Vector2(0, index * TableState.STACK_STEP if press_whole else 0.0)
	drag_offset = camera.to_world(press_at) - first_pos
	_drag_screen_scale = _card_screen_scale(first_pos)
	_drag_screen_offset = press_at - _card_screen_origin(first_pos, _drag_screen_scale)
	dragging_id = state.take_from(pressed_id, press_whole)
	if not conversation_preparation.is_empty() and _conversation_stack().is_empty():
		conversation_preparation.clear()
	_lift_drag_views()
	_refresh_combination_targets()
	if not press_whole and index > 0:
		sound.play_cue(&"split")
	else:
		sound.play_cue(&"pick")
	_sync_views()


func _move_drag(at: Vector2) -> void:
	if not state.stacks.has(dragging_id):
		return
	var probe_started := HitchProbe.stamp()
	mouse_screen = at
	state.move_stack(dragging_id, camera.to_world(at) - drag_offset)
	var blocked := pointer_blocked.is_valid() and bool(pointer_blocked.call(at))
	market_target = market.slot_at(at) if market != null and not blocked else &""
	customer_target = customer_lane.customer_at(at) if customer_lane != null and not blocked else ""
	target_id = find_drop_target() if customer_target.is_empty() and market_target.is_empty() and _is_board_point(at) else ""
	target_card = customer_target
	if not target_id.is_empty():
		target_card = state.stacks[target_id].cards.back()
	drop_action = shop.preview_action(dragging_id, target_card) if shop != null and not customer_target.is_empty() else &"stack"
	if chapter_runtime == null and shop != null and customer_target.is_empty() and not target_card.is_empty():
		drop_action = shop.preview_action(dragging_id, target_card)
	if market is ChapterMarketDock and not market_target.is_empty():
		drop_action = &"buy" if market.preview_stack(dragging_id, market_target).ok else &"reject"
	elif shop != null and not market_target.is_empty():
		drop_action = shop.preview_market_action(dragging_id, market_target)
	if not _dialogue_npc_for_drop().is_empty():
		if not customer_target.is_empty():
			drop_action = &"talk"
		else:
			drop_action = &"stack" if state.can_merge(dragging_id, target_id) else &"reject"
	if customer_lane != null:
		customer_lane.set_drop_target(customer_target, drop_action in [&"sell", &"talk"])
	if market != null:
		market.set_drop_target(market_target, drop_action in [&"buy", &"liquidate"])
	preview.visible = not target_id.is_empty() and _is_board_point(at)
	if preview.visible:
		var entry: Dictionary = state.stacks[target_id]
		preview.position = _drop_origin(target_id) + Vector2(0, entry.cards.size() * TableState.STACK_STEP) if drop_action in [&"stack", &"toggle_shop"] else entry.position
		preview.preview_size = state.stack_size(dragging_id) if drop_action in [&"stack", &"toggle_shop"] else TableState.CARD_SIZE
		preview.blocked = drop_action == &"reject"
		preview.z_index = 3500
		preview.queue_redraw()
	_sync_targets()
	HitchProbe.record("drag_move", probe_started)


func find_drop_target() -> String:
	if not state.stacks.has(dragging_id):
		return ""
	var lead := Rect2(state.stacks[dragging_id].position, TableState.CARD_SIZE)
	var best := ""
	var best_score := INF
	for id: String in state.sorted_stacks():
		if id == dragging_id or _stack_is_flying(id) or not views[state.stacks[id].cards.back()].visible:
			continue
		var entry: Dictionary = state.stacks[id]
		var action: StringName = shop.preview_action(dragging_id, entry.cards.back()) if chapter_runtime == null and shop != null else &"stack"
		if action in [&"stack", &"toggle_shop"] and not state.can_merge(dragging_id, id):
			continue
		var top: Rect2 = views[entry.cards.back()].get_visual_rect()
		var overlap := lead.intersection(top).get_area() / (TableState.CARD_SIZE.x * TableState.CARD_SIZE.y)
		if overlap < (0.20 if id == target_id else 0.30):
			continue
		var score := lead.get_center().distance_squared_to(top.get_center())
		if id == target_id:
			score *= 0.8
		if score <= best_score:
			best_score = score
			best = id
	return best


func _drop_origin(id: String) -> Vector2:
	var entry: Dictionary = state.stacks[id]
	var origin: Vector2 = views[entry.cards.front()].position
	var total_size := state.stack_size(id) + Vector2(0, state.stacks[dragging_id].cards.size() * TableState.STACK_STEP)
	return state.clamp_position(origin, total_size)


func _finish_drag(at: Vector2) -> void:
	var probe_started := HitchProbe.stamp()
	_finish_drag_impl(at)
	HitchProbe.record("drag_finish", probe_started)


func _finish_drag_impl(at: Vector2) -> void:
	if pointer_blocked.is_valid() and pointer_blocked.call(at):
		cancel_gesture()
		return
	if dragging_id.is_empty():
		_clear_gesture()
		return
	_move_drag(at)
	var conversation_npc := _dialogue_npc_for_drop()
	if drop_action == &"talk" and not conversation_npc.is_empty():
		var hero_id := ""
		for card: String in state.stacks[dragging_id].cards:
			if state.card_kind(card) == &"hero":
				hero_id = card
		var npc_card := customer_target
		cancel_gesture()
		_prepare_conversation(conversation_npc, hero_id, npc_card, true)
		return
	if drop_action == &"reject" or (not _is_board_point(at) and customer_target.is_empty() and market_target.is_empty()):
		cancel_gesture()
		return
	var landed_ids: Array = state.stacks[dragging_id].cards.duplicate()
	var fixed_id := dragging_id
	if market is ChapterMarketDock and not market_target.is_empty():
		var chapter_result: Dictionary = market.perform_stack(dragging_id, market_target)
		if not chapter_result.ok:
			cancel_gesture()
			return
		if state.stacks.has(dragging_id):
			state.move_stack(dragging_id, pressed_snapshot.position)
		market.confirm(market_target)
		_clear_gesture()
		_sync_views()
		sound.play_cue(&"stack")
		return
	if shop != null and drop_action in [&"toggle_shop", &"buy", &"sell", &"liquidate"]:
		var return_position: Vector2 = pressed_snapshot.position
		var first_index: int = pressed_snapshot.cards.find(landed_ids.front())
		return_position += Vector2(0, max(0, first_index) * TableState.STACK_STEP)
		var result: Dictionary
		if not market_target.is_empty():
			result = shop.perform_market_drop(dragging_id, market_target, return_position)
		else:
			result = shop.perform_drop(dragging_id, target_card, return_position)
		if not result.get("ok", false):
			cancel_gesture()
			return
		if not market_target.is_empty():
			market.confirm(market_target)
		_sync_views()
		_clear_gesture()
		_sync_views()
		sound.play_cue(&"stack")
		for id: String in landed_ids:
			if views.has(id):
				views[id].land()
		return
	if not target_id.is_empty():
		if not state.can_merge(dragging_id, target_id):
			cancel_gesture()
			return
		fixed_id = target_id
		state.move_stack(target_id, _drop_origin(target_id))
		state.merge(dragging_id, target_id)
		sound.play_cue(&"stack")
	else:
		sound.play_cue(&"drop")
	state.settle_overlaps(fixed_id)
	_clear_gesture(false)
	_sync_views()
	for id: String in landed_ids:
		if views.has(id):
			views[id].land()
	if chapter_runtime != null:
		if conversation_npc.is_empty():
			stack_combined.emit(fixed_id)
			return
		chapter_runtime.advance(0.0, true)
		if not chapter_runtime.options_for_stack(fixed_id).is_empty():
			stack_combined.emit(fixed_id)
			return
	if not conversation_npc.is_empty():
		var hero_id := ""
		var npc_card := ""
		for card: String in state.stacks[fixed_id].cards:
			if state.card_kind(card) == &"hero":
				hero_id = card
			elif String(state.cards[card].metadata.get("npc_id", "")) == conversation_npc:
				npc_card = card
		_prepare_conversation(conversation_npc, hero_id, npc_card)


func _prepare_conversation(npc_id: String, hero_id: String, npc_card: String, queued: bool = false) -> void:
	if chapter_runtime != null and chapter_runtime.story_options(npc_id).is_empty():
		return
	if chapter_runtime != null and (state.sigil_instance_locked(hero_id) or state.sigil_instance_locked(npc_card)):
		return
	conversation_preparation = {"npc_id": npc_id, "hero_id": hero_id, "npc_card": npc_card, "queued": queued, "elapsed": 0.0}
	_sync_stack_progress()


func _conversation_stack() -> String:
	if conversation_preparation.is_empty():
		return ""
	var hero_id: String = conversation_preparation.hero_id
	var npc_card: String = conversation_preparation.npc_card
	if not state.cards.has(hero_id) or not state.cards.has(npc_card):
		return ""
	var stack := state.stack_for(hero_id)
	if stack.is_empty():
		return ""
	if conversation_preparation.queued:
		return stack if state.stack_for(npc_card).is_empty() else ""
	return stack if state.stack_for(npc_card) == stack else ""


func _advance_conversation_preparation(delta: float) -> void:
	if conversation_preparation.is_empty():
		return
	var stack := _conversation_stack()
	if stack.is_empty():
		conversation_preparation.clear()
		return
	if simulation_paused or get_tree().paused or not pressed_id.is_empty() or panning or _stack_is_flying(stack):
		return
	conversation_preparation.elapsed += maxf(delta, 0.0)
	if float(conversation_preparation.elapsed) < CONVERSATION_PREPARE_SECONDS:
		return
	var npc_id: String = conversation_preparation.npc_id
	conversation_preparation.clear()
	_sync_stack_progress()
	dialogue_requested.emit(npc_id)


func _dialogue_npc_for_drop() -> String:
	if not state.stacks.has(dragging_id):
		return ""
	var dragged: Array = state.stacks[dragging_id].cards
	var receiving: Array = []
	if not customer_target.is_empty():
		receiving = [customer_target]
	elif state.stacks.has(target_id):
		receiving = state.stacks[target_id].cards
	return _dialogue_npc_for_cards(dragged,receiving)


func _dialogue_npc_for_cards(dragged: Array, receiving: Array) -> String:
	for side: Array in [dragged, receiving]:
		var opposite: Array = receiving if side == dragged else dragged
		for id: String in side:
			if not state.cards.has(id) or state.card_kind(id) != &"hero":
				continue
			for other: String in opposite:
				if not state.cards.has(other):
					continue
				var npc_id := String(state.cards[other].metadata.get("npc_id", ""))
				if not ContentCatalog.npc_definition(npc_id).is_empty():
					return npc_id
	return ""


func _refresh_combination_targets() -> void:
	combination_targets.clear()
	if not state.stacks.has(dragging_id):
		return
	var probe_started := HitchProbe.stamp()
	var dragged: Array = state.stacks[dragging_id].cards
	var discovered: Array[String] = progress.discovered_recipes if progress != null else []
	for stack_id: String in state.sorted_stacks():
		if stack_id==dragging_id or _stack_is_flying(stack_id) or not state.can_merge(dragging_id,stack_id) or not views[state.stacks[stack_id].cards.back()].visible:
			continue
		var receiving: Array = state.stacks[stack_id].cards
		var definition_ids: Array[String] = []
		for card_id: String in dragged+receiving:
			var definition_id := state.definition_id_for_card(card_id)
			if not definition_id.is_empty():
				definition_ids.append(definition_id)
		if not ContentCatalog.discovered_combination_recipe_for_cards(definition_ids,discovered).is_empty():
			combination_targets[stack_id] = true
	HitchProbe.record("drag_combination_hints", probe_started)


func _clear_gesture(sync_targets: bool = true) -> void:
	_lower_drag_views()
	pressed_id = ""
	pressed_snapshot = {}
	press_button = MOUSE_BUTTON_NONE
	dragging_id = ""
	target_id = ""
	target_card = ""
	customer_target = ""
	market_target = &""
	drop_action = &"stack"
	combination_targets.clear()
	if customer_lane != null:
		customer_lane.set_drop_target("", false)
	if market != null:
		market.set_drop_target(&"", false)
	drag_velocity = Vector2.ZERO
	preview.visible = false
	panning = false
	if sync_targets:
		_sync_targets()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func cancel_gesture() -> void:
	var probe_started := HitchProbe.stamp()
	if not dragging_id.is_empty() and not pressed_snapshot.is_empty():
		var original_id: String = pressed_snapshot.id
		if dragging_id != original_id:
			state.stacks.erase(dragging_id)
		state.stacks[original_id] = pressed_snapshot.duplicate(true)
	_clear_gesture(false)
	_sync_views()
	HitchProbe.record("drag_cancel", probe_started)


func pick_card(screen: Vector2) -> String:
	var point := camera.to_world(screen)
	var ordered := state.sorted_stacks()
	ordered.reverse()
	for id: String in ordered:
		if _stack_is_flying(id):
			continue
		var cards: Array = state.stacks[id].cards.duplicate()
		cards.reverse()
		for card: String in cards:
			if not views.has(card):
				continue
			var view: TableCardView = views[card]
			if not view.visible:
				continue
			var hit_point := screen if view.get_parent() == drag_root else point
			if view.hit_test(hit_point):
				return card
	return ""


func _sync_views(instant: bool = false) -> void:
	var probe_started := HitchProbe.stamp()
	var alive := {}
	var views_started := HitchProbe.stamp()
	for entry: Dictionary in state.stacks.values():
		for card: String in entry.cards:
			alive[card] = true
			if not views.has(card):
				var view := TableCardView.new()
				view.card_id = card
				if _pending_flights.has(card):
					var flight: CardFlight = _pending_flights[card]
					_pending_flights.erase(card)
					flights[card] = flight
					drag_root.add_child(view)
					flight.advance(view, camera.to_screen(state.card_position(card) + TableState.CARD_SIZE * 0.5), _card_screen_scale(state.card_position(card)), 0.0, reduced_motion)
					view.reduced_motion = reduced_motion
					view.play_unfold()
				else:
					_pending_flights.erase(card)
					world.add_child(view)
					view.snap_to(state.card_position(card))
				views[card] = view
			var card_view: TableCardView = views[card]
			if not card_view.visible:
				card_view.land()
			card_view.visible = true
	for card: String in _pending_flights.keys():
		if not alive.has(card):
			_pending_flights.erase(card)
	for card: String in views.keys():
		if not alive.has(card):
			flights.erase(card)
			_pending_flights.erase(card)
			_retire_view(views[card])
			views.erase(card)
	if not selected_id.is_empty() and not alive.has(selected_id):
		selected_id = ""
	HitchProbe.record("sync_view_nodes", views_started)
	var targets_started := HitchProbe.stamp()
	_sync_targets()
	HitchProbe.record("sync_view_targets", targets_started)
	if instant:
		for view: TableCardView in views.values():
			view.snap_to(view.target_position)
	HitchProbe.record("sync_card_views", probe_started)


func _sync_targets() -> void:
	var positions_started := HitchProbe.stamp()
	var layer := 0
	for id: String in state.sorted_stacks():
		var entry: Dictionary = state.stacks[id]
		for index in entry.cards.size():
			var view: TableCardView = views[entry.cards[index]]
			var world_position: Vector2 = entry.position + Vector2(0, index * TableState.STACK_STEP)
			if not flights.has(view.card_id):
				if view.get_parent() == drag_root:
					if is_instance_valid(projection_stage) and id == dragging_id:
						view.target_position = mouse_screen - _drag_screen_offset + camera.to_screen(world_position) - camera.to_screen(entry.position)
						view.scale = Vector2.ONE * _drag_screen_scale
					else:
						view.target_position = _card_screen_origin(world_position)
						view.scale = Vector2.ONE * _card_screen_scale(world_position)
				else:
					view.target_position = world_position
					view.scale = Vector2.ONE
				view.z_index = 3600 + index if id == dragging_id else layer
			view.drag_order = index
			view.stack_count = entry.cards.size() if index == entry.cards.size() - 1 else 0
			layer += 1
	HitchProbe.record("sync_target_positions", positions_started)
	var flags_started := HitchProbe.stamp()
	_update_view_flags()
	HitchProbe.record("sync_target_flags", flags_started)


func _update_view_flags() -> void:
	for id: String in state.stacks:
		for card: String in state.stacks[id].cards:
			var view: TableCardView = views[card]
			if not view.visible:
				continue
			view.dragging = id == dragging_id
			view.pressed = card == pressed_id or (press_whole and not pressed_id.is_empty() and state.stack_for(pressed_id) == id)
			view.hovered = card == hovered_id and dragging_id.is_empty() and not panning and not flights.has(card)
			view.selected = card == selected_id
			view.drop_target = id == target_id
			view.combination_hint = not dragging_id.is_empty() and id in combination_targets and card==state.stacks[id].cards.back()
			view.drag_velocity = drag_velocity
			view.reduced_motion = reduced_motion
			var kind := state.card_kind(card)
			var content_started := HitchProbe.stamp()
			CardContent.apply(view, kind, shop.is_open if shop != null else false, player_name if kind == &"hero" else "")
			HitchProbe.record("card_content_" + String(kind), content_started)
	_sync_stack_progress()
	if panning or not dragging_id.is_empty():
		Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN if drop_action == &"reject" else Input.CURSOR_DRAG)
	elif not hovered_id.is_empty() and _is_board_point(mouse_screen):
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func refresh_content() -> void:
	_sync_views()


func replace_state(next_state: TableState) -> void:
	conversation_preparation.clear()
	cancel_gesture()
	flights.clear()
	_pending_flights.clear()
	for parent: Node in [world, drag_root]:
		if parent == null:
			continue
		for child: Node in parent.get_children():
			if child is TableCardView:
				child.hide()
				child.queue_free()
	views.clear()
	selected_id = ""
	hovered_id = ""
	state = next_state
	_reclamp_stacks()
	_layout()
	_sync_views(true)
	_sync_stack_progress()


func _reclamp_stacks() -> void:
	for id: String in state.stacks:
		state.move_stack(id, state.stacks[id].position)


func stack_screen_rect(id: String) -> Rect2:
	if not state.stacks.has(id):
		return Rect2()
	var result := Rect2()
	var found := false
	for card: String in state.stacks[id].cards:
		if not views.has(card):
			continue
		var view: TableCardView = views[card]
		var rect := view.get_visual_rect()
		if view.get_parent() != drag_root:
			rect = _world_rect_to_screen(rect)
		result = result.merge(rect) if found else rect
		found = true
	return result


func _sync_stack_progress() -> void:
	if stack_progress == null:
		return
	var rows: Array[Dictionary] = []
	var id := opening.work_stack_id() if opening != null and opening.stage == &"explore" else ""
	var progress := opening.progress() if not id.is_empty() else 0.0
	if id.is_empty():
		id = _conversation_stack()
		if not id.is_empty():
			progress = clampf(float(conversation_preparation.elapsed) / CONVERSATION_PREPARE_SECONDS, 0.0, 1.0)
	if not id.is_empty():
		rows.append({"stack_id": id, "progress": progress})
	if exploration != null:
		rows.append_array(exploration.work_progress())
	if chapter_runtime != null:
		rows.append_array(chapter_runtime.work_progress())
	while _extra_stack_progress.size() < maxi(0, rows.size() - 1):
		var extra := StackProgressView.new()
		stack_progress.get_parent().add_child(extra)
		_extra_stack_progress.append(extra)
	var all_views: Array[StackProgressView] = [stack_progress]
	all_views.append_array(_extra_stack_progress)
	for index in all_views.size():
		if index >= rows.size():
			all_views[index].clear()
		else:
			_set_work_progress(all_views[index], rows[index].stack_id, rows[index].progress)


func _set_work_progress(view: StackProgressView, id: String, progress: float) -> void:
	if id.is_empty() or not state.stacks.has(id) or _stack_is_flying(id):
		view.clear()
		return
	var rect := stack_screen_rect(id)
	if not rect.has_area():
		view.clear()
		return
	var screen_scale := _card_screen_scale(state.stacks[id].position)
	var height := clampf(12.0 * screen_scale, 7.0, 20.0)
	var gap := clampf(8.0 * screen_scale, 5.0, 14.0)
	var progress_rect := Rect2(Vector2(rect.position.x, rect.position.y - height - gap), Vector2(rect.size.x, height))
	view.set_progress(id, progress, progress_rect)


func _lift_drag_views() -> void:
	if drag_root == null:
		return
	for card: String in state.stacks[dragging_id].cards:
		var view: TableCardView = views[card]
		var at := _card_screen_origin(view.position, _drag_screen_scale)
		view.reparent(drag_root, false)
		view.snap_to(at)
		view.scale = Vector2.ONE * _drag_screen_scale


func _lower_drag_views() -> void:
	if drag_root == null:
		return
	for view: TableCardView in views.values():
		if view.get_parent() != drag_root or flights.has(view.card_id):
			continue
		var at := camera.to_world(view.position)
		if is_instance_valid(projection_stage):
			at = camera.to_world(view.position + TableState.CARD_SIZE * view.scale * 0.5) - TableState.CARD_SIZE * 0.5
		view.reparent(world, false)
		view.position = at
		view.target_position = at
		view.scale = Vector2.ONE


func _retire_view(view: TableCardView) -> void:
	view.target_position = view.position
	view.dragging = false
	view.hovered = false
	var tween := view.create_tween().set_parallel(true)
	tween.tween_property(view, "modulate:a", 0.0, 0.14)
	tween.tween_property(view, "scale", view.scale * 0.9, 0.14)
	tween.chain().tween_callback(view.queue_free)


func queue_output_flights(card_ids: Array[String], source_id: StringName) -> void:
	var origin := Vector2.INF
	if market != null and source_id in MarketDock.IDS:
		origin = market.slot_origin(source_id)
	elif customer_lane != null and customer_lane.views.has(String(source_id)):
		origin = customer_lane.customer_origin(String(source_id))
	elif views.has(String(source_id)):
		var source_view: TableCardView = views[String(source_id)]
		origin = source_view.get_visual_rect().get_center()
		if source_view.get_parent() != drag_root:
			origin = camera.to_screen(origin)
	if not origin.is_finite():
		push_error("Cannot animate output without a visible source: " + String(source_id))
		return
	for index in card_ids.size():
		_pending_flights[card_ids[index]] = CardFlight.new(origin, source_id, index)


func queue_world_output_flights(card_ids: Array[String], source_position: Vector2, source_id: String) -> void:
	var origin := camera.to_screen(source_position + TableState.CARD_SIZE * 0.5)
	queue_screen_output_flights(card_ids, origin, source_id)


func queue_screen_output_flights(card_ids: Array[String], origin: Vector2, source_id: String) -> void:
	for index in card_ids.size():
		if state.cards.has(card_ids[index]) and state.cards[card_ids[index]].zone == &"board":
			_pending_flights[card_ids[index]] = CardFlight.new(origin, StringName(source_id), index)
	_sync_views()


func _advance_flights(delta: float) -> void:
	for card: String in flights.keys():
		if not views.has(card) or not state.cards.has(card):
			flights.erase(card)
			continue
		var view: TableCardView = views[card]
		var destination := state.card_position(card)
		var flight: CardFlight = flights[card]
		if flight.advance(view, camera.to_screen(destination + TableState.CARD_SIZE * 0.5), _card_screen_scale(destination), delta, reduced_motion):
			flights.erase(card)
			view.reparent(world, false)
			view.scale = Vector2.ONE
			view.snap_to(destination)
			view.land()
			_sync_targets()


func _stack_is_flying(stack: String) -> bool:
	for card: String in state.stacks[stack].cards:
		if flights.has(card):
			return true
	return false


func _card_screen_scale(position: Vector2) -> float:
	if not is_instance_valid(projection_stage):
		return camera.zoom
	var middle := position + Vector2(0.0, TableState.CARD_SIZE.y * 0.5)
	return maxf(camera.to_screen(middle).distance_to(camera.to_screen(middle + Vector2(TableState.CARD_SIZE.x, 0.0))) / TableState.CARD_SIZE.x, 0.01)


func _card_screen_origin(position: Vector2, screen_scale: float = -1.0) -> Vector2:
	if not is_instance_valid(projection_stage):
		return camera.to_screen(position)
	var factor := _card_screen_scale(position) if screen_scale < 0.0 else screen_scale
	return camera.to_screen(position + TableState.CARD_SIZE * 0.5) - TableState.CARD_SIZE * factor * 0.5


func _world_rect_to_screen(rect: Rect2) -> Rect2:
	var result := Rect2(camera.to_screen(rect.position), Vector2.ZERO)
	for corner in [Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		result = result.expand(camera.to_screen(corner))
	return result


func _screen_rect_to_world(rect: Rect2) -> Rect2:
	var result := Rect2(camera.to_world(rect.position), Vector2.ZERO)
	for corner in [Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		result = result.expand(camera.to_world(corner))
	return result
