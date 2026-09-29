class_name ChapterServiceEffects
extends RefCounted

const Canon = preload("res://scripts/content/module_recipe_runner.gd")
const Operations = preload("res://scripts/content/chapter_operation_runner.gd")
const Story = preload("res://scripts/content/module_story_session.gd")
const Market = preload("res://scripts/content/module_market_exchange.gd")
const KIND := "chapter_service"
const CONTEXT_ID := "service/context"

var _table: TableState
var _story: Story
var _catalog: Dictionary = {}
var _operations: Dictionary = {}
var _market: Dictionary = {}


# 配置和查询只读。真实入镇后由控制器显式 activate，序章不会偷偷写章节回执。
func configure(table: TableState, story: Story, catalog: Dictionary, operations: Dictionary, market_catalog: Dictionary) -> Dictionary:
	var error := validate_catalog(catalog, operations, market_catalog, table, story)
	if error.is_empty():
		error = validate_table(table, story, catalog, operations, market_catalog)
	if not error.is_empty():
		return _fail(error)
	_table = table
	_story = story
	_catalog = catalog.duplicate(true)
	_operations = operations.duplicate(true)
	_market = market_catalog.duplicate(true)
	return {"ok": true, "error": ""}


# 激活不发资源，不解锁服务；只固定共享市场政策和激活前的合法历史单据。
func activate(day: Variant) -> Dictionary:
	if _table == null:
		return _fail("services_not_configured")
	var error := validate_table(_table, _story, _catalog, _operations, _market)
	if not error.is_empty():
		return _fail(error)
	if not Market._integer(day, 1, Market.MAX_DAY):
		return _fail("invalid_service_day")
	if _table.transaction_receipts.has(CONTEXT_ID):
		return _replay(_table.transaction_receipts[CONTEXT_ID])
	if _latest_day(_table) > int(day):
		return _fail("service_day_cannot_regress")
	var baseline: Dictionary = {}
	for tx: String in _table.transaction_receipts:
		var value: Dictionary = _table.transaction_receipts[tx]
		if value.get("kind") == "market_exchange":
			baseline[tx] = Canon.canonical_digest(value)
	var receipt := {"kind": KIND, "version": 1, "status": "completed", "action": "activate_context",
		"transaction_id": CONTEXT_ID, "day": int(day), "context": capture_context(), "market_baseline": baseline}
	var candidate := _table.fork_empty()
	candidate.restore(_table.snapshot())
	candidate.transaction_receipts[CONTEXT_ID] = receipt
	error = validate_table(candidate, _story, _catalog, _operations, _market)
	if not error.is_empty():
		return _fail(error)
	_table.restore(candidate.snapshot())
	var result := receipt.duplicate(true)
	result.merge({"ok": true, "already_applied": false})
	return result


