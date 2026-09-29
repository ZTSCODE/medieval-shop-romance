class_name ModuleCheckpoint
extends RefCounted

const Runner = preload("res://scripts/content/module_recipe_runner.gd")
const Story = preload("res://scripts/content/module_story_session.gd")
const Sigils = preload("res://scripts/content/module_sigil_bindings.gd")
const Market = preload("res://scripts/content/module_market_exchange.gd")
const Events = preload("res://scripts/content/module_event_effects.gd")
const Operations = preload("res://scripts/content/chapter_operation_runner.gd")
const Services = preload("res://scripts/content/chapter_service_effects.gd")
const Customers = preload("res://scripts/content/chapter_customer_queue.gd")
const Appointments = preload("res://scripts/content/chapter_appointment_service.gd")
const SCHEMA_VERSION := 1
const MAX_COUNTER := 2147483647
const MAX_RECEIPTS := 50000


# 这是独立模块检查点；不负责正式 GameSnapshot、磁盘替换或缺失模块迁移。
# 成功返回可直接 JSON.stringify 的载荷，失败返回 ok=false/error。
static func capture(table: TableState, story_session: Story, recipe_runner: Runner, action_bridge: RefCounted = null, market_catalog: Variant = null, event_definitions: Variant = null, operations: Variant = null, service_catalog: Variant = null, customer_catalog: Variant = null) -> Dictionary:
	if table == null or story_session == null or recipe_runner == null:
		return _failure("missing_checkpoint_participant")
	var snapshot := table.snapshot()
	var story_data := story_session.to_data()
	if not _safe({"table": snapshot, "story": story_data}, true, 0, {"visited": 0}):
		return _failure("checkpoint_contains_unsupported_data")
	var runner_data := recipe_runner.to_data()
	var raw := {"schema_version": SCHEMA_VERSION, "module_ids": _modules(table),
		"card_catalog_fingerprint": _catalog_fingerprint(table), "table": snapshot,
		"story": story_data, "runner": runner_data}
	var service_error := validate_service_context(table, story_session, service_catalog, operations, market_catalog)
	if not service_error.is_empty():
		return _failure(service_error)
	if service_catalog != null:
		raw["service_context"] = Services.context_for(service_catalog, operations, market_catalog)
	var market_error := _market_context_error(table, market_catalog, service_catalog, operations)
	if not market_error.is_empty():
		return _failure(market_error)
	if market_catalog != null:
		raw["market_catalog_fingerprint"] = Market.catalog_fingerprint(market_catalog.offers, market_catalog.sources)
	if customer_catalog != null:
		if not customer_catalog is Dictionary or not Customers.validate_catalog(customer_catalog, table).is_empty():
			return _failure("invalid_customer_checkpoint_context")
		raw["customer_catalog_fingerprint"] = Runner.canonical_digest(customer_catalog)
	var event_error := validate_event_context(table, story_session, event_definitions)
	if not event_error.is_empty():
		return _failure(event_error)
	if event_definitions != null:
		raw["event_catalog_fingerprint"] = Runner.canonical_digest(event_definitions)
	var operation_error := validate_operation_context(table, story_session, operations, Services.workbench_policy(service_catalog))
	if not operation_error.is_empty():
		return _failure(operation_error)
	if operations != null:
		raw["operation_catalog_fingerprint"] = Runner.canonical_digest(operations)
	if action_bridge != null:
		if not action_bridge.has_method("is_bound_to") or not action_bridge.is_bound_to(table, story_session):
			return _failure("bridge_belongs_to_another_checkpoint")
		var bridge_data: Dictionary = action_bridge.to_data()
		if bridge_data.get("ok") == false:
			return _failure("invalid_bridge_checkpoint: " + str(bridge_data.get("error", "")))
		if bridge_data.get("event_catalog_fingerprint", "") != raw.get("event_catalog_fingerprint", ""):
			return _failure("bridge_event_context_mismatch")
		raw["bridge"] = bridge_data
	if not _safe(raw, true, 0, {"visited": 0}):
		return _failure("checkpoint_contains_unsupported_data")
	var fingerprint_source := snapshot.duplicate(true)
	for field: String in ["next_card_id", "next_stack_id", "next_z"]:
		fingerprint_source.erase(field)
	if runner_data.get("table_digest") != Runner.canonical_digest(fingerprint_source):
		return _failure("runner_belongs_to_another_table")
	var link_error := _story_receipt_error(story_data, table.transaction_receipts)
	if not link_error.is_empty():
		return _failure(link_error)
	return Runner.json_value(raw)


