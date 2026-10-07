class_name ChapterSnapshot
extends RefCounted

const Package = preload("res://scripts/content/chapter_package.gd")
const Checkpoint = preload("res://scripts/content/module_checkpoint.gd")
const Runner = preload("res://scripts/content/module_recipe_runner.gd")
const Sigils = preload("res://scripts/content/module_sigil_bindings.gd")
const Effects = preload("res://scripts/content/module_event_effects.gd")
const Market = preload("res://scripts/content/module_market_exchange.gd")
const Scheduler = preload("res://scripts/content/module_scene_scheduler.gd")
const Operations = preload("res://scripts/content/chapter_operation_runner.gd")
const Services = preload("res://scripts/content/chapter_service_effects.gd")
const Relationships = preload("res://scripts/content/chapter_relationship_progress.gd")
const Customers = preload("res://scripts/content/chapter_customer_queue.gd")
const VERSION := 9
const LIMIT := 1000000000


# 棋盘只有顶层一份，联合检查点其余部分与导演状态共同引用它。
static func capture(state: TableState, day_data: Dictionary, camera_data: Dictionary, progress_data: Dictionary, opening_data: Dictionary, identity_data: Dictionary, checkpoint: Dictionary, director: Dictionary, manifest_path: String = Package.MANIFEST_PATH) -> Dictionary:
	if state == null or not checkpoint.get("table") is Dictionary or Runner.canonical_digest(checkpoint.table) != Runner.canonical_digest(state.snapshot()):
		return _failure("checkpoint_table_mismatch")
	var package_started := HitchProbe.stamp()
	var package := Package.read(manifest_path)
	HitchProbe.record("snapshot_package_read", package_started)
	if not package.ok:
		return package
	var payload := prepare_capture(checkpoint, day_data, camera_data, progress_data, opening_data, identity_data, director, package.package_fingerprint)
	var decode_started := HitchProbe.stamp()
	var validated := _decode_with_package(payload, package)
	HitchProbe.record("snapshot_capture_decode", decode_started)
	if not validated.ok:
		return validated
	# 好感仅为真实关系证据的显示缓存；写盘也不能保留调用者传入的旧值或伪造值。
	payload.progress = validated.progress.duplicate(true)
	return payload


static func prepare_capture(checkpoint: Dictionary, day_data: Dictionary, camera_data: Dictionary, progress_data: Dictionary, opening_data: Dictionary, identity_data: Dictionary, director: Dictionary, package_fingerprint: String) -> Dictionary:
	var metadata := checkpoint.duplicate(true)
	metadata.erase("table")
	return Runner.json_value({"state_version": VERSION, "session_mode": "chapter_01",
		"content_generation": ContentCatalog.content_generation(),
		"table": checkpoint.table, "module_checkpoint": metadata,
		"package_fingerprint": package_fingerprint, "director": director,
		"day": day_data, "camera": camera_data, "progress": progress_data,
		"opening": opening_data, "identity": identity_data}) as Dictionary


static func validate_prepared_capture(payload: Dictionary) -> Dictionary:
	if not _generation_matches(payload):
		return _failure("content_generation_mismatch", "SAVE_UNSUPPORTED_VERSION")
	var package := Package.read()
	if not package.ok:
		return package
	var validated := _decode_with_package(payload, package)
	if not validated.ok:
		return validated
	var safe_payload := payload.duplicate(true)
	safe_payload.progress = validated.progress.duplicate(true)
	return {"ok": true, "payload": safe_payload}


static func decode(payload: Variant, manifest_path: String = Package.MANIFEST_PATH) -> Dictionary:
	if not _generation_matches(payload):
		return _failure("content_generation_mismatch", "SAVE_UNSUPPORTED_VERSION")
	var package_started := HitchProbe.stamp()
	var package := Package.read(manifest_path)
	HitchProbe.record("snapshot_package_read", package_started)
	if not package.ok:
		return package
	return _decode_with_package(payload, package)