# 将炉屋已经备好的普通行前餐交给这张真实任务卡；后续长任务仍由操作执行器计时。
# 不产出食物卡、货币或NPC，不跳过任务本身，也不覆盖请客的餐食。
func prepare(service_id: String, task_id: String, instance_ids: Array[String], day: Variant, transaction_id: String) -> Dictionary:
	if _table == null:
		return _fail("services_not_configured")
	var error := validate_table(_table, _story, _catalog, _operations, _market)
	if not error.is_empty():
		return _fail(error)
	if not _table.transaction_receipts.has(CONTEXT_ID):
		return _fail("service_context_not_active")
	if not Market._integer(day, 1, Market.MAX_DAY) or not Market._strings(instance_ids, false) or not _prep_tx(transaction_id):
		return _fail("invalid_service_request")
	var ids := instance_ids.duplicate()
	ids.sort()
	var request := {"service_id": service_id, "task_id": task_id, "participant_ids": ids, "day": int(day)}
	if _table.transaction_receipts.has(transaction_id):
		var prior: Dictionary = _table.transaction_receipts[transaction_id]
		if prior.get("kind") != KIND or Canon.canonical_digest(prior.get("request")) != Canon.canonical_digest(request):
			return _fail("service_transaction_conflict")
		return _replay(prior)
	if _story.to_data().state.paused:
		return _fail("service_story_paused")
	if _latest_day(_table) > int(day):
		return _fail("service_day_cannot_regress")
	var hearth: Dictionary = _catalog.hearth
	if service_id != hearth.id or not hearth.tasks.has(task_id):
		return _fail("unknown_service_task")
	var unlock := _unlock(_table, hearth.unlock_operation_id)
	if unlock.is_empty():
		return _fail("service_arrangement_not_completed")
	var count := 0
	for value: Dictionary in _table.transaction_receipts.values():
		if value.get("kind") == KIND and value.get("action") == "prepare" and value.service_id == service_id and int(value.day) == int(day):
			count += 1
	if count >= int(hearth.daily_limit):
		return _fail("service_daily_limit_reached")
	var task: Dictionary = hearth.tasks[task_id]
	var prep: Dictionary = _operations[task.preparation_operation_id]
	var state: Dictionary = _story.to_data().state
	var facts: Array = state.facts.duplicate()
	for value: Dictionary in _table.transaction_receipts.values():
		if value.get("kind") == "chapter_operation" and value.get("status") == "completed":
			for fact: String in value.grants_facts:
				if fact not in facts:
					facts.append(fact)
	for id: String in prep.requires_stories:
		if id not in state.completed:
			return _fail("service_task_story_unavailable")
	for fact: String in prep.requires_facts:
		if fact not in facts:
			return _fail("service_task_fact_unavailable")
	for fact: String in prep.forbidden_facts:
		if fact in facts:
			return _fail("service_task_forbidden")
	var actual: Dictionary = {}
	var refs: Dictionary = {}
	var stack_id := ""
	for id: String in ids:
		if not _table.cards.has(id) or _table.cards[id].zone != &"board" or _table.sigil_instance_locked(id):
			return _fail("service_participant_missing_or_locked")
		var stack := _table.stack_for(id)
		if stack_id.is_empty():
			stack_id = stack
		if stack != stack_id:
			return _fail("service_participants_not_stacked")
		var definition := _table.definition_id_for_card(id)
		var authored := _table.content_card_definition(definition)
		if authored.get("category") == "character" and definition != "card.hero":
			var npc: String = str(_table.cards[id].metadata.get("npc_id", ""))
			if npc.is_empty() or _table.content_npc_definition(npc).get("card_id") != definition:
				return _fail("service_provider_identity_mismatch")
		actual[definition] = int(actual.get(definition, 0)) + 1
		refs[definition] = id
	var expected := Market._counts(prep.participants)
	expected.erase(task.meal_card_id)
	if actual != expected or _table.stacks[stack_id].cards.size() != ids.size():
		return _fail("service_participant_multiset_mismatch")
	for condition: Dictionary in prep.requires_metadata:
		for key: String in condition.values:
			if _table.cards[refs[condition.card_id]].metadata.get(key) != condition.values[key]:
				return _fail("service_task_metadata_mismatch")
	var task_instance: String = refs[task.task_card_id]
	var transform: Dictionary = prep.transforms[0]
	if _table.cards[task_instance].metadata.get("state") != transform.require_state:
		return _fail("service_task_already_prepared_or_invalid")
	for value: Dictionary in _table.transaction_receipts.values():
		if value.get("kind") == KIND and value.get("action") == "prepare" and value.task_instance_id == task_instance:
			return _fail("service_task_already_prepared")
	var source: String = refs[task.provider_card_id]
	var position := _table.card_position(source)
	var receipt := {"kind": KIND, "version": 1, "status": "completed", "action": "prepare", "transaction_id": transaction_id,
		"service_id": service_id, "task_id": task_id, "task_instance_id": task_instance, "participant_ids": ids,
		"day": int(day), "unlock_transaction_id": unlock, "catalog_fingerprint": Canon.canonical_digest(_catalog),
		"preparation_fingerprint": Canon.canonical_digest(prep), "source_id": source,
		"source_position": [position.x, position.y], "grants_facts": prep.grants_facts.duplicate(),
		"created_ids": [], "consumed_ids": [], "request": request}
	var candidate := _table.fork_empty()
	candidate.restore(_table.snapshot())
	candidate.cards[task_instance].metadata.state = transform.set_state
	candidate.transaction_receipts[transaction_id] = receipt
	error = validate_table(candidate, _story, _catalog, _operations, _market)
	if not error.is_empty():
		return _fail(error)
	_table.restore(candidate.snapshot())
	var result := receipt.duplicate(true)
	result.merge({"ok": true, "already_applied": false})
	return result


func capture_context() -> Dictionary:
	return context_for(_catalog, _operations, _market)


static func context_for(catalog: Dictionary, operations: Dictionary, market_catalog: Dictionary) -> Dictionary:
	return {"version": 1, "catalog_fingerprint": Canon.canonical_digest(catalog),
		"operation_catalog_fingerprint": Canon.canonical_digest(operations), "market_catalog_fingerprint": Canon.canonical_digest(market_catalog)}


