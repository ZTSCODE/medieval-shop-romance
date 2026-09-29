class_name ShopSession
extends Node

signal changed
signal feedback(key: String)
signal outputs_created(card_ids: Array[String], source_id: StringName)
signal customer_arrived(npc_id: StringName)
signal transaction_completed(action: StringName, npc_id: StringName)

const ARRIVAL_INTERVAL := 12.0
const MAX_CUSTOMERS := 3
const MAX_ARRIVALS_PER_DAY := 6
const WAIT_SECONDS := 55.0
const BUY_PRICE := 1
const SELL_PRICE := 2
const LIQUIDATE_PRICE := 1
const FIRST_ARRIVAL_SECONDS := 3.0
const TIMER_EPSILON := 0.00001

var state: TableState
var output_bounds := TableState.WORLD_BOUNDS
var is_open := false
var customers: Array[String] = []
var arrival_remaining := FIRST_ARRIVAL_SECONDS
var arrivals_today := 0
var sales_count := 0
var next_ticket := 1


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func setup(table: TableState) -> void:
	state = table
	state.stacks.clear()
	state.cards.clear()
	is_open = false
	customers.clear()
	arrival_remaining = FIRST_ARRIVAL_SECONDS
	arrivals_today = 0
	sales_count = 0
	next_ticket = 1
	for entry: Dictionary in ContentCatalog.initial_cards():
		var at: Array = entry.get("position", [0.0, 0.0])
		state.create_defined(String(entry.get("definition_id", "")), Vector2(float(at[0]), float(at[1])), int(entry.get("count", 1)))
	changed.emit()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if state == null or delta <= 0.0 or not is_finite(delta):
		return
	var remaining := delta
	var structure_changed := _prune_customers()
	while remaining > TIMER_EPSILON:
		var step := remaining
		for card: String in customers:
			step = minf(step, maxf(float(state.cards[card].metadata.remaining), 0.0))
		var arrival_active := _can_arrive()
		if arrival_active:
			step = minf(step, maxf(arrival_remaining, 0.0))
		for card: String in customers:
			var metadata: Dictionary = state.cards[card].metadata
			metadata.remaining = maxf(float(metadata.remaining) - step, 0.0)
		if arrival_active:
			arrival_remaining = maxf(arrival_remaining - step, 0.0)
		remaining -= step
		var expired: Array[String] = []
		for card: String in customers:
			if float(state.cards[card].metadata.remaining) <= TIMER_EPSILON:
				expired.append(card)
		for card: String in expired:
			customers.erase(card)
			state.remove_card(card)
			structure_changed = true
		if not expired.is_empty():
			feedback.emit("SHOP_CUSTOMER_LEFT")
		if _can_arrive() and arrival_remaining <= TIMER_EPSILON:
			if _add_customer():
				structure_changed = true
			arrival_remaining = ARRIVAL_INTERVAL
		elif step <= TIMER_EPSILON and expired.is_empty():
			break
	if structure_changed:
		changed.emit()


func _can_arrive() -> bool:
	return is_open and customers.size() < MAX_CUSTOMERS and arrivals_today < MAX_ARRIVALS_PER_DAY and state.card_count() < TableState.MAX_CARDS


func _add_customer() -> bool:
	var npc_ids := ContentCatalog.shop_npc_ids()
	var npc_id := ""
	for offset in npc_ids.size():
		var candidate: String = npc_ids[(next_ticket - 1 + offset) % npc_ids.size()]
		var already_waiting := false
		for existing: String in customers:
			if state.cards[existing].metadata.get("npc_id", "") == candidate:
				already_waiting = true
				break
		if not already_waiting:
			npc_id = candidate
			break
	if npc_id.is_empty():
		return false
	var card := state.create_queue_card(&"customer")
	if card.is_empty():
		return false
	state.cards[card].metadata = {
		"ticket": next_ticket,
		"remaining": WAIT_SECONDS,
		"total_wait": WAIT_SECONDS,
		"requested_kind": &"goods",
		"npc_id": npc_id,
	}
	next_ticket += 1
	customers.append(card)
	arrivals_today += 1
	customer_arrived.emit(StringName(npc_id))
	return true


