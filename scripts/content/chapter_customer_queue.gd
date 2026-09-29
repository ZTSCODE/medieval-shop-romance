class_name ChapterCustomerQueue
extends ShopSession

const MIN_SECONDS := 0.001
const MAX_SALE_RECORDS := 8192
const SALE_RECEIPT_KIND := "chapter_customer_sale"

var chapter: ChapterRuntime
var catalog: Dictionary = {}
var current_day := 1
var arrival_screen_origin := Vector2.ZERO
var sale_records: Array[Dictionary] = []
var arrival_records: Array[Dictionary] = []


static func validate_catalog(data: Variant, table: TableState) -> String:
	if not data is Dictionary or data.keys().size() != 8:
		return "invalid_customer_catalog_fields"
	for key: String in ["schema_version", "module_id", "first_arrival_seconds", "arrival_interval_seconds",
		"patience_seconds", "max_waiting", "max_arrivals_per_day", "orders"]:
		if not data.has(key):
			return "invalid_customer_catalog_fields"
	if data.schema_version != 1 or data.module_id != "chapter_01":
		return "invalid_customer_catalog_identity"
	for key: String in ["first_arrival_seconds", "arrival_interval_seconds", "patience_seconds"]:
		if not data[key] is float and not data[key] is int:
			return "invalid_customer_timing"
		if not is_finite(float(data[key])) or float(data[key]) < MIN_SECONDS or float(data[key]) > 120.0:
			return "invalid_customer_timing"
	if not _integer(data.max_waiting, 1, 3) or not _integer(data.max_arrivals_per_day, int(data.max_waiting), 8):
		return "invalid_customer_capacity"
	if not data.orders is Array or data.orders.is_empty() or data.orders.size() > 8:
		return "invalid_customer_orders"
	var ids: Dictionary = {}
	for order: Variant in data.orders:
		if not order is Dictionary or order.keys().size() != 4:
			return "invalid_customer_order_fields"
		for key: String in ["id", "item_card_id", "coin_count", "requires_facts"]:
			if not order.has(key):
				return "invalid_customer_order_fields"
		if not order.id is String or not order.id.begins_with("order.ch01.") or ids.has(order.id):
			return "invalid_customer_order_id"
		ids[order.id] = true
		if not order.item_card_id is String or table.content_card_definition(order.item_card_id).is_empty() or not table.content_card_definition(order.item_card_id).get("sellable", false):
			return "invalid_customer_order_item"
		if not _integer(order.coin_count, 1, 6):
			return "invalid_customer_order_price"
		if not order.requires_facts is Array or order.requires_facts.size() > 8:
			return "invalid_customer_order_facts"
		var known: Dictionary = {}
		for fact: Variant in order.requires_facts:
			if not fact is String or not fact.begins_with("fact.ch01.") or known.has(fact):
				return "invalid_customer_order_facts"
			known[fact] = true
	return ""