static func _decode_with_package(payload: Variant, package: Dictionary) -> Dictionary:
	if not _generation_matches(payload):
		return _failure("content_generation_mismatch", "SAVE_UNSUPPORTED_VERSION")
	# onboarding 为可选的新手目标字段，其余字段仍按原清单严格校验。
	var core_fields: Variant = payload
	if payload is Dictionary and payload.has("onboarding"):
		core_fields = payload.duplicate()
		core_fields.erase("onboarding")
	if not _fields(core_fields, ["state_version", "session_mode", "content_generation", "table", "module_checkpoint", "package_fingerprint", "director", "day", "camera", "progress", "opening", "identity"]):
		return _failure("invalid_chapter_payload_fields")
	if not _integer(payload.state_version, VERSION, VERSION) or payload.session_mode != "chapter_01":
		return _failure("unsupported_chapter_version", "SAVE_UNSUPPORTED_VERSION")
	if not payload.package_fingerprint is String or payload.package_fingerprint != package.package_fingerprint:
		return _failure("package_fingerprint_mismatch", "SAVE_UNSUPPORTED_VERSION")
	if not payload.module_checkpoint is Dictionary or payload.module_checkpoint.has("table") or not payload.table is Dictionary:
		return _failure("duplicate_or_invalid_chapter_table")
	var joint: Dictionary = payload.module_checkpoint.duplicate(true)
	joint["table"] = payload.table.duplicate(true)
	var bundle: Dictionary = package.bundle
	var world := Checkpoint.decode(joint, bundle.stories, bundle.content.recipes, bundle.exclusive_fact_groups,
		package.action_bindings, package.market_catalog, package.catalog_context, package.event_definitions, package.operations, package.service_catalog, package.customer_catalog)
	if not world.ok:
		return _context_failure(str(world.error))
	var table: TableState = world.table
	var heroes := 0
	for id: String in table.cards:
		if table.definition_id_for_card(id) == "card.hero":
			heroes += 1
			if table.cards[id].zone != &"board":
				return _failure("hero_outside_board")
	if heroes != 1:
		return _failure("chapter_requires_one_hero")
	var day: Variant = payload.day
	if not _fields(day, ["day", "elapsed", "seconds_per_day"]) or not _integer(day.day, 1, LIMIT) or not _number(day.seconds_per_day, 1, 3600) or not _number(day.elapsed, 0, float(day.seconds_per_day)) or float(day.elapsed) >= float(day.seconds_per_day):
		return _failure("invalid_chapter_day")
	var shop_error := _shop_state_error(table, int(day.day), package.customer_catalog, world.story)
	if not shop_error.is_empty():
		return _failure(shop_error)
	var contact_error := _contact_interest_error(table, world.story)
	if not contact_error.is_empty():
		return _failure(contact_error)
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("kind") == "chapter_appointment" and int(receipt.get("day", 0)) > int(day.day):
			return _failure("appointment_receipt_from_future_day")
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("kind") in [Services.KIND, Market.RECEIPT_KIND] and int(receipt.get("day", 0)) > int(day.day):
			return _failure("service_or_market_receipt_from_future_day")
	var camera: Variant = payload.camera
	if not _fields(camera, ["zoom", "center"]) or not _number(camera.zoom, TableCamera.MIN_ZOOM, TableCamera.MAX_ZOOM) or not _position(camera.center):
		return _failure("invalid_chapter_camera")
	var identity_error := PlayerIdentity.validate_data(payload.identity)
	if not identity_error.is_empty():
		return _failure("invalid_chapter_identity: " + identity_error)
	var opening_error := _opening_error(payload.opening, table, world.story)
	if not opening_error.is_empty():
		return _failure(opening_error)
	var progress_error := _progress_error(payload.progress, int(day.day), table, package.catalog_context.catalog)
	if not progress_error.is_empty():
		return _context_failure(progress_error)
	var relationships := Relationships.evaluate(table, world.story, package.relationship_catalog, package.operations, package.event_definitions, Services.workbench_policy(package.service_catalog))
	if not relationships.ok:
		return _context_failure(str(relationships.error))
	var progress: Dictionary = payload.progress.duplicate(true)
	# 这里只更新原有见面记录，不依据投影凭空登记人物；信号仍由独立投影读取。
	for npc_id: String in progress.npcs:
		progress.npcs[npc_id].affection = int(relationships.npcs.get(npc_id, {}).get("affection", 0))
	var director_error := _director_error(payload.director, table, world.story, package)
	if not director_error.is_empty():
		return _context_failure(director_error)
	var operation_runner := Operations.new()
	var result := operation_runner.configure(table, world.story, package.operations, Services.workbench_policy(package.service_catalog))
	if not result.ok:
		return _context_failure(str(result.error))
	result = operation_runner.restore(payload.director.operation_jobs)
	if not result.ok:
		return _context_failure(str(result.error))
	world["operation_runner"] = operation_runner
	var sigils := Sigils.new()
	result = sigils.configure(table)
	if not result.ok:
		return _failure("invalid_chapter_sigils: " + str(result.error))
	world["sigils"] = sigils
	var effects := Effects.new()
	result = effects.configure(table, world.story, package.event_definitions)
	if not result.ok:
		return _context_failure(str(result.error))
	world["effects"] = effects
	var services := Services.new()
	result = services.configure(table, world.story, package.service_catalog, package.operations, package.market_catalog)
	if not result.ok:
		return _context_failure(str(result.error))
	world["services"] = services
	var market := Market.new()
	result = market.configure(table, package.market_catalog.offers, package.market_catalog.sources, Services.market_policy(package.service_catalog), package.operations)
	if not result.ok:
		return _context_failure(str(result.error))
	world["market"] = market
	var scheduler := Scheduler.new()
	result = scheduler.configure(table, world.story, package.scene_rules, bundle.content.recipes, package.event_definitions, package.operations, package.service_catalog, package.market_catalog)
	if not result.ok:
		return _context_failure(str(result.error))
	world["scheduler"] = scheduler
	var checkpoint_template: Dictionary = payload.module_checkpoint.duplicate(true)
	for field: String in ["story", "runner", "bridge"]:
		checkpoint_template.erase(field)
	return {"ok": true, "error": "", "error_key": "", "session_mode": "chapter_01", "state": table,
		"day": day.duplicate(true), "camera": camera.duplicate(true), "progress": progress,
		"opening": payload.opening.duplicate(true), "identity": payload.identity.duplicate(true),
		"director": payload.director.duplicate(true), "package": package, "chapter_world": world,
		"checkpoint_template": checkpoint_template, "onboarding": OnboardingGoals.sanitize(payload.get("onboarding"))}