func _prune_customers() -> bool:
	var removed := false
	for card: String in customers.duplicate():
		if not state.cards.has(card) or state.card_kind(card) != &"customer" or state.cards[card].zone != &"queue":
			customers.erase(card)
			removed = true
	return removed


func on_day_started(_day: int) -> void:
	arrivals_today = 0
	changed.emit()


func preview_action(source_stack: String, target_card: String) -> StringName:
	if state == null or not state.stacks.has(source_stack) or not state.cards.has(target_card):
		return &"reject"
	var source_cards: Array = state.stacks[source_stack].cards
	if source_cards.is_empty() or target_card in source_cards:
		return &"reject"
	if state.cards[target_card].zone == &"queue":
		if target_card in customers and state.card_kind(target_card) == &"customer":
			var requested := StringName(state.cards[target_card].metadata.get("requested_kind", &"goods"))
			if _is_pure(source_stack, requested):
				return &"sell"
		return &"reject"
	var target_stack := state.stack_for(target_card)
	if target_stack.is_empty():
		return &"reject"
	if _is_shop_combination(source_stack, target_stack):
		return &"toggle_shop" if state.can_merge(source_stack, target_stack) else &"reject"
	return &"stack" if state.can_merge(source_stack, target_stack) else &"reject"


func preview_market_action(source_stack: String, market_id: StringName) -> StringName:
	if state == null or not state.stacks.has(source_stack):
		return &"reject"
	match market_id:
		&"supply":
			if _is_pure(source_stack, &"coin") and state.stacks[source_stack].cards.size() >= BUY_PRICE:
				return &"buy"
		&"sell":
			if _is_pure(source_stack, &"goods"):
				return &"liquidate"
	return &"reject"


func _is_pure(stack: String, kind: StringName) -> bool:
	if not state.stacks.has(stack) or state.stacks[stack].cards.is_empty():
		return false
	for card: String in state.stacks[stack].cards:
		if state.card_kind(card) != kind:
			return false
	return true


func _is_shop_combination(source: String, target: String) -> bool:
	if state.stacks[source].cards.size() != 1 or state.stacks[target].cards.size() != 1:
		return false
	var source_kind := state.card_kind(state.stacks[source].cards[0])
	var target_kind := state.card_kind(state.stacks[target].cards[0])
	return (source_kind == &"hero" and target_kind == &"shop") or (source_kind == &"shop" and target_kind == &"hero")


func perform_drop(source_stack: String, target_card: String, return_position: Vector2) -> Dictionary:
	var action := preview_action(source_stack, target_card)
	var result := _new_result(action)
	var npc_id: StringName = StringName(state.cards[target_card].metadata.get("npc_id", "")) if state.cards.has(target_card) else &""
	match action:
		&"toggle_shop":
			var target_stack := state.stack_for(target_card)
			if not state.merge(source_stack, target_stack):
				return result
			is_open = not is_open
			if is_open:
				arrival_remaining = FIRST_ARRIVAL_SECONDS
			result.ok = true
			feedback.emit("SHOP_OPENED" if is_open else "SHOP_CLOSED")
		&"sell":
			if not _has_output_capacity(2, SELL_PRICE):
				feedback.emit("SHOP_TABLE_FULL")
				return result
			var goods: String = state.stacks[source_stack].cards.back()
			state.remove_card(goods)
			state.remove_card(target_card)
			customers.erase(target_card)
			result.consumed.append_array([goods, target_card])
			state.move_stack(source_stack, return_position)
			_add_output(&"coin", SELL_PRICE, return_position, result)
			sales_count += 1
			result.ok = true
			feedback.emit("SHOP_SOLD")
		&"reject":
			feedback.emit("SHOP_INVALID_DROP")
	_notify_transaction(result, StringName(target_card))
	if result.ok:
		transaction_completed.emit(action, npc_id)
	return result