# 调用方只在 ok 后整体替换三个引用。失败候选不会接触既有对象或全局目录。
static func decode(payload: Variant, stories: Dictionary, recipes: Dictionary, groups: Array = [], action_bindings: Variant = null, market_catalog: Variant = null, catalog_context: Dictionary = {}, event_definitions: Variant = null, operations: Variant = null, service_catalog: Variant = null, customer_catalog: Variant = null) -> Dictionary:
	if not _safe(payload, false, 0, {"visited": 0}):
		return _failure("checkpoint_contains_unsupported_data")
	var fields := ["schema_version", "module_ids", "card_catalog_fingerprint", "table", "story", "runner"]
	if payload is Dictionary and payload.has("customer_catalog_fingerprint"):
		fields.append("customer_catalog_fingerprint")
		if not customer_catalog is Dictionary or payload.customer_catalog_fingerprint != Runner.canonical_digest(customer_catalog):
			return _failure("customer_catalog_context_mismatch")
	elif customer_catalog != null:
		return _failure("customer_checkpoint_context_required")
	if payload is Dictionary and payload.has("service_context"):
		fields.append("service_context")
		if not service_catalog is Dictionary or not operations is Dictionary or not market_catalog is Dictionary:
			return _failure("service_catalog_context_required")
		if Runner.canonical_digest(payload.service_context) != Runner.canonical_digest(Services.context_for(service_catalog, operations, market_catalog)):
			return _failure("service_catalog_context_mismatch")
	elif service_catalog != null:
		return _failure("service_checkpoint_context_required")
	if payload is Dictionary and payload.has("operation_catalog_fingerprint"):
		fields.append("operation_catalog_fingerprint")
		if not operations is Dictionary or payload.operation_catalog_fingerprint != Runner.canonical_digest(operations):
			return _failure("operation_catalog_context_mismatch")
	elif operations != null:
		return _failure("operation_checkpoint_context_required")
	if payload is Dictionary and payload.has("event_catalog_fingerprint"):
		fields.append("event_catalog_fingerprint")
		if not event_definitions is Dictionary:
			return _failure("event_catalog_context_required")
		if not _text(payload.event_catalog_fingerprint) or payload.event_catalog_fingerprint != Runner.canonical_digest(event_definitions):
			return _failure("event_catalog_fingerprint_mismatch")
	elif event_definitions != null:
		return _failure("event_checkpoint_context_required")
	if payload is Dictionary and payload.has("market_catalog_fingerprint"):
		fields.append("market_catalog_fingerprint")
		if not _fields(market_catalog, ["offers", "sources"]) or not market_catalog.offers is Dictionary or not market_catalog.sources is Dictionary:
			return _failure("market_catalog_context_required")
		if payload.market_catalog_fingerprint != Market.catalog_fingerprint(market_catalog.offers, market_catalog.sources):
			return _failure("market_catalog_fingerprint_mismatch")
	elif market_catalog != null:
		return _failure("market_checkpoint_context_required")
	if payload is Dictionary and payload.has("bridge"):
		fields.append("bridge")
		if not action_bindings is Dictionary:
			return _failure("bridge_binding_context_required")
	elif action_bindings != null:
		return _failure("bridge_checkpoint_required")
	if not _fields(payload, fields):
		return _failure("invalid_checkpoint_fields")
	if not _integer(payload.schema_version, SCHEMA_VERSION, SCHEMA_VERSION):
		return _failure("unsupported_checkpoint_version")
	var candidate_table := TableState.new()
	if not catalog_context.is_empty():
		if not _fields(catalog_context, ["catalog", "module_ids"]) or not catalog_context.catalog is Dictionary or not _strings(catalog_context.module_ids):
			return _failure("invalid_local_catalog_context")
		var module_ids: Array[String] = []
		module_ids.assign(catalog_context.module_ids)
		var context_result := candidate_table.configure_catalog(catalog_context.catalog, module_ids)
		if not context_result.ok:
			return _failure("invalid_local_catalog_context: " + str(context_result.error))
	if not _strings(payload.module_ids) or payload.module_ids != _modules(candidate_table) or payload.card_catalog_fingerprint != _catalog_fingerprint(candidate_table):
		return _failure("checkpoint_catalog_context_mismatch")
	var structure_error := _table_structure_error(payload.table, candidate_table)
	if not structure_error.is_empty():
		return _failure(structure_error)
	var native_table: Dictionary = payload.table.duplicate(true)
	for stack: Dictionary in native_table.stacks.values():
		stack.position = Vector2(float(stack.position[0]), float(stack.position[1]))
		stack.z = int(stack.z)
	for field: String in ["next_card_id", "next_stack_id", "next_z"]:
		native_table[field] = int(native_table[field])
	for card: Dictionary in native_table.cards.values():
		for field: String in ["kind", "category", "zone"]:
			card[field] = StringName(card[field])
		if card.metadata.has("membership_revision"):
			card.metadata.membership_revision = int(card.metadata.membership_revision)
	candidate_table.restore(native_table)
	var table_error := candidate_table.validate()
	if not table_error.is_empty():
		return _failure("invalid_table: " + table_error)
	var candidate_runner := Runner.new()
	var configured := candidate_runner.configure(candidate_table, recipes)
	if not configured.ok:
		return _failure("invalid_recipe_context: " + str(configured.error))
	var candidate_story := Story.new()
	configured = candidate_story.configure(stories, groups)
	if not configured.ok:
		return _failure("invalid_story_context: " + str(configured.error))
	var restored := candidate_story.restore(payload.story)
	if not restored.ok:
		return _failure("invalid_story_checkpoint: " + str(restored.error))
	var service_error := validate_service_context(candidate_table, candidate_story, service_catalog, operations, market_catalog)
	if not service_error.is_empty():
		return _failure(service_error)
	var market_error := _market_context_error(candidate_table, market_catalog, service_catalog, operations)
	if not market_error.is_empty():
		return _failure(market_error)
	var operation_error := validate_operation_context(candidate_table, candidate_story, operations, Services.workbench_policy(service_catalog))
	if not operation_error.is_empty():
		return _failure(operation_error)
	var receipt_error := _receipts_error(candidate_table, recipes, market_catalog if market_catalog is Dictionary else {}, event_definitions, operations, service_catalog, candidate_story, customer_catalog)
	if not receipt_error.is_empty():
		return _failure(receipt_error)
	var link_error := _story_receipt_error(payload.story, candidate_table.transaction_receipts)
	if not link_error.is_empty():
		return _failure(link_error)
	if not payload.runner is Dictionary:
		return _failure("invalid_runner_checkpoint")
	restored = candidate_runner.restore(payload.runner)
	if not restored.ok:
		return _failure("invalid_runner_checkpoint: " + str(restored.error))
	var event_error := validate_event_context(candidate_table, candidate_story, event_definitions)
	if not event_error.is_empty():
		return _failure(event_error)
	var candidate_bridge: RefCounted = null
	if payload.has("bridge"):
		var bridge_script: Script = load("res://scripts/content/module_action_bridge.gd")
		candidate_bridge = bridge_script.new()
		configured = candidate_bridge.configure(candidate_table, candidate_story, action_bindings, recipes, market_catalog if market_catalog is Dictionary else {}, event_definitions, operations, service_catalog, customer_catalog)
		if not configured.ok:
			return _failure("invalid_bridge_context: " + str(configured.error))
		restored = candidate_bridge.restore(payload.bridge)
		if not restored.ok:
			return _failure("invalid_bridge_checkpoint: " + str(restored.error))
	return {"ok": true, "table": candidate_table, "story": candidate_story, "runner": candidate_runner, "bridge": candidate_bridge, "error": ""}