static func _opening_error(data: Variant, table: TableState, story: RefCounted) -> String:
	if not _fields(data, ["stage", "intro_index", "elapsed"]):
		return "invalid_chapter_opening_fields"
	if data.stage in ["intro", "explore"]:
		var error := OpeningFlow.validate_data(data, table)
		if not error.is_empty():
			return "invalid_chapter_opening: " + error
		var story_state: Dictionary = story.to_data().state
		if not table.transaction_receipts.is_empty() or not story_state.completed.is_empty() or not story_state.story_id.is_empty():
			return "opening_precedes_chapter_progress"
		return ""
	if data.stage == "complete" and _integer(data.intro_index, OpeningFlow.intro_page_count() - 1, OpeningFlow.intro_page_count() - 1) and _number(data.elapsed, OpeningFlow.explore_seconds(), OpeningFlow.explore_seconds()):
		return ""
	if data.stage == "inactive" and _integer(data.intro_index, 0, 0) and _number(data.elapsed, 0, 0):
		return ""
	return "invalid_chapter_opening_state"


static func _progress_error(data: Variant, day: int, table: TableState, catalog: Dictionary) -> String:
	if not _fields(data, ["recipes", "npcs"]) or not data.recipes is Array or not data.npcs is Dictionary:
		return "invalid_chapter_progress_fields"
	var known := {}
	for id: Variant in data.recipes:
		if not id is String or known.has(id):
			return "invalid_or_repeated_journal_recipe"
		if not catalog.recipes.has(id):
			return "unknown_journal_recipe"
		known[id] = true
	for id: Variant in data.npcs:
		if not id is String or table.content_npc_definition(id).is_empty():
			return "unknown_journal_npc"
		var npc: Variant = data.npcs[id]
		if not _fields(npc, PlayerProgress.NPC_FIELDS):
			return "invalid_journal_npc_fields"
		if not _integer(npc.affection, 0, 100) or not _integer(npc.visits, 1, PlayerProgress.COUNTER_MAX) or not _integer(npc.orders_served, 0, int(npc.visits)) or not _integer(npc.first_seen_day, 1, day) or not _integer(npc.last_seen_day, int(npc.first_seen_day), day):
			return "invalid_journal_npc_counters"
	return ""