static func validate_sale_receipt(transaction_id: String, receipt: Variant, orders_catalog: Variant, table: TableState) -> String:
	var fields := ["kind", "version", "status", "transaction_id", "ticket", "day", "order_id", "npc_id",
		"item_definition_id", "input_instance_ids", "output_instance_ids", "source_position"]
	if not receipt is Dictionary or receipt.size() != fields.size():
		return "invalid_customer_sale_receipt_fields"
	for field: String in fields:
		if not receipt.has(field):
			return "invalid_customer_sale_receipt_fields"
	if receipt.kind != SALE_RECEIPT_KIND or receipt.version != 1 or receipt.status != "completed" or not _integer(receipt.ticket, 1, 2147483647) or transaction_id != "customer/%d" % int(receipt.ticket) or receipt.transaction_id != transaction_id:
		return "invalid_customer_sale_receipt_identity"
	if not _integer(receipt.day, 1, 1000000000) or not receipt.npc_id is String or String(receipt.npc_id) not in ContentCatalog.shop_npc_ids():
		return "invalid_customer_sale_participant"
	if not orders_catalog is Dictionary or not orders_catalog.get("orders") is Array:
		return "customer_sale_catalog_required"
	var order: Dictionary = {}
	for candidate: Dictionary in orders_catalog.orders:
		if candidate.id == receipt.order_id:
			order = candidate
			break
	if order.is_empty() or receipt.item_definition_id != order.item_card_id:
		return "customer_sale_wrong_order"
	if not receipt.input_instance_ids is Array or receipt.input_instance_ids.size() != 2 or not receipt.output_instance_ids is Array or receipt.output_instance_ids.size() != int(order.coin_count):
		return "customer_sale_wrong_quantity"
	var used: Dictionary = {}
	for id: Variant in receipt.input_instance_ids + receipt.output_instance_ids:
		if not _card_instance(id, table.next_card_id) or used.has(id):
			return "customer_sale_invalid_instances"
		used[id] = true
	for id: String in receipt.input_instance_ids:
		if table.cards.has(id):
			return "customer_sale_input_reappeared"
	if not receipt.source_position is Array or receipt.source_position.size() != 2:
		return "customer_sale_invalid_placement"
	for coordinate: Variant in receipt.source_position:
		if not coordinate is int and not coordinate is float:
			return "customer_sale_invalid_placement"
	var point := Vector2(float(receipt.source_position[0]), float(receipt.source_position[1]))
	if not is_finite(point.x) or not is_finite(point.y) or not TableState.WORLD_BOUNDS.encloses(Rect2(point, TableState.CARD_SIZE)):
		return "customer_sale_invalid_placement"
	for coin: String in receipt.output_instance_ids:
		if table.cards.has(coin):
			if table.definition_id_for_card(coin) != "card.coin" or table.cards[coin].metadata.get("production_transaction_id") != transaction_id or table.cards[coin].metadata.get("production_source_position") != receipt.source_position:
				return "customer_sale_output_mismatch"
	return ""


static func _card_instance(value: Variant, next_id: int) -> bool:
	if not value is String or not value.begins_with("card_"):
		return false
	var suffix: String = value.trim_prefix("card_")
	return suffix.is_valid_int() and int(suffix) >= 1 and int(suffix) < next_id and value == "card_%04d" % int(suffix)


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and float(value) >= minimum and float(value) <= maximum


func configure_chapter(runtime: ChapterRuntime, day: int = 1) -> Dictionary:
	chapter = runtime
	if chapter == null:
		catalog.clear()
		arrival_records.clear()
		sale_records.clear()
		return {"ok": true}
	state = chapter.table
	catalog = chapter.package.get("customer_catalog", {}).duplicate(true)
	var error := validate_catalog(catalog, state)
	if not error.is_empty():
		return {"ok": false, "error": error}
	current_day = maxi(1, day)
	_restore_from_table()
	changed.emit()
	return {"ok": true}


func sync_chapter_state() -> void:
	if chapter == null:
		return
	var was_open := is_open
	is_open = chapter.shop_open()
	if is_open and not was_open:
		arrival_remaining = float(catalog.first_arrival_seconds)
	_store_shop_state()
	changed.emit()


func advance(delta: float) -> void:
	if chapter == null:
		super.advance(delta)
		return
	if _shop_card_id().is_empty() or delta <= 0.0 or not is_finite(delta):
		return
	is_open = chapter.shop_open()
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
			var customer: Dictionary = state.cards[card].metadata
			customer.remaining = maxf(float(customer.remaining) - step, 0.0)
		if arrival_active:
			arrival_remaining = maxf(arrival_remaining - step, 0.0)
		remaining -= step
		var expired: Array[String] = []
		for card: String in customers:
			if float(state.cards[card].metadata.remaining) <= TIMER_EPSILON:
				expired.append(card)
		for card: String in expired:
			_mark_arrival_status(int(state.cards[card].metadata.ticket), "left")
			customers.erase(card)
			state.remove_card(card)
			structure_changed = true
		if not expired.is_empty():
			feedback.emit("SHOP_CUSTOMER_LEFT")
		if _can_arrive() and arrival_remaining <= TIMER_EPSILON:
			if _add_customer():
				structure_changed = true
			arrival_remaining = float(catalog.arrival_interval_seconds)
		elif step <= TIMER_EPSILON and expired.is_empty():
			break
	_store_shop_state()
	if structure_changed:
		changed.emit()