static func _table_structure_error(data: Variant, context_table: TableState) -> String:
	if not _fields(data, ["cards", "stacks", "transaction_receipts", "next_card_id", "next_stack_id", "next_z"]):
		return "invalid_table_fields"
	for field: String in ["cards", "stacks", "transaction_receipts"]:
		if not data[field] is Dictionary:
			return "invalid_table_collection"
	for field: String in ["next_card_id", "next_stack_id", "next_z"]:
		if not _integer(data[field], 1, MAX_COUNTER):
			return "invalid_table_allocator"
	if data.cards.size() > TableState.MAX_CARDS or data.stacks.size() > TableState.MAX_CARDS or data.transaction_receipts.size() > MAX_RECEIPTS:
		return "table_collection_limit"
	var unique: Dictionary = {}
	for id: Variant in data.cards:
		if not _instance_id(id, "card", int(data.next_card_id)):
			return "invalid_card_instance_id"
		var card: Variant = data.cards[id]
		if not _fields(card, ["kind", "category", "zone", "metadata"]) or not card.metadata is Dictionary:
			return "invalid_card_fields"
		if not _text(card.kind) or not _text(card.category) or card.zone not in ["board", "queue", "bound"]:
			return "invalid_card_type_or_zone"
		var metadata: Dictionary = card.metadata
		var definition_id := context_table.content_id_for_kind(StringName(card.kind))
		if metadata.has("definition_id"):
			if not _text(metadata.definition_id):
				return "invalid_card_definition_id"
			definition_id = metadata.definition_id
		var definition := context_table.content_card_definition(definition_id)
		if definition.is_empty() or str(definition.get("kind", "")) != card.kind or str(definition.get("category", "")) != card.category:
			return "unregistered_or_mismatched_card_definition"
		var module_id := str(definition.get("module_id", ""))
		if str(metadata.get("module_id", "")) != module_id or (not module_id.is_empty() and not metadata.has("definition_id")):
			return "invalid_card_module_ownership"
		if metadata.has("module_id") and not metadata.module_id is String:
			return "invalid_module_id_type"
		if metadata.has("membership_revision") and not _integer(metadata.membership_revision, 0, MAX_COUNTER):
			return "invalid_membership_revision"
		for field: String in ["state", "order_id", "customer_id", "npc_id", "bound_to", "bound_sigil"]:
			if metadata.has(field) and not _text(metadata[field]):
				return "invalid_card_metadata_identity"
		if metadata.has("npc_id") and context_table.content_npc_definition(metadata.npc_id).is_empty():
			return "unknown_metadata_npc"
		if metadata.has("npc_id") and context_table.content_npc_definition(metadata.npc_id).get("card_id", "") != definition_id:
			return "npc_metadata_card_mismatch"
		if definition.get("unique", false) or definition_id in ["card.hero", "card.messenger"]:
			if unique.has(definition_id):
				return "duplicate_unique_card"
			unique[definition_id] = id
	var orders: Dictionary = {}
	for id: Variant in data.stacks:
		if not _instance_id(id, "stack", int(data.next_stack_id)):
			return "invalid_stack_instance_id"
		var stack: Variant = data.stacks[id]
		if not _fields(stack, ["id", "cards", "position", "z"]) or stack.id != id:
			return "invalid_stack_fields"
		if not _strings(stack.cards) or stack.cards.is_empty() or stack.cards.size() > TableState.MAX_STACK:
			return "invalid_stack_members"
		if not _position(stack.position) or not _integer(stack.z, 1, int(data.next_z) - 1):
			return "invalid_stack_position_or_order"
		if orders.has(int(stack.z)):
			return "duplicate_stack_order"
		orders[int(stack.z)] = true
	return ""