static func _shop_state_error(table: TableState, day: int, customer_catalog: Dictionary, story: RefCounted) -> String:
	var shops := 0
	var entered_town := false
	var unlock_fact: Variant = ContentCatalog.runtime_rules().get("shop_unlock_fact", "")
	if not unlock_fact is String:
		return "invalid_shop_unlock_fact"
	var earned_facts: Dictionary = {}
	for fact: String in story.to_data().state.facts:
		earned_facts[fact] = true
	var shop_metadata: Dictionary = {}
	var queued: Array[Dictionary] = []
	var known_orders: Dictionary = {}
	for order: Dictionary in customer_catalog.orders:
		known_orders[String(order.id)] = order
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("status") == "completed":
			for fact: String in receipt.get("grants_facts", []):
				earned_facts[fact] = true
		if not unlock_fact.is_empty() and receipt.get("kind") == Operations.RECEIPT_KIND and receipt.get("status") == "completed" and unlock_fact in receipt.get("grants_facts", []):
			entered_town = true
	for id: String in table.cards:
		var metadata: Dictionary = table.cards[id].metadata
		var is_shop := table.definition_id_for_card(id) == "card.shop"
		if is_shop:
			shops += 1
			shop_metadata = metadata
			if table.cards[id].zone != &"board":
				return "chapter_shop_outside_board"
		if table.cards[id].zone == &"queue":
			if table.definition_id_for_card(id) != "card.customer":
				return "invalid_chapter_queue_card"
			queued.append({"id": id, "metadata": metadata})
		for key: String in ["chapter_arrival_remaining", "chapter_arrivals_day", "chapter_arrivals_today", "chapter_next_ticket", "chapter_sales", "chapter_sale_records", "chapter_arrival_records"]:
			if metadata.has(key) and not is_shop:
				return "chapter_shop_metadata_on_other_card"
		if not metadata.has("chapter_open"):
			continue
		if not is_shop or not metadata.chapter_open is bool:
			return "invalid_chapter_shop_open_metadata"
		if metadata.chapter_open and not entered_town:
			return "chapter_shop_open_before_town"
	if shops > 1:
		return "duplicate_chapter_shop"
	if shops == 0 and not queued.is_empty():
		return "chapter_customers_without_shop"
	if shops == 0:
		return ""
	var fields := ["chapter_arrival_remaining", "chapter_arrivals_day", "chapter_arrivals_today", "chapter_next_ticket", "chapter_sales", "chapter_sale_records", "chapter_arrival_records"]
	var has_timing := false
	for key: String in fields:
		has_timing = has_timing or shop_metadata.has(key)
	if not has_timing:
		return "chapter_customers_without_shop_timing" if not queued.is_empty() else ""
	for key: String in fields:
		if not shop_metadata.has(key):
			return "incomplete_chapter_shop_timing"
	if not shop_metadata.has("chapter_open") or not shop_metadata.chapter_open is bool:
		return "chapter_shop_timing_without_open_state"
	if not _number(shop_metadata.chapter_arrival_remaining, 0.0, float(customer_catalog.arrival_interval_seconds)):
		return "invalid_chapter_arrival_timer"
	if not _integer(shop_metadata.chapter_arrivals_day, day, day) or not _integer(shop_metadata.chapter_arrivals_today, 0, int(customer_catalog.max_arrivals_per_day)):
		return "invalid_chapter_arrival_day"
	if not _integer(shop_metadata.chapter_next_ticket, 1, LIMIT) or not _integer(shop_metadata.chapter_sales, 0, LIMIT):
		return "invalid_chapter_ticket_counters"
	var next_ticket: int = int(shop_metadata.chapter_next_ticket)
	if int(shop_metadata.chapter_sales) > next_ticket - 1 or queued.size() > int(customer_catalog.max_waiting):
		return "inconsistent_chapter_customer_counters"
	if not shop_metadata.chapter_sale_records is Array or shop_metadata.chapter_sale_records.size() > Customers.MAX_SALE_RECORDS or int(shop_metadata.chapter_sales) != shop_metadata.chapter_sale_records.size():
		return "invalid_chapter_sale_ledger_size"
	if not shop_metadata.chapter_arrival_records is Array or shop_metadata.chapter_arrival_records.size() != next_ticket - 1 or shop_metadata.chapter_arrival_records.size() > Customers.MAX_SALE_RECORDS:
		return "invalid_chapter_arrival_ledger_size"
	var arrivals: Dictionary = {}
	var day_counts: Dictionary = {}
	for record: Variant in shop_metadata.chapter_arrival_records:
		if not _fields(record, ["ticket", "day", "npc_id", "order_id", "status", "guest_instance_id"]):
			return "invalid_chapter_arrival_record"
		if not _integer(record.ticket, 1, next_ticket - 1) or arrivals.has(int(record.ticket)) or not _integer(record.day, 1, day):
			return "invalid_chapter_arrival_ticket"
		if not record.npc_id is String or String(record.npc_id) not in ContentCatalog.shop_npc_ids() or not record.order_id is String or not known_orders.has(String(record.order_id)):
			return "invalid_chapter_arrival_identity"
		if record.status not in ["waiting", "served", "left"] or not _instance_id(record.guest_instance_id, table.next_card_id):
			return "invalid_chapter_arrival_status"
		arrivals[int(record.ticket)] = record
		var arrival_day := int(record.day)
		day_counts[arrival_day] = int(day_counts.get(arrival_day, 0)) + 1
		if day_counts[arrival_day] > int(customer_catalog.max_arrivals_per_day):
			return "chapter_arrival_daily_quota_exceeded"
	for ticket in range(1, next_ticket):
		if not arrivals.has(ticket):
			return "chapter_arrival_ticket_gap"
	if int(shop_metadata.chapter_arrivals_today) != int(day_counts.get(day, 0)):
		return "chapter_arrival_daily_count_mismatch"
	var tickets: Dictionary = {}
	var npcs: Dictionary = {}
	var output_ids: Dictionary = {}
	for sale: Variant in shop_metadata.chapter_sale_records:
		if not _fields(sale, ["ticket", "order_id", "npc_id", "item_instance_id", "guest_instance_id", "output_instance_ids", "day"]):
			return "invalid_chapter_sale_record"
		if not _integer(sale.ticket, 1, next_ticket - 1) or tickets.has(int(sale.ticket)) or not _integer(sale.day, 1, day):
			return "invalid_chapter_sale_ticket"
		tickets[int(sale.ticket)] = true
		var arrival: Dictionary = arrivals.get(int(sale.ticket), {})
		if arrival.is_empty() or arrival.status != "served" or arrival.npc_id != sale.npc_id or arrival.order_id != sale.order_id or arrival.guest_instance_id != sale.guest_instance_id or int(arrival.day) > int(sale.day):
			return "chapter_sale_arrival_mismatch"
		var receipt_id := "customer/%d" % int(sale.ticket)
		var receipt: Dictionary = table.transaction_receipts.get(receipt_id, {})
		if receipt.is_empty() or receipt.get("kind") != Customers.SALE_RECEIPT_KIND or receipt.get("day") != sale.day or receipt.get("order_id") != sale.order_id or receipt.get("npc_id") != sale.npc_id or receipt.get("input_instance_ids") != [sale.item_instance_id, sale.guest_instance_id] or receipt.get("output_instance_ids") != sale.output_instance_ids:
			return "chapter_sale_receipt_mismatch"
		var sale_order_id := String(sale.order_id)
		if not sale.order_id is String or not known_orders.has(sale_order_id):
			return "invalid_chapter_sale_order"
		for fact: String in known_orders[sale_order_id].requires_facts:
			if not earned_facts.has(fact):
				return "chapter_sale_before_order_unlock"
		if not sale.npc_id is String or String(sale.npc_id) not in ContentCatalog.shop_npc_ids():
			return "invalid_chapter_sale_npc"
		if not _instance_id(sale.item_instance_id, table.next_card_id) or table.cards.has(sale.item_instance_id) or not _instance_id(sale.guest_instance_id, table.next_card_id) or table.cards.has(sale.guest_instance_id):
			return "invalid_chapter_sale_inputs"
		if not sale.output_instance_ids is Array or sale.output_instance_ids.size() != int(known_orders[sale_order_id].coin_count):
			return "invalid_chapter_sale_payment"
		for coin: Variant in sale.output_instance_ids:
			if not _instance_id(coin, table.next_card_id) or output_ids.has(coin):
				return "invalid_chapter_sale_output_ids"
			if table.cards.has(coin) and table.definition_id_for_card(coin) != "card.coin":
				return "invalid_chapter_sale_output_card"
			output_ids[coin] = true
	for entry: Dictionary in queued:
		var metadata: Dictionary = entry.metadata
		if not _fields(metadata, ["ticket", "remaining", "total_wait", "requested_kind", "chapter_order_id", "npc_id"]):
			return "invalid_chapter_customer_metadata"
		var order_id := String(metadata.chapter_order_id)
		if not known_orders.has(order_id):
			return "unknown_chapter_customer_order"
		var order: Dictionary = known_orders[order_id]
		for fact: String in order.requires_facts:
			if not earned_facts.has(fact):
				return "chapter_customer_order_before_unlock"
		var expected_kind := String(table.content_card_definition(String(order.item_card_id)).kind)
		if String(metadata.requested_kind) != expected_kind:
			return "chapter_customer_order_kind_mismatch"
		if not _number(metadata.total_wait, float(customer_catalog.patience_seconds), float(customer_catalog.patience_seconds)) or not _number(metadata.remaining, 0.0, float(metadata.total_wait)):
			return "invalid_chapter_customer_patience"
		if not _integer(metadata.ticket, 1, next_ticket - 1) or tickets.has(int(metadata.ticket)):
			return "invalid_chapter_customer_ticket"
		if not metadata.npc_id is String or String(metadata.npc_id) not in ContentCatalog.shop_npc_ids() or npcs.has(String(metadata.npc_id)):
			return "invalid_chapter_customer_npc"
		tickets[int(metadata.ticket)] = true
		var arrival: Dictionary = arrivals.get(int(metadata.ticket), {})
		if arrival.is_empty() or arrival.status != "waiting" or arrival.guest_instance_id != entry.id or arrival.order_id != order_id or arrival.npc_id != metadata.npc_id:
			return "chapter_queue_arrival_mismatch"
		npcs[String(metadata.npc_id)] = true
	for ticket: int in arrivals:
		var record: Dictionary = arrivals[ticket]
		if record.status == "waiting" and not tickets.has(ticket):
			return "chapter_orphan_waiting_arrival"
		if record.status == "served" and not table.transaction_receipts.has("customer/%d" % ticket):
			return "chapter_orphan_served_arrival"
		if record.status == "left" and table.cards.has(record.guest_instance_id):
			return "chapter_left_guest_reappeared"
	var customer_receipt_count := 0
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("kind") == Customers.SALE_RECEIPT_KIND:
			customer_receipt_count += 1
	if customer_receipt_count != int(shop_metadata.chapter_sales):
		return "chapter_customer_receipt_count_mismatch"
	return ""


