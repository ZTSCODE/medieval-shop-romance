class_name ModuleSceneScheduler
extends RefCounted

const Story = preload("res://scripts/content/module_story_session.gd")
const Runner = preload("res://scripts/content/module_recipe_runner.gd")
const Events = preload("res://scripts/content/module_event_effects.gd")
const Operations = preload("res://scripts/content/chapter_operation_runner.gd")
const Services = preload("res://scripts/content/chapter_service_effects.gd")

var _table: TableState
var _session: Story
var _rules: Dictionary = {}
var _recipes: Dictionary = {}
var _event_definitions: Dictionary = {}
var _operations: Dictionary = {}
var _service_catalog: Variant = null
var _market_catalog: Dictionary = {}
var _busy := false


# 只配置场次资格；不把场次列表顺序变成固定剧情顺序，不自动触发或补发奖励。
func configure(table: TableState, story_session: Story, rules: Dictionary, recipes: Dictionary, event_definitions: Dictionary = {}, operations: Dictionary = {}, service_catalog: Variant = null, market_catalog: Dictionary = {}) -> Dictionary:
	if _busy:
		return _failure("scheduler_is_requesting_story")
	if table == null or story_session == null or story_session.to_data().catalog_fingerprint.is_empty():
		return _failure("missing_or_unconfigured_participant")
	if not table.validate().is_empty() or rules.size() > Story.MAX_STORIES:
		return _failure("invalid_table_or_rule_count")
	var events := Events.new()
	var event_check := events.configure(table, story_session, event_definitions)
	if not event_check.ok:
		return _failure("invalid_event_qualification_context: " + str(event_check.error))
	var service_error := _service_error(table, story_session, service_catalog, operations, market_catalog)
	if not service_error.is_empty():
		return _failure(service_error)
	var validator := Runner.new()
	if not validator.configure(table.fork_empty(), recipes).ok:
		return _failure("invalid_recipe_context")
	for id: Variant in rules:
		var rule: Variant = rules[id]
		if not id is String or not story_session.story_exists(id):
			return _failure("unknown_rule_story")
		var expected_fields := ["npc_id", "requires_completed", "requires_facts", "requires_recipes", "requires_cards", "not_completed"]
		if rule is Dictionary and rule.has("forbidden_facts"):
			expected_fields.append("forbidden_facts")
		if rule is Dictionary and rule.has("repeatable"):
			expected_fields.append("repeatable")
			if not rule.repeatable is bool:
				return _failure("invalid_repeatable_scene_rule")
		if not _fields(rule, expected_fields):
			return _failure("unknown_or_missing_rule_condition")
		if not rule.npc_id is String or table.content_npc_definition(rule.npc_id).is_empty():
			return _failure("unknown_rule_npc")
		for field: String in ["requires_completed", "not_completed", "requires_facts"]:
			if not _strings(rule[field]):
				return _failure("invalid_rule_condition_list")
		for dependency: String in rule.requires_completed + rule.not_completed:
			if dependency == id or not story_session.story_exists(dependency):
				return _failure("self_or_unknown_story_dependency")
		for dependency: String in rule.requires_completed:
			if dependency in rule.not_completed:
				return _failure("contradictory_story_dependency")
		for fact: String in rule.requires_facts:
			if not _fact_id(fact):
				return _failure("invalid_rule_fact_id")
		if rule.has("forbidden_facts"):
			if not _strings(rule.forbidden_facts):
				return _failure("invalid_forbidden_fact_condition")
			for fact: String in rule.forbidden_facts:
				if not _fact_id(fact) or fact in rule.requires_facts:
					return _failure("invalid_or_contradictory_forbidden_fact")
		for field: String in ["requires_recipes", "requires_cards"]:
			if not rule[field] is Array:
				return _failure("invalid_counted_condition")
			var identity_field := "recipe_id" if field == "requires_recipes" else "card_id"
			var seen: Dictionary = {}
			for condition: Variant in rule[field]:
				if not _fields(condition, [identity_field, "count"]) or not condition[identity_field] is String or seen.has(condition[identity_field]):
					return _failure("invalid_or_duplicate_counted_condition")
				if not _integer(condition.count, 1, 50000 if field == "requires_recipes" else TableState.MAX_CARDS):
					return _failure("invalid_condition_count")
				if (field == "requires_recipes" and not recipes.has(condition.recipe_id)) or (field == "requires_cards" and table.content_card_definition(condition.card_id).is_empty()):
					return _failure("unknown_counted_condition_reference")
				seen[condition[identity_field]] = true
	var marks: Dictionary = {}
	for id: String in rules:
		if _cyclic(id, rules, marks):
			return _failure("completed_story_dependency_cycle")
	_table = table
	_session = story_session
	_rules = rules.duplicate(true)
	_recipes = recipes.duplicate(true)
	_event_definitions = event_definitions.duplicate(true)
	_operations = operations.duplicate(true)
	_service_catalog = service_catalog.duplicate(true) if service_catalog is Dictionary else null
	_market_catalog = market_catalog.duplicate(true)
	return {"ok": true, "error": ""}