static func validate_receipts(table: TableState, recipes: Dictionary, market_catalog: Dictionary = {}, event_definitions: Variant = null, operations: Variant = null, service_catalog: Variant = null, story_session: Story = null, customer_catalog: Variant = null) -> String:
	return _receipts_error(table, recipes, market_catalog, event_definitions, operations, service_catalog, story_session, customer_catalog)


static func _receipts_error(table: TableState, recipes: Dictionary, market_catalog: Dictionary = {}, event_definitions: Variant = null, operations: Variant = null, service_catalog: Variant = null, story_session: Story = null, customer_catalog: Variant = null) -> String:
	var produced: Dictionary = {}
	var consumed: Dictionary = {}
	var service_error := validate_service_context(table, story_session, service_catalog, operations, market_catalog)
	if not service_error.is_empty():
		return service_error
	var policy := Services.market_policy(service_catalog) if service_catalog is Dictionary else {}
	# 原子复合操作的法印授权有一张子收据；只有完全匹配声明的那一枚才与父创建视为同一次。
	var linked_sigils := _operation_sigil_links(table, operations, Services.workbench_policy(service_catalog))
	if linked_sigils.has("error"):
		return str(linked_sigils.error)
	for id: Variant in table.transaction_receipts:
		var receipt: Variant = table.transaction_receipts[id]
		if not _text(id) or not receipt is Dictionary:
			return "invalid_transaction_receipt"
		if receipt.get("kind") == Services.KIND or id.begins_with("service/"):
			# 完整服务目录、实际解锁操作、任务当前状态和日额已在上面统一核验。
			continue
		if receipt.get("kind") == Operations.RECEIPT_KIND or id.begins_with("operation/") and receipt.get("kind") != Sigils.RECEIPT_KIND:
			if not operations is Dictionary:
				return "operation_catalog_context_required"
			var operation_error := Operations.validate_receipt(id, receipt, operations, table, story_session, Services.workbench_policy(service_catalog))
			if not operation_error.is_empty():
				return operation_error
			for card_id: String in receipt.participant_ids + receipt.created_ids:
				if not _instance_id(card_id, "card", table.next_card_id):
					return "invalid_operation_receipt_allocator"
			for card_id: String in receipt.consumed_ids:
				if consumed.has(card_id) or table.cards.has(card_id):
					return "consumed_instance_reappeared_or_consumed_twice"
				consumed[card_id] = id
			for card_id: String in receipt.created_ids:
				if produced.has(card_id):
					return "instance_produced_twice"
				produced[card_id] = id
			continue
		if id.begins_with(Events.TRANSACTION_PREFIX) or receipt.get("kind") == Events.RECEIPT_KIND:
			if not event_definitions is Dictionary:
				return "event_catalog_context_required"
			var event_error := Events.validate_receipt(id, receipt, event_definitions, table)
			if not event_error.is_empty():
				return event_error
			for card_id: String in receipt.removed_ids:
				if consumed.has(card_id) or table.cards.has(card_id):
					return "consumed_instance_reappeared_or_consumed_twice"
				consumed[card_id] = id
			for card_id: String in receipt.created_ids:
				if produced.has(card_id):
					return "instance_produced_twice"
				produced[card_id] = id
			continue
		if receipt.get("kind") == Market.RECEIPT_KIND:
			if not _fields(market_catalog, ["offers", "sources"]):
				return "market_catalog_context_required"
			var market_error := Market.validate_receipt(id, receipt, market_catalog.offers, market_catalog.sources, table, policy, operations if operations is Dictionary else {})
			if not market_error.is_empty():
				return market_error
			for card_id: String in receipt.input_instance_ids:
				if not _instance_id(card_id, "card", table.next_card_id) or consumed.has(card_id) or table.cards.has(card_id):
					return "consumed_instance_reappeared_or_consumed_twice"
				consumed[card_id] = id
			for card_id: String in receipt.output_instance_ids:
				if not _instance_id(card_id, "card", table.next_card_id) or produced.has(card_id):
					return "instance_produced_twice"
				produced[card_id] = id
			continue
		if id.begins_with("customer/") or receipt.get("kind") == Customers.SALE_RECEIPT_KIND:
			if not customer_catalog is Dictionary:
				return "customer_catalog_context_required"
			var customer_error := Customers.validate_sale_receipt(id, receipt, customer_catalog, table)
			if not customer_error.is_empty():
				return customer_error
			for card_id: String in receipt.input_instance_ids:
				if consumed.has(card_id) or table.cards.has(card_id):
					return "consumed_instance_reappeared_or_consumed_twice"
				consumed[card_id] = id
			for card_id: String in receipt.output_instance_ids:
				if produced.has(card_id):
					return "instance_produced_twice"
				produced[card_id] = id
			continue
		if id.begins_with("appointment/") or receipt.get("kind") == Appointments.KIND:
			if not operations is Dictionary or story_session == null:
				return "appointment_catalog_context_required"
			var appointment_error := Appointments.validate_receipt(id, receipt, operations, table, story_session)
			if not appointment_error.is_empty():
				return appointment_error
			continue
		if receipt.get("kind") == Sigils.RECEIPT_KIND:
			var sigil_error := Sigils.validate_receipt(id, receipt, table)
			if not sigil_error.is_empty():
				return sigil_error
			if not _instance_id(receipt.sigil_instance_id, "card", table.next_card_id) or not _instance_id(receipt.host_instance_id, "card", table.next_card_id):
				return "invalid_sigil_receipt_allocator"
			if receipt.action == "grant_bound":
				if linked_sigils.has(id):
					continue
				if produced.has(receipt.sigil_instance_id):
					return "instance_produced_twice"
				produced[receipt.sigil_instance_id] = id
			continue
		if not _transaction_id(id):
			return "unknown_transaction_receipt_kind"
		if receipt.get("ok") != true or receipt.get("transaction_id") != id or receipt.get("job_id") != id or not recipes.has(receipt.get("recipe_id")):
			return "invalid_receipt_identity"
		if receipt.get("status") == "cancelled":
			if not _fields(receipt, ["ok", "status", "job_id", "transaction_id", "recipe_id", "reason", "grants_facts"]) or not _text(receipt.reason) or receipt.grants_facts != []:
				return "invalid_cancelled_receipt"
			continue
		if not _fields(receipt, ["ok", "status", "job_id", "transaction_id", "recipe_id", "recipe_fingerprint", "source_id", "source_position", "input_instance_ids", "reusable_instance_ids", "output_instance_ids", "transformed_instance_id", "grants_facts"]) or receipt.status != "completed":
			return "invalid_completed_receipt_fields"
		var recipe: Dictionary = recipes[receipt.recipe_id]
		if receipt.recipe_fingerprint != Runner.canonical_digest(recipe):
			return "receipt_recipe_fingerprint_mismatch"
		var all_ids: Dictionary = {}
		for field: String in ["input_instance_ids", "reusable_instance_ids", "output_instance_ids"]:
			if not _strings(receipt[field]):
				return "invalid_receipt_instances"
			for card_id: String in receipt[field]:
				if not _instance_id(card_id, "card", table.next_card_id) or all_ids.has(card_id):
					return "invalid_or_reused_receipt_instance"
				all_ids[card_id] = true
		if receipt.input_instance_ids.size() != _count(recipe.inputs) or receipt.reusable_instance_ids.size() != _count(recipe.reusable) or receipt.output_instance_ids.size() != _count(recipe.outputs):
			return "receipt_recipe_count_mismatch"
		for card_id: String in receipt.input_instance_ids:
			if consumed.has(card_id) or table.cards.has(card_id):
				return "consumed_instance_reappeared_or_consumed_twice"
			consumed[card_id] = id
		for card_id: String in receipt.output_instance_ids:
			if produced.has(card_id):
				return "instance_produced_twice"
			produced[card_id] = id
		if receipt.source_id not in receipt.input_instance_ids and receipt.source_id not in receipt.reusable_instance_ids:
			return "invalid_receipt_source"
		if not _position(receipt.source_position) or not _strings(receipt.grants_facts) or receipt.grants_facts != recipe.get("grants_facts", []):
			return "invalid_receipt_position_or_facts"
		if not TableState.WORLD_BOUNDS.has_point(Vector2(float(receipt.source_position[0]), float(receipt.source_position[1]))):
			return "receipt_position_outside_board"
		if not receipt.transformed_instance_id is String or (recipe.action == "craft" and not receipt.transformed_instance_id.is_empty()) or (recipe.action == "transform" and receipt.transformed_instance_id not in receipt.reusable_instance_ids):
			return "invalid_receipt_transform_identity"
	for id: String in table.cards:
		var metadata: Dictionary = table.cards[id].metadata
		if metadata.has("production_transaction_id") != metadata.has("production_source_position"):
			return "incomplete_production_metadata"
		if not metadata.has("production_transaction_id"):
			continue
		var transaction: Variant = metadata.production_transaction_id
		if not _text(transaction) or not table.transaction_receipts.has(transaction):
			return "missing_production_receipt"
		var receipt: Dictionary = table.transaction_receipts[transaction]
		var outputs: Array = receipt.get("created_ids", []) if receipt.get("kind") == Operations.RECEIPT_KIND else receipt.get("output_instance_ids", [])
		if receipt.status != "completed" or id not in outputs or Runner.canonical_digest(metadata.production_source_position) != Runner.canonical_digest(receipt.source_position):
			return "mismatched_production_receipt"
	return ""