static func market_policy(catalog: Dictionary) -> Dictionary:
	var result := {"catalog_fingerprint": Canon.canonical_digest(catalog), "rule": catalog.consignment.duplicate(true)}
	if catalog.has("workbench"):
		result["workbench_policy"] = catalog.workbench.duplicate(true) if catalog.workbench is Dictionary else catalog.workbench
	return result


static func workbench_policy(catalog: Variant) -> Variant:
	return catalog.get("workbench") if catalog is Dictionary else null


static func validate_catalog(catalog: Dictionary, operations: Dictionary, market_catalog: Dictionary, table: TableState, story: Story) -> String:
	var fields := ["version", "hearth", "consignment", "deferred_contracts"]
	if catalog.has("workbench"):
		fields.append("workbench")
	if table == null or story == null or not Market._fields(catalog, fields) or not Market._integer(catalog.version, 1, 1):
		return "invalid_service_catalog"
	if not Market._fields(market_catalog, ["offers", "sources"]) or not market_catalog.offers is Dictionary or not market_catalog.sources is Dictionary:
		return "invalid_service_market_context"
	var error := Operations.validate_catalog(operations, table, story, workbench_policy(catalog))
	if not error.is_empty():
		return error
	error = Market.validate_catalog(market_catalog.offers, market_catalog.sources, table)
	if not error.is_empty():
		return error
	var hearth: Variant = catalog.hearth
	if not Market._fields(hearth, ["id", "name_key", "description_key", "unlock_operation_id", "daily_limit", "tasks"]) or not _named(hearth) or not operations.has(hearth.unlock_operation_id) or not Market._integer(hearth.daily_limit, 1, 1) or not hearth.tasks is Dictionary or hearth.tasks.is_empty():
		return "invalid_hearth_service"
	for task_id: Variant in hearth.tasks:
		var task: Variant = hearth.tasks[task_id]
		if not Market._identifier(task_id) or not Market._fields(task, ["preparation_operation_id", "followup_operation_id", "task_card_id", "provider_card_id", "meal_card_id"]):
			return "invalid_service_task_definition"
		for key: String in task:
			if not task[key] is String or task[key].is_empty():
				return "invalid_service_task_reference"
		if not operations.has(task.preparation_operation_id) or not operations.has(task.followup_operation_id):
			return "unknown_service_task_operation"
		var prep: Dictionary = operations[task.preparation_operation_id]
		var next: Dictionary = operations[task.followup_operation_id]
		var counts := Market._counts(prep.participants)
		if counts.get(task.task_card_id) != 1 or counts.get(task.provider_card_id) != 1 or counts.get(task.meal_card_id) != 1 or counts.get("card.hero") != 1:
			return "service_preparation_participants_unsupported"
		if Market._counts(prep.consume) != {task.meal_card_id: 1} or not prep.creates.is_empty() or not prep.sigil_effects.is_empty() or prep.transforms.size() != 1:
			return "service_preparation_effects_unsupported"
		if not prep.forbidden_facts.is_empty():
			return "service_preparation_nonmonotonic_conditions_unsupported"
		var transform: Dictionary = prep.transforms[0]
		if transform.card_id != task.task_card_id or transform.to_card_id != task.task_card_id or transform.require_state.is_empty() or transform.set_state.is_empty() or transform.require_state == transform.set_state or prep.source_card_id != task.provider_card_id:
			return "service_task_state_transition_unsupported"
		if Market._counts(next.participants).get(task.task_card_id) != 1 or float(next.duration) < 15.0:
			return "service_followup_is_not_real_long_task"
		var accepts_prepared := false
		for condition: Dictionary in next.requires_metadata:
			if condition.card_id == task.task_card_id and condition.values.get("state") == transform.set_state:
				accepts_prepared = true
		if not accepts_prepared:
			return "service_followup_does_not_consume_preparation_state"
		for condition: Dictionary in prep.requires_metadata:
			if condition.values.has("bound_sigil_definition_id"):
				return "service_preparation_cannot_replace_magic_requirement"
		if table.content_card_definition(task.meal_card_id).get("category") != "item" or table.content_card_definition(task.provider_card_id).get("category") != "character":
			return "service_task_food_or_provider_invalid"
	if not catalog.deferred_contracts is Dictionary:
		return "invalid_deferred_service_contracts"
	for value: Variant in catalog.deferred_contracts.values():
		if not value is Dictionary or value.get("enabled") != false or not value.get("contract") is String:
			return "unsupported_service_cannot_be_enabled"
	return Market.validate_service_policy(market_policy(catalog), operations, market_catalog.offers, table)