# 返回全部合法候选的稳定 ID 顺序；调用方须让玩家决定，不能默认拿第一项。
# 查询不创建任务、不取得实例锁、不改变任何故事、卡牌或事务收据。
func eligible_for_npc(npc_id: String) -> Array[String]:
	var matches: Dictionary = eligible_for_npcs([npc_id])
	var result: Array[String] = []
	for id: String in matches.get(npc_id, []):
		result.append(id)
	return result


func eligible_for_npcs(npc_ids: Array[String]) -> Dictionary:
	return _eligible_for_npcs(npc_ids, false)


func preview_eligible_for_npcs(npc_ids: Array[String], virtual_cards: Dictionary = {}) -> Dictionary:
	return _eligible_for_npcs(npc_ids, true, virtual_cards)


func _eligible_for_npcs(npc_ids: Array[String], trusted_preview: bool, virtual_cards: Dictionary = {}) -> Dictionary:
	var matches: Dictionary = {}
	if _table == null or _session == null or _busy:
		return matches
	for npc_id: String in npc_ids:
		if not _table.content_npc_definition(npc_id).is_empty():
			matches[npc_id] = []
	if matches.is_empty():
		return matches
	var state := _preview_qualification_state() if trusted_preview else _qualification_state()
	if not state.ok or not _idle():
		return matches
	for id: String in _rules:
		var npc_id: String = _rules[id].npc_id
		if not matches.has(npc_id):
			continue
		var qualified_state := state
		if virtual_cards.has(npc_id):
			qualified_state = state.duplicate()
			qualified_state.cards = state.cards.duplicate()
			var virtual_id: String = virtual_cards[npc_id]
			qualified_state.cards[virtual_id] = int(qualified_state.cards.get(virtual_id, 0)) + 1
		if _requirements_met(id, qualified_state):
			matches[npc_id].append(id)
	for npc_id: String in matches:
		matches[npc_id].sort()
	return matches


func _preview_qualification_state() -> Dictionary:
	# 显示提示只读取已通过加载/交易校验的状态；实际发起剧情仍走完整校验。
	var story_state: Dictionary = _session.to_data().state
	var facts: Dictionary = {}
	for fact: String in story_state.facts:
		facts[fact] = true
	var recipes: Dictionary = {}
	for receipt: Dictionary in _table.transaction_receipts.values():
		if receipt.get("status") != "completed":
			continue
		for fact: String in receipt.get("grants_facts", []):
			facts[fact] = true
		if receipt.get("recipe_id") is String and (receipt.get("kind", "") == "" or receipt.get("kind", "") == "recipe"):
			var recipe_id: String = receipt.recipe_id
			recipes[recipe_id] = int(recipes.get(recipe_id, 0)) + 1
	var cards: Dictionary = {}
	for id: String in _table.cards:
		if _table.cards[id].zone in [&"board", &"bound"]:
			var definition_id := _table.definition_id_for_card(id)
			cards[definition_id] = int(cards.get(definition_id, 0)) + 1
	return {"ok": true, "facts": facts, "completed": story_state.completed, "recipes": recipes, "cards": cards}