static func validate_operation_context(table: TableState, story: Story, operations: Variant = null, workbench_policy: Variant = null) -> String:
	if table == null or story == null:
		return "missing_operation_context"
	if operations != null:
		if not operations is Dictionary:
			return "invalid_operation_catalog_context"
		var error := Operations.validate_catalog(operations, table, story, workbench_policy)
		if not error.is_empty():
			return error
	for tx: String in table.transaction_receipts:
		var receipt: Variant = table.transaction_receipts[tx]
		if not receipt is Dictionary or receipt.get("kind") != Operations.RECEIPT_KIND:
			continue
		if operations == null:
			return "operation_catalog_context_required"
		var error := Operations.validate_receipt(tx, receipt, operations, table, story, workbench_policy)
		if not error.is_empty():
			return error
	return ""


static func validate_service_context(table: TableState, story: Story, service_catalog: Variant = null, operations: Variant = null, market_catalog: Variant = null) -> String:
	if table == null:
		return "missing_service_table"
	if service_catalog == null:
		for tx: Variant in table.transaction_receipts:
			var receipt: Variant = table.transaction_receipts[tx]
			if (tx is String and tx.begins_with("service/")) or (receipt is Dictionary and (receipt.get("kind") == Services.KIND or (receipt.get("kind") == Market.RECEIPT_KIND and receipt.get("version") == 2))):
				return "service_catalog_context_required"
		return ""
	if not service_catalog is Dictionary or not operations is Dictionary or not market_catalog is Dictionary or story == null:
		return "invalid_service_catalog_context"
	var error := Services.validate_catalog(service_catalog, operations, market_catalog, table, story)
	if not error.is_empty():
		return error
	return Services.validate_table(table, story, service_catalog, operations, market_catalog)