static func validate_receipt(tx: String, value: Variant, catalog: Dictionary, operations: Dictionary, market_catalog: Dictionary, table: TableState, story: Story) -> String:
	var catalog_error := validate_catalog(catalog, operations, market_catalog, table, story)
	if not catalog_error.is_empty():
		return catalog_error
	if not value is Dictionary or value.get("kind") != KIND or not Market._integer(value.get("version"), 1, 1) or value.get("status") != "completed" or value.get("transaction_id") != tx or not Market._integer(value.get("day"), 1, Market.MAX_DAY):
		return "invalid_service_receipt_identity"
	if value.get("action") == "activate_context":
		if not Market._fields(value, ["kind", "version", "status", "action", "transaction_id", "day", "context", "market_baseline"]) or tx != CONTEXT_ID or not value.market_baseline is Dictionary or Canon.canonical_digest(value.context) != Canon.canonical_digest(context_for(catalog, operations, market_catalog)):
			return "invalid_service_context_receipt"
		for id: Variant in value.market_baseline:
			if not id is String or not table.transaction_receipts.has(id) or not table.transaction_receipts[id] is Dictionary or Canon.canonical_digest(table.transaction_receipts[id]) != value.market_baseline[id] or table.transaction_receipts[id].get("kind") != "market_exchange" or int(table.transaction_receipts[id].get("day", 0)) > int(value.day):
				return "service_market_baseline_mismatch"
		return ""
	if not _prep_tx(tx) or value.get("action") != "prepare" or not Market._fields(value, ["kind", "version", "status", "action", "transaction_id", "service_id", "task_id", "task_instance_id", "participant_ids", "day", "unlock_transaction_id", "catalog_fingerprint", "preparation_fingerprint", "source_id", "source_position", "grants_facts", "created_ids", "consumed_ids", "request"]):
		return "invalid_service_preparation_receipt"
	var hearth: Dictionary = catalog.hearth
	if value.service_id != hearth.id or not value.task_id is String or not hearth.tasks.has(value.task_id) or value.catalog_fingerprint != Canon.canonical_digest(catalog):
		return "service_receipt_catalog_mismatch"
	var task: Dictionary = hearth.tasks[value.task_id]
	var prep: Dictionary = operations[task.preparation_operation_id]
	if value.preparation_fingerprint != Canon.canonical_digest(prep) or value.grants_facts != prep.grants_facts or value.created_ids != [] or value.consumed_ids != []:
		return "service_receipt_effect_mismatch"
	if not Market._strings(value.participant_ids, false) or value.participant_ids.size() != Market._total(prep.participants) - 1 or not Market._position(value.source_position):
		return "invalid_service_receipt_participants"
	for id: Variant in value.participant_ids:
		if not Market._instance_id(id) or int(id.trim_prefix("card_")) >= table.next_card_id:
			return "invalid_service_receipt_instance"
	if not value.task_instance_id is String or not value.source_id is String or value.task_instance_id not in value.participant_ids or value.source_id not in value.participant_ids or value.task_instance_id == value.source_id:
		return "invalid_service_receipt_task_or_source"
	if table.cards.has(value.task_instance_id) and table.definition_id_for_card(value.task_instance_id) != task.task_card_id:
		return "service_receipt_task_identity_changed"
	if table.cards.has(value.source_id) and table.definition_id_for_card(value.source_id) != task.provider_card_id:
		return "service_receipt_provider_identity_changed"
	if not value.unlock_transaction_id is String or not table.transaction_receipts.has(value.unlock_transaction_id):
		return "service_unlock_receipt_missing"
	var unlock: Dictionary = table.transaction_receipts[value.unlock_transaction_id]
	if unlock.get("operation_id") != hearth.unlock_operation_id or unlock.get("status") != "completed":
		return "service_unlock_receipt_mismatch"
	var error := Operations.validate_receipt(value.unlock_transaction_id, unlock, operations, table, story, workbench_policy(catalog))
	if not error.is_empty():
		return error
	var state: Dictionary = story.to_data().state
	for required: String in prep.requires_stories:
		if required not in state.completed:
			return "service_receipt_required_story_missing"
	var proven: Array = state.facts.duplicate()
	for id: Variant in table.transaction_receipts:
		var evidence: Variant = table.transaction_receipts[id]
		if evidence is Dictionary and evidence.get("kind") == "chapter_operation" and evidence.get("status") == "completed":
			error = Operations.validate_receipt(str(id), evidence, operations, table, story, workbench_policy(catalog))
			if not error.is_empty():
				return error
			for fact: String in evidence.grants_facts:
				if fact not in proven:
					proven.append(fact)
	for required: String in prep.requires_facts:
		if required not in proven:
			return "service_receipt_task_acceptance_missing"
	if not Market._fields(value.request, ["service_id", "task_id", "participant_ids", "day"]) or value.request.service_id != value.service_id or value.request.task_id != value.task_id or value.request.participant_ids != value.participant_ids or value.request.day != value.day:
		return "service_receipt_request_mismatch"
	return ""