# 必须由已完成 TableInteraction 的 1.5 秒组合准备的调用方发起。
# 本层只验证真实合叠与资格，不声称自己计时，也不制造准备动画或重读奖励。
func request(story_id: String, npc_instance_id: String) -> Dictionary:
	if _table == null or _session == null:
		return _failure("scheduler_not_configured")
	if _busy:
		return _failure("scheduler_is_requesting_story")
	if not _rules.has(story_id):
		return _failure("story_has_no_scheduling_rule")
	if not _idle():
		return _failure("story_session_is_busy_or_paused")
	var state := _qualification_state()
	if not state.ok:
		return state
	if not _requirements_met(story_id, state):
		return _failure("story_requirements_not_met")
	if not _table.cards.has(npc_instance_id):
		return _failure("npc_instance_missing")
	var rule: Dictionary = _rules[story_id]
	var npc: Dictionary = _table.cards[npc_instance_id]
	var definition := _table.content_npc_definition(rule.npc_id)
	if npc.zone != &"board" or npc.metadata.get("npc_id") != rule.npc_id or _table.definition_id_for_card(npc_instance_id) != definition.get("card_id"):
		return _failure("npc_instance_identity_or_zone_mismatch")
	var stack := _table.stack_for(npc_instance_id)
	if stack.is_empty():
		return _failure("npc_has_no_board_stack")
	var hero_found := false
	for card_id: String in _table.stacks[stack].cards:
		if card_id != npc_instance_id and _table.cards[card_id].zone == &"board" and _table.definition_id_for_card(card_id) == "card.hero":
			hero_found = true
	if not hero_found:
		return _failure("hero_and_npc_are_not_combined")
	_busy = true
	var started := _session.start(story_id)
	_busy = false
	return {"ok": true, "story_id": story_id, "npc_instance_id": npc_instance_id} if started.ok else _failure("session_refused_story: " + str(started.error))


func _idle() -> bool:
	var state: Dictionary = _session.to_data().state
	return not state.paused and str(state.story_id).is_empty()