static func _contact_interest_error(table: TableState, story: RefCounted) -> String:
	var state: Dictionary = story.to_data().state
	var facts: Array = state.facts
	var earned: Dictionary = {}
	for fact: String in facts:
		earned[fact] = true
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("status") == "completed":
			for fact: String in receipt.get("grants_facts", []):
				earned[fact] = true
	var visits: Variant = ContentCatalog.runtime_rules().get("contact_visits", {})
	if not visits is Dictionary:
		return "invalid_contact_visit_rules"
	for slug: Variant in visits:
		if not slug is String or slug.is_empty():
			return "invalid_contact_visit_rule_id"
		var rule: Variant = visits[slug]
		if not _fields(rule, ["permission_fact", "interest_facts", "visit_story", "first_receipt", "arrival_fact", "visit_operation", "return_story", "revisit_receipt_prefix"]):
			return "invalid_contact_visit_rule_fields"
		for field: String in ["permission_fact", "visit_story", "first_receipt", "arrival_fact", "visit_operation", "return_story", "revisit_receipt_prefix"]:
			if not rule[field] is String or rule[field].is_empty():
				return "invalid_contact_visit_rule_reference"
		if not rule.interest_facts is Array or rule.interest_facts.size() != 2:
			return "invalid_contact_visit_interests"
		for fact: Variant in rule.interest_facts:
			if not fact is String or fact.is_empty():
				return "invalid_contact_visit_interests"
		if rule.interest_facts[0] == rule.interest_facts[1]:
			return "invalid_contact_visit_interests"
		var permission: String = rule.permission_fact
		if permission in facts:
			var first: bool = rule.interest_facts[0] in facts
			var second: bool = rule.interest_facts[1] in facts
			if first == second:
				return "chapter_contact_interest_missing_or_ambiguous"
		var visit_story: String = rule.visit_story
		if visit_story not in state.completed:
			continue
		if not table.transaction_receipts.has(rule.first_receipt):
			return "chapter_contact_visit_without_day_record"
		if not earned.has(rule.arrival_fact):
			return "chapter_contact_visit_without_arrival"
		var proved := false
		for receipt: Dictionary in table.transaction_receipts.values():
			if receipt.get("kind") == Operations.RECEIPT_KIND and receipt.get("status") == "completed" and receipt.get("operation_id") == rule.visit_operation:
				proved = true
				break
		if not proved:
			return "chapter_contact_visit_without_operation"
		var return_story: String = rule.return_story
		if return_story in state.completed or state.story_id == return_story:
			var revisits := 0
			for tx: String in table.transaction_receipts:
				if tx.begins_with(rule.revisit_receipt_prefix):
					revisits += 1
			if revisits == 0:
				return "chapter_return_visit_without_day_record"
	return ""