static func _operation_sigil_links(table: TableState, operations: Variant, workbench_policy: Variant = null) -> Dictionary:
	var linked := {}
	if not operations is Dictionary:
		return linked
	for tx: String in table.transaction_receipts:
		var receipt: Variant = table.transaction_receipts[tx]
		if not receipt is Dictionary or receipt.get("kind") != Operations.RECEIPT_KIND or receipt.get("status") != "completed":
			continue
		if not operations.has(receipt.get("operation_id")):
			return {"error": "unknown_operation_receipt"}
		var error := Operations.validate_receipt(tx, receipt, operations, table, null, workbench_policy)
		if not error.is_empty():
			return {"error": error}
		var operation: Dictionary = operations[receipt.operation_id]
		for effect: Variant in operation.get("sigil_effects", []):
			if not effect is Dictionary or effect.get("action") != "grant_bound":
				continue
			var child_id := Sigils.GRANT_PREFIX + str(effect.event_id)
			var child: Variant = table.transaction_receipts.get(child_id)
			if not child is Dictionary or linked.has(child_id) or child.get("kind") != Sigils.RECEIPT_KIND or child.get("action") != "grant_bound" or child.get("sigil_definition_id") != effect.sigil_definition_id or child.get("sigil_instance_id") not in receipt.get("created_ids", []):
				return {"error": "operation_sigil_grant_receipt_mismatch"}
			linked[child_id] = tx
	return linked