func _qualification_state() -> Dictionary:
	if not _table.validate().is_empty():
		return _failure("invalid_table")
	var service_error := _service_error(_table, _session, _service_catalog, _operations, _market_catalog)
	if not service_error.is_empty():
		return _failure(service_error)
	# configure 是只读校验：核对事件目录、收据指纹和真实 completed trigger，不应用事件。
	var events := Events.new()
	var event_check := events.configure(_table, _session, _event_definitions)
	if not event_check.ok:
		return _failure("invalid_event_qualification_context: " + str(event_check.error))
	var story_state: Dictionary = _session.to_data().state
	var facts: Dictionary = {}
	for fact: String in story_state.facts:
		facts[fact] = true
	var counts: Dictionary = {}
	var produced: Dictionary = {}
	var consumed: Dictionary = {}
	for id: Variant in _table.transaction_receipts:
		var receipt: Variant = _table.transaction_receipts[id]
		if not id is String or not receipt is Dictionary:
			return _failure("invalid_transaction_ledger")
		if receipt.get("kind") == Services.KIND:
			if receipt.get("action") == "prepare":
				for fact: String in receipt.grants_facts:
					facts[fact] = true
			continue
		if receipt.get("kind") == "chapter_operation":
			var operation_error := Operations.validate_receipt(id, receipt, _operations, _table, _session, Services.workbench_policy(_service_catalog))
			if not operation_error.is_empty():
				return _failure(operation_error)
			if receipt.status == "completed":
				for fact: String in receipt.grants_facts:
					facts[fact] = true
			continue
		if receipt.get("kind") == Events.RECEIPT_KIND:
			var event_error := Events.validate_receipt(id, receipt, _event_definitions, _table)
			if not event_error.is_empty():
				return _failure(event_error)
			for fact: String in receipt.grants_facts:
				facts[fact] = true
			continue
		# 市场、法印等其他收据不授予场次事实，也不算完成配方。
		if receipt.get("kind", "") != "" or (not id.begins_with("recipe/") and not receipt.has("recipe_id")):
			continue
		var error := _recipe_receipt_error(id, receipt)
		if not error.is_empty():
			return _failure(error)
		if receipt.status != "completed":
			continue
		for card_id: String in receipt.input_instance_ids:
			if consumed.has(card_id) or _table.cards.has(card_id):
				return _failure("recipe_input_consumed_twice_or_reappeared")
			consumed[card_id] = true
		for card_id: String in receipt.output_instance_ids:
			if produced.has(card_id):
				return _failure("recipe_output_identity_duplicated")
			produced[card_id] = true
		counts[receipt.recipe_id] = int(counts.get(receipt.recipe_id, 0)) + 1
		for fact: String in receipt.grants_facts:
			facts[fact] = true
	var cards: Dictionary = {}
	for id: String in _table.cards:
		var card: Dictionary = _table.cards[id]
		var definition_id := _table.definition_id_for_card(id)
		var definition := _table.content_card_definition(definition_id)
		if definition.is_empty() or str(card.kind) != str(definition.kind) or str(card.category) != str(definition.category):
			return _failure("card_definition_identity_mismatch")
		if card.zone in [&"board", &"bound"]:
			cards[definition_id] = int(cards.get(definition_id, 0)) + 1
	return {"ok": true, "facts": facts, "completed": story_state.completed.duplicate(), "recipes": counts, "cards": cards}


static func _service_error(table: TableState, session: Story, catalog: Variant, operations: Dictionary, market: Dictionary) -> String:
	if catalog == null:
		for tx: Variant in table.transaction_receipts:
			var receipt: Variant = table.transaction_receipts[tx]
			if (tx is String and tx.begins_with("service/")) or (receipt is Dictionary and (receipt.get("kind") == Services.KIND or (receipt.get("kind") == "market_exchange" and receipt.get("version") == 2))):
				return "service_qualification_context_required"
		return ""
	if not catalog is Dictionary:
		return "invalid_service_qualification_context"
	var error := Services.validate_catalog(catalog, operations, market, table, session)
	return error if not error.is_empty() else Services.validate_table(table, session, catalog, operations, market)


func _requirements_met(id: String, state: Dictionary) -> bool:
	if id in state.completed and not _rules[id].get("repeatable", false):
		return false
	var rule: Dictionary = _rules[id]
	for story: String in rule.requires_completed:
		if story not in state.completed:
			return false
	for story: String in rule.not_completed:
		if story in state.completed:
			return false
	for fact: String in rule.requires_facts:
		if not state.facts.has(fact):
			return false
	for fact: String in rule.get("forbidden_facts", []):
		if state.facts.has(fact):
			return false
	for required: Dictionary in rule.requires_recipes:
		if int(state.recipes.get(required.recipe_id, 0)) < int(required.count):
			return false
	for required: Dictionary in rule.requires_cards:
		if int(state.cards.get(required.card_id, 0)) < int(required.count):
			return false
	return true