static func _director_error(data: Variant, table: TableState, story: RefCounted, package: Dictionary) -> String:
	if not _fields(data, ["schema_version", "scene_npc_id", "story_sources", "completed_operations", "operation_jobs", "pending_outputs"]) or not _integer(data.schema_version, 1, 1):
		return "invalid_chapter_director_fields"
	if not data.scene_npc_id is String or (not data.scene_npc_id.is_empty() and table.content_npc_definition(data.scene_npc_id).is_empty()):
		return "unknown_director_npc"
	if not data.story_sources is Dictionary or not data.completed_operations is Array or not data.operation_jobs is Dictionary or not data.pending_outputs is Array or not data.pending_outputs.is_empty():
		return "invalid_chapter_director_collections"
	var state: Dictionary = story.to_data().state
	for id: Variant in data.story_sources:
		if not id is String or not story.story_exists(id):
			return "unknown_director_story"
		var source: Variant = data.story_sources[id]
		if not _instance_id(source, table.next_card_id):
			return "invalid_director_source_id"
		if not state.choices.has(id):
			return "director_source_without_started_story"
		if table.cards.has(source):
			var rule: Dictionary = package.scene_rules.get(id, {})
			if not rule.is_empty() and table.cards[source].metadata.get("npc_id") != rule.npc_id:
				return "director_source_npc_mismatch"
		else:
			var proved := false
			for receipt: Dictionary in table.transaction_receipts.values():
				if receipt.get("kind") != Effects.RECEIPT_KIND or receipt.get("source_instance_id") != source or source not in receipt.get("removed_ids", []):
					continue
				if package.event_definitions[receipt.event_id].trigger_story_id == id:
					proved = true
			if not proved:
				return "director_source_has_no_departure_proof"
	var expected := {}
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("kind") == Operations.RECEIPT_KIND and receipt.get("status") == "completed":
			expected[receipt.operation_id] = true
	var supplied := {}
	for id: Variant in data.completed_operations:
		if not id is String or supplied.has(id) or not package.operations.has(id) or not expected.has(id):
			return "director_completed_operations_mismatch"
		supplied[id] = true
	if supplied.size() != expected.size():
		return "director_completed_operations_mismatch"
	if state.story_id.is_empty() and not data.scene_npc_id.is_empty():
		return "director_npc_without_active_story"
	if not state.story_id.is_empty():
		if not data.story_sources.has(state.story_id):
			return "director_active_story_source_missing"
		var source: String = data.story_sources[state.story_id]
		if table.cards.has(source) and table.cards[source].metadata.get("npc_id", "") != data.scene_npc_id:
			return "director_active_npc_mismatch"
	return ""


static func _generation_matches(payload: Variant) -> bool:
	var generation := ContentCatalog.content_generation()
	return not generation.is_empty() and payload is Dictionary and payload.get("content_generation") is String and payload.content_generation == generation


static func _fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))


static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0], -1000000, 1000000) and _number(value[1], -1000000, 1000000)


static func _instance_id(value: Variant, next: int) -> bool:
	if not value is String or not value.begins_with("card_"):
		return false
	var suffix: String = value.trim_prefix("card_")
	return suffix.is_valid_int() and suffix.to_int() > 0 and suffix.to_int() < next and value == "card_%04d" % suffix.to_int()


static func _context_failure(error: String) -> Dictionary:
	for marker: String in ["unknown", "unregistered", "catalog", "fingerprint", "configuration", "unavailable", "context_mismatch", "checkpoint_context_required"]:
		if error.contains(marker):
			return _failure(error, "SAVE_UNSUPPORTED_VERSION")
	return _failure(error)


static func _failure(error: String, key: String = "SAVE_CORRUPT") -> Dictionary:
	return {"ok": false, "error": error, "reason": error, "error_key": key}