static func _story_receipt_error(story_data: Variant, receipts: Dictionary) -> String:
	if not story_data is Dictionary or not story_data.get("state") is Dictionary or not story_data.state.get("transactions") is Dictionary:
		return "invalid_story_transaction_map"
	# 此处验证真实已提交事务存在；action 到具体 recipe 的语义绑定由后续桥接器负责。
	for id: Variant in story_data.state.transactions:
		if not receipts.has(id) or not receipts[id] is Dictionary or receipts[id].get("status") != "completed" or receipts[id].get("transaction_id") != id:
			return "story_action_missing_completed_table_receipt"
		if receipts[id].get("kind") == Events.RECEIPT_KIND or (id is String and id.begins_with(Events.TRANSACTION_PREFIX)):
			return "story_action_cannot_use_chapter_event"
		if receipts[id].get("kind") == Services.KIND or (id is String and id.begins_with("service/")):
			return "story_action_cannot_use_service_receipt"
	return ""


static func validate_event_context(table: TableState, story: Story, event_definitions: Variant = null) -> String:
	if table == null or story == null:
		return "missing_event_checkpoint_participant"
	if event_definitions == null:
		for id: Variant in table.transaction_receipts:
			var receipt: Variant = table.transaction_receipts[id]
			if (id is String and id.begins_with(Events.TRANSACTION_PREFIX)) or (receipt is Dictionary and (receipt.has("event_fingerprint") or receipt.get("kind") == Events.RECEIPT_KIND)):
				return "event_catalog_context_required"
		return ""
	if not event_definitions is Dictionary:
		return "invalid_event_catalog_context"
	var validator := Events.new()
	var configured := validator.configure(table, story, event_definitions)
	if not configured.ok:
		return "invalid_event_context: " + str(configured.error)
	# 捕获时尚未取得配方目录，先验证事件与全部既有事务的实例分配不冲突。
	var event_produced := {}
	var event_removed := {}
	for id: String in table.transaction_receipts:
		var receipt: Variant = table.transaction_receipts[id]
		if not receipt is Dictionary or receipt.get("kind") != Events.RECEIPT_KIND:
			continue
		for card_id: String in receipt.created_ids:
			if event_produced.has(card_id):
				return "instance_produced_twice"
			event_produced[card_id] = true
		for card_id: String in receipt.removed_ids:
			if event_removed.has(card_id):
				return "consumed_instance_reappeared_or_consumed_twice"
			event_removed[card_id] = true
	for receipt: Variant in table.transaction_receipts.values():
		if not receipt is Dictionary or receipt.get("kind") == Events.RECEIPT_KIND:
			continue
		if receipt.get("kind") == Sigils.RECEIPT_KIND and receipt.get("action") == "grant_bound" and event_produced.has(receipt.get("sigil_instance_id")):
			return "instance_produced_twice"
		for field: String in ["output_instance_ids", "input_instance_ids"]:
			if receipt.has(field) and (not receipt[field] is Array or receipt[field].size() > TableState.MAX_CARDS):
				return "invalid_event_peer_receipt_instances"
		for card_id: Variant in receipt.get("output_instance_ids", []):
			if event_produced.has(card_id):
				return "instance_produced_twice"
		for card_id: Variant in receipt.get("input_instance_ids", []):
			if event_removed.has(card_id):
				return "consumed_instance_reappeared_or_consumed_twice"
	return ""