func on_day_started(day: int) -> void:
	if chapter == null:
		super.on_day_started(day)
		return
	if day <= current_day:
		return
	current_day = day
	arrivals_today = 0
	arrival_remaining = float(catalog.first_arrival_seconds)
	_store_shop_state()
	changed.emit()


func _can_arrive() -> bool:
	if chapter == null:
		return super._can_arrive()
	return is_open and customers.size() < int(catalog.max_waiting) and arrivals_today < int(catalog.max_arrivals_per_day) and arrival_records.size() < MAX_SALE_RECORDS and state.card_count() < TableState.MAX_CARDS and not _available_orders().is_empty()


func _add_customer() -> bool:
	if chapter == null:
		return super._add_customer()
	var possible := _available_orders()
	var npc_ids := ContentCatalog.shop_npc_ids()
	if possible.is_empty() or npc_ids.is_empty():
		return false
	var npc_id := ""
	for offset in npc_ids.size():
		var candidate: String = npc_ids[(next_ticket - 1 + offset) % npc_ids.size()]
		var waiting := false
		for existing: String in customers:
			if state.cards[existing].metadata.get("npc_id") == candidate:
				waiting = true
		if not waiting:
			npc_id = candidate
			break
	if npc_id.is_empty():
		return false
	var order: Dictionary = possible[(next_ticket - 1) % possible.size()]
	var definition: Dictionary = state.content_card_definition(order.item_card_id)
	var card := state.create_queue_card(&"customer")
	if card.is_empty():
		return false
	state.cards[card].metadata = {"ticket": next_ticket, "remaining": float(catalog.patience_seconds),
		"total_wait": float(catalog.patience_seconds), "requested_kind": String(definition.kind),
		"chapter_order_id": order.id, "npc_id": npc_id}
	next_ticket += 1
	customers.append(card)
	arrivals_today += 1
	arrival_records.append({"ticket": int(state.cards[card].metadata.ticket), "day": current_day, "npc_id": npc_id,
		"order_id": String(order.id), "status": "waiting", "guest_instance_id": card})
	customer_arrived.emit(StringName(npc_id))
	return true


func preview_action(source_stack: String, target_card: String) -> StringName:
	if chapter == null or target_card not in customers:
		return super.preview_action(source_stack, target_card)
	if not state.stacks.has(source_stack) or not state.cards.has(target_card):
		return &"reject"
	var order := _order_for_customer(target_card)
	if order.is_empty():
		return &"reject"
	for id: String in state.stacks[source_stack].cards:
		if state.definition_id_for_card(id) != String(order.item_card_id):
			return &"reject"
	return &"sell"


func perform_drop(source_stack: String, target_card: String, return_position: Vector2) -> Dictionary:
	if chapter == null or target_card not in customers:
		return super.perform_drop(source_stack, target_card, return_position)
	var result := _new_result(preview_action(source_stack, target_card))
	if result.action != &"sell":
		return result
	var order := _order_for_customer(target_card)
	var price: int = order.coin_count
	if not _has_output_capacity(2, price):
		feedback.emit("SHOP_TABLE_FULL")
		return result
	var item: String = state.stacks[source_stack].cards.back()
	var npc_id: StringName = StringName(state.cards[target_card].metadata.npc_id)
	var ticket := int(state.cards[target_card].metadata.ticket)
	var transaction_id := "customer/%d" % ticket
	if state.transaction_receipts.has(transaction_id):
		return result
	state.remove_card(item)
	state.remove_card(target_card)
	customers.erase(target_card)
	result.consumed.append_array([item, target_card])
	if state.stacks.has(source_stack):
		state.move_stack(source_stack, return_position)
	_add_output(&"coin", price, return_position, result)
	var output_stack: String = result.created_stacks[0]
	var placement: Vector2 = state.stacks[output_stack].position
	var source_position := [placement.x, placement.y]
	for coin: String in result.created:
		state.cards[coin].metadata.production_transaction_id = transaction_id
		state.cards[coin].metadata.production_source_position = source_position.duplicate()
	state.transaction_receipts[transaction_id] = {"kind": SALE_RECEIPT_KIND, "version": 1,
		"status": "completed", "transaction_id": transaction_id, "ticket": ticket, "day": current_day,
		"order_id": String(order.id), "npc_id": String(npc_id), "item_definition_id": String(order.item_card_id),
		"input_instance_ids": [item, target_card], "output_instance_ids": result.created.duplicate(),
		"source_position": source_position}
	sales_count += 1
	_mark_arrival_status(ticket, "served")
	sale_records.append({"ticket": ticket, "order_id": String(order.id), "npc_id": String(npc_id),
		"item_instance_id": item, "guest_instance_id": target_card,
		"output_instance_ids": result.created.duplicate(), "day": current_day})
	result.ok = true
	_store_shop_state()
	feedback.emit("SHOP_SOLD")
	_notify_transaction(result, StringName(target_card))
	transaction_completed.emit(&"sell", npc_id)
	return result