func perform_market_drop(source_stack: String, market_id: StringName, return_position: Vector2) -> Dictionary:
	var action := preview_market_action(source_stack, market_id)
	var result := _new_result(action)
	if action == &"reject":
		feedback.emit("SHOP_INVALID_DROP")
		return result
	var consumed_count := BUY_PRICE if action == &"buy" else 1
	var output_count := 1 if action == &"buy" else LIQUIDATE_PRICE
	if not _has_output_capacity(consumed_count, output_count):
		feedback.emit("SHOP_TABLE_FULL")
		return result
	var payment: Array = state.stacks[source_stack].cards.slice(-consumed_count)
	for card: String in payment:
		state.remove_card(card)
		result.consumed.append(card)
	state.move_stack(source_stack, return_position)
	_add_output(&"goods" if action == &"buy" else &"coin", output_count, return_position, result)
	result.ok = true
	feedback.emit("SHOP_BOUGHT" if action == &"buy" else "SHOP_LIQUIDATED")
	_notify_transaction(result, market_id)
	transaction_completed.emit(action, &"")
	return result


func _new_result(action: StringName) -> Dictionary:
	return {
		"ok": false,
		"action": action,
		"created": [] as Array[String],
		"created_stacks": [] as Array[String],
		"consumed": [] as Array[String],
	}


func _notify_transaction(result: Dictionary, source_id: StringName) -> void:
	if not result.ok:
		return
	if not result.created.is_empty():
		outputs_created.emit(result.created.duplicate(), source_id)
	changed.emit()


func _has_output_capacity(consumed_count: int, output_count: int) -> bool:
	return output_count > 0 and output_count <= TableState.MAX_STACK and state.card_count() - consumed_count + output_count <= TableState.MAX_CARDS


func _add_output(kind: StringName, count: int, return_position: Vector2, result: Dictionary) -> void:
	var at := _output_position(return_position, count)
	var stack := state.create_typed(kind, at, count)
	result.created_stacks.append(stack)
	result.created.append_array(state.stacks[stack].cards)


func _output_position(return_position: Vector2, count: int) -> Vector2:
	var size := TableState.CARD_SIZE + Vector2(0, (count - 1) * TableState.STACK_STEP)
	var first := state.clamp_position(return_position + Vector2(155, 0), size)
	var candidates: Array[Vector2] = [first, state.clamp_position(return_position + Vector2(0, TableState.CARD_SIZE.y + 34), size)]
	for ring in range(1, 9):
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP, Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			candidates.append(state.clamp_position(first + direction * Vector2(155, size.y + 22) * ring, size))
	for at: Vector2 in candidates:
		if output_bounds.encloses(Rect2(at, size)) and _output_is_clear(at, size):
			return at
	for at: Vector2 in _visible_output_candidates(size, return_position):
		if _output_is_clear(at, size):
			return at
	for at: Vector2 in candidates:
		if _output_is_clear(at, size):
			return at
	return first


func _visible_output_candidates(size: Vector2, near: Vector2) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	var bounds := output_bounds.intersection(TableState.WORLD_BOUNDS.grow(-20))
	if bounds.size.x < size.x or bounds.size.y < size.y:
		return candidates
	var first := bounds.position
	var last := bounds.end - size
	var columns := ceili((last.x - first.x) / 24.0)
	var rows := ceili((last.y - first.y) / 24.0)
	for row in range(rows + 1):
		for column in range(columns + 1):
			candidates.append(Vector2(minf(first.x + column * 24.0, last.x), minf(first.y + row * 24.0, last.y)))
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(near) < b.distance_squared_to(near))
	return candidates


func _output_is_clear(at: Vector2, size: Vector2) -> bool:
	var rect := Rect2(at, size).grow(8)
	for id: String in state.stacks:
		if rect.intersects(state.stack_rect(id).grow(8)):
			return false
	return true