static func validate_table(table: TableState, story: Story, catalog: Dictionary, operations: Dictionary, market_catalog: Dictionary) -> String:
	if table == null or story == null:
		return "service_context_missing"
	var error := table.validate()
	if not error.is_empty():
		return error
	var quotas: Dictionary = {}
	var tasks: Dictionary = {}
	var context_value: Variant = table.transaction_receipts.get(CONTEXT_ID, {})
	if not context_value is Dictionary:
		return "invalid_service_context_receipt"
	var context: Dictionary = context_value
	for tx: Variant in table.transaction_receipts:
		var value: Variant = table.transaction_receipts[tx]
		if not tx is String or not value is Dictionary:
			return "invalid_service_ledger_entry"
		if value.get("kind") == "chapter_operation":
			error = Operations.validate_receipt(tx, value, operations, table, story, workbench_policy(catalog))
		elif value.get("kind") == KIND or tx.begins_with("service/"):
			error = validate_receipt(tx, value, catalog, operations, market_catalog, table, story)
			if error.is_empty() and value.action == "prepare":
				if context.is_empty() or int(value.day) < int(context.day):
					return "service_preparation_without_active_context"
				var key: String = str(int(value.day)) + ":" + value.service_id
				quotas[key] = int(quotas.get(key, 0)) + 1
				if quotas[key] > int(catalog.hearth.daily_limit) or tasks.has(value.task_instance_id):
					return "service_ledger_reuses_day_or_task"
				tasks[value.task_instance_id] = true
				error = _task_state_error(value, catalog, operations, table)
		if not error.is_empty():
			return error
	var policy := market_policy(catalog) if not context.is_empty() else {}
	return Market.validate_table(table, market_catalog.offers, market_catalog.sources, policy, operations)


static func _task_state_error(receipt: Dictionary, catalog: Dictionary, operations: Dictionary, table: TableState) -> String:
	var id: String = receipt.task_instance_id
	if not table.cards.has(id):
		return ""
	var task: Dictionary = catalog.hearth.tasks[receipt.task_id]
	var prep: Dictionary = operations[task.preparation_operation_id]
	var expected_state: String = prep.transforms[0].set_state
	var followup: Dictionary = operations[task.followup_operation_id]
	for value: Variant in table.transaction_receipts.values():
		if not value is Dictionary or value.get("kind") != "chapter_operation" or value.get("status") != "completed" or value.get("operation_id") != task.followup_operation_id:
			continue
		if not value.get("transformed_ids") is Array:
			return "service_followup_receipt_invalid"
		if id in value.transformed_ids:
			for transform: Dictionary in followup.transforms:
				if transform.card_id == task.task_card_id and not transform.set_state.is_empty():
					expected_state = transform.set_state
	var metadata: Dictionary = table.cards[id].metadata
	if metadata.get("state") != expected_state:
		return "service_prepared_task_state_mismatch"
	for condition: Dictionary in prep.requires_metadata:
		if condition.card_id == task.task_card_id:
			for key: String in condition.values:
				if key != "state" and metadata.get(key) != condition.values[key]:
					return "service_prepared_task_identity_mismatch"
	return ""


static func _unlock(table: TableState, operation_id: String) -> String:
	for tx: String in table.transaction_receipts:
		var value: Dictionary = table.transaction_receipts[tx]
		if value.get("kind") == "chapter_operation" and value.get("operation_id") == operation_id and value.get("status") == "completed":
			return tx
	return ""


static func _latest_day(table: TableState) -> int:
	var day := 0
	for value: Dictionary in table.transaction_receipts.values():
		if value.get("kind") in [KIND, "market_exchange"]:
			day = maxi(day, int(value.get("day", 0)))
	return day


static func _named(value: Dictionary) -> bool:
	return Market._identifier(value.get("id")) and value.get("name_key") is String and not value.name_key.is_empty() and value.get("description_key") is String and not value.description_key.is_empty()


static func _prep_tx(value: String) -> bool:
	return value.begins_with("service/prep/") and Market._identifier(value.trim_prefix("service/prep/"))


static func _replay(receipt: Dictionary) -> Dictionary:
	var result := receipt.duplicate(true)
	result.merge({"ok": true, "already_applied": true})
	return result


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}