func _order_for_customer(card: String) -> Dictionary:
	if not state.cards.has(card):
		return {}
	var id: String = state.cards[card].metadata.get("chapter_order_id", "")
	for order: Dictionary in catalog.get("orders", []):
		if order.id == id:
			return order
	return {}


func _mark_arrival_status(ticket: int, value: String) -> void:
	for index in arrival_records.size():
		if int(arrival_records[index].ticket) == ticket:
			arrival_records[index].status = value
			return


func _available_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if chapter == null:
		return result
	var facts := chapter.facts()
	for order: Dictionary in catalog.orders:
		var allowed := true
		for fact: String in order.requires_facts:
			if fact not in facts:
				allowed = false
		if allowed:
			result.append(order)
	return result


func _shop_card_id() -> String:
	if state == null:
		return ""
	for id: String in state.cards:
		if state.definition_id_for_card(id) == "card.shop" and state.cards[id].zone == &"board":
			return id
	return ""


func _restore_from_table() -> void:
	customers.clear()
	sale_records.clear()
	arrival_records.clear()
	var shop_id := _shop_card_id()
	if shop_id.is_empty():
		is_open = false
		return
	var metadata: Dictionary = state.cards[shop_id].metadata
	is_open = metadata.get("chapter_open") == true
	arrival_remaining = float(metadata.get("chapter_arrival_remaining", catalog.first_arrival_seconds))
	arrivals_today = int(metadata.get("chapter_arrivals_today", 0)) if int(metadata.get("chapter_arrivals_day", current_day)) == current_day else 0
	next_ticket = int(metadata.get("chapter_next_ticket", 1))
	sales_count = int(metadata.get("chapter_sales", 0))
	for record: Dictionary in metadata.get("chapter_sale_records", []):
		sale_records.append(record.duplicate(true))
	for record: Dictionary in metadata.get("chapter_arrival_records", []):
		arrival_records.append(record.duplicate(true))
	for id: String in state.cards:
		if state.cards[id].zone == &"queue" and state.definition_id_for_card(id) == "card.customer" and state.cards[id].metadata.has("chapter_order_id"):
			customers.append(id)
	customers.sort_custom(func(a: String, b: String) -> bool:
		return int(state.cards[a].metadata.ticket) < int(state.cards[b].metadata.ticket))
	_store_shop_state()


func _store_shop_state() -> void:
	var shop_id := _shop_card_id()
	if shop_id.is_empty():
		return
	var metadata: Dictionary = state.cards[shop_id].metadata
	metadata.chapter_open = is_open
	metadata.chapter_arrival_remaining = arrival_remaining
	metadata.chapter_arrivals_day = current_day
	metadata.chapter_arrivals_today = arrivals_today
	metadata.chapter_next_ticket = next_ticket
	metadata.chapter_sales = sales_count
	metadata.chapter_sale_records = sale_records.duplicate(true)
	metadata.chapter_arrival_records = arrival_records.duplicate(true)