static func _market_context_error(table: TableState, catalog: Variant, service_catalog: Variant = null, operations: Variant = null) -> String:
	if catalog == null:
		for id: Variant in table.transaction_receipts:
			var receipt: Variant = table.transaction_receipts[id]
			if (id is String and id.begins_with("market/")) or (receipt is Dictionary and receipt.get("kind") == Market.RECEIPT_KIND):
				return "market_catalog_context_required"
		return ""
	if not _fields(catalog, ["offers", "sources"]) or not catalog.offers is Dictionary or not catalog.sources is Dictionary:
		return "invalid_market_catalog_context"
	var policy := Services.market_policy(service_catalog) if service_catalog is Dictionary else {}
	return Market.validate_table(table, catalog.offers, catalog.sources, policy, operations if operations is Dictionary else {})


static func _modules(table: TableState) -> Array:
	var result := table.content_module_ids().duplicate()
	result.sort()
	return result


static func _catalog_fingerprint(table: TableState) -> String:
	var definitions: Dictionary = {}
	for id: String in table.content_card_ids():
		var definition := table.content_card_definition(id)
		var semantic := {}
		# 更换插画、颜色或译名不能使已有进度失效；规则字段仍严格匹配。
		for field: String in ["id", "kind", "category", "unique", "protected", "sellable", "module_id"]:
			if definition.has(field):
				semantic[field] = definition[field]
		var tags: Array = definition.get("tags", []).duplicate()
		tags.sort()
		semantic.tags = tags
		definitions[id] = semantic
	return Runner.canonical_digest(definitions)


static func _fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: Variant in fields:
		if not value.has(field):
			return false
	return true


static func _text(value: Variant) -> bool:
	return value is String and not value.is_empty()


static func _strings(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not _text(item) or seen.has(item):
			return false
		seen[item] = true
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and float(value) >= minimum and float(value) <= maximum


static func _position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))


static func _instance_id(value: Variant, prefix: String, next: int) -> bool:
	if not _text(value) or not value.begins_with(prefix + "_"):
		return false
	var suffix: String = value.trim_prefix(prefix + "_")
	if not suffix.is_valid_int():
		return false
	var number := int(suffix)
	return number > 0 and number < next and value == "%s_%04d" % [prefix, number]


static func _transaction_id(id: String) -> bool:
	var parts := id.split("/")
	return parts.size() == 3 and parts[0] == "recipe" and not parts[1].is_empty() and parts[2].is_valid_int() and int(parts[2]) > 0 and str(int(parts[2])) == parts[2]


static func _count(rules: Array) -> int:
	var total := 0
	for rule: Dictionary in rules:
		total += int(rule.count)
	return total


static func _safe(value: Variant, allow_native: bool, depth: int, budget: Dictionary) -> bool:
	budget.visited += 1
	if depth > 32 or int(budget.visited) > 600000:
		return false
	if value == null or value is bool:
		return true
	if value is String or (allow_native and value is StringName):
		return str(value).length() <= 4096
	if value is int or value is float:
		return is_finite(float(value)) and absf(float(value)) <= 9007199254740991.0
	if allow_native and value is Vector2:
		return is_finite(value.x) and is_finite(value.y)
	if value is Array:
		for item: Variant in value:
			if not _safe(item, allow_native, depth + 1, budget):
				return false
		return true
	if value is Dictionary:
		var keys: Dictionary = {}
		for key: Variant in value:
			if not (key is String or (allow_native and key is StringName)) or str(key).length() > 4096 or keys.has(str(key)):
				return false
			keys[str(key)] = true
			if not _safe(value[key], allow_native, depth + 1, budget):
				return false
		return true
	return false


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "table": null, "story": null, "runner": null, "bridge": null, "error": error}