func _recipe_receipt_error(id: String, receipt: Dictionary) -> String:
	var parts := id.split("/")
	if parts.size() != 3 or parts[0] != "recipe" or parts[1].is_empty() or not parts[2].is_valid_int() or int(parts[2]) <= 0 or str(int(parts[2])) != parts[2]:
		return "invalid_recipe_transaction_id"
	if not receipt.get("ok") is bool or not receipt.ok or receipt.get("job_id") != id or receipt.get("transaction_id") != id or not _recipes.has(receipt.get("recipe_id")):
		return "invalid_recipe_receipt_identity"
	if receipt.get("status") == "cancelled":
		if not _fields(receipt, ["ok", "status", "job_id", "transaction_id", "recipe_id", "reason", "grants_facts"]) or not receipt.reason is String or receipt.reason.is_empty() or receipt.grants_facts != []:
			return "invalid_cancelled_recipe_receipt"
		return ""
	if not _fields(receipt, ["ok", "status", "job_id", "transaction_id", "recipe_id", "recipe_fingerprint", "source_id", "source_position", "input_instance_ids", "reusable_instance_ids", "output_instance_ids", "transformed_instance_id", "grants_facts"]) or receipt.status != "completed":
		return "invalid_completed_recipe_receipt"
	var recipe: Dictionary = _recipes[receipt.recipe_id]
	if receipt.recipe_fingerprint != Runner.canonical_digest(recipe):
		return "recipe_receipt_fingerprint_mismatch"
	var identities: Dictionary = {}
	for field: String in ["input_instance_ids", "reusable_instance_ids", "output_instance_ids"]:
		if not _strings(receipt[field]):
			return "invalid_recipe_receipt_instances"
		for card_id: String in receipt[field]:
			if not _instance_id(card_id, _table.next_card_id) or identities.has(card_id):
				return "invalid_recipe_receipt_instance_identity"
			identities[card_id] = true
	if receipt.input_instance_ids.size() != _count(recipe.inputs) or receipt.reusable_instance_ids.size() != _count(recipe.reusable) or receipt.output_instance_ids.size() != _count(recipe.outputs):
		return "recipe_receipt_count_mismatch"
	if receipt.source_id not in receipt.input_instance_ids and receipt.source_id not in receipt.reusable_instance_ids:
		return "invalid_recipe_receipt_source"
	if not _position(receipt.source_position) or not TableState.WORLD_BOUNDS.has_point(Vector2(float(receipt.source_position[0]), float(receipt.source_position[1]))):
		return "invalid_recipe_receipt_position"
	if not _strings(receipt.grants_facts) or receipt.grants_facts != recipe.get("grants_facts", []):
		return "recipe_receipt_fact_mismatch"
	for output_id: String in receipt.output_instance_ids:
		if not _table.cards.has(output_id):
			continue
		var metadata: Dictionary = _table.cards[output_id].metadata
		if metadata.get("production_transaction_id") != id or Runner.canonical_digest(metadata.get("production_source_position")) != Runner.canonical_digest(receipt.source_position):
			return "recipe_output_provenance_mismatch"
	if not receipt.transformed_instance_id is String or (recipe.action == "craft" and receipt.transformed_instance_id != "") or (recipe.action == "transform" and receipt.transformed_instance_id not in receipt.reusable_instance_ids):
		return "invalid_recipe_receipt_transform"
	return ""


static func _cyclic(id: String, rules: Dictionary, marks: Dictionary) -> bool:
	if int(marks.get(id, 0)) == 1:
		return true
	if int(marks.get(id, 0)) == 2 or not rules.has(id):
		return false
	marks[id] = 1
	for dependency: String in rules[id].requires_completed:
		if _cyclic(dependency, rules, marks):
			return true
	marks[id] = 2
	return false


static func _count(rules: Array) -> int:
	var result := 0
	for rule: Dictionary in rules:
		result += int(rule.count)
	return result


static func _fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: Variant in fields:
		if not value.has(field):
			return false
	return true


static func _strings(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not item is String or item.is_empty() or seen.has(item):
			return false
		seen[item] = true
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and float(value) >= minimum and float(value) <= maximum


static func _fact_id(value: String) -> bool:
	if not value.begins_with("fact.") or value.length() <= 5:
		return false
	for c: String in value:
		if c not in "abcdefghijklmnopqrstuvwxyz0123456789_.":
			return false
	return true


static func _instance_id(id: String, next: int) -> bool:
	if not id.begins_with("card_"):
		return false
	var suffix := id.trim_prefix("card_")
	return suffix.is_valid_int() and int(suffix) > 0 and int(suffix) < next and id == "card_%04d" % int(suffix)


static func _position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
