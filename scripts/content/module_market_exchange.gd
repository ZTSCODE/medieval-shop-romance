class_name ModuleMarketExchange
extends RefCounted

const Runner = preload("res://scripts/content/module_recipe_runner.gd")
const Operations = preload("res://scripts/content/chapter_operation_runner.gd")
const RECEIPT_KIND := "market_exchange"
const MAX_DAY := 1000000
const MAX_SOURCE_COORDINATE := 1000000.0

var _table: TableState
var _offers: Dictionary = {}
var _sources: Dictionary = {}
var _service_policy: Dictionary = {}
var _operations: Dictionary = {}


# 固定菜单只收取/产出真实卡牌，没有抽象钱包或货源卡。
# sources 为稳定来源 ID -> {modes:[buy/sell]}；来源位置由控制器实时提供。
func configure(table: TableState, offers: Dictionary, sources: Dictionary, service_policy: Dictionary = {}, operations: Dictionary = {}) -> Dictionary:
	if table == null:
		return _failure("missing_table")
	var error := validate_catalog(offers, sources, table)
	if error.is_empty():
		error = validate_service_policy(service_policy, operations, offers, table)
	if error.is_empty():
		error = _table_error(table, offers, sources, service_policy, operations)
	if not error.is_empty():
		return _failure(error)
	_table = table
	_offers = offers.duplicate(true)
	_sources = sources.duplicate(true)
	_service_policy = service_policy.duplicate(true)
	_operations = operations.duplicate(true)
	return {"ok": true, "error": "", "catalog_fingerprint": catalog_fingerprint(_offers, _sources)}


# 只读报价供固定菜单使用；同执行共享额度与首单加价，不序列化整目录或写激活记录。
func terms(offer_id: String, day: int) -> Dictionary:
	if _table == null or not _offers.has(offer_id) or not _integer(day, 1, MAX_DAY):
		return _failure("invalid_market_quote_request")
	var activated := _table.transaction_receipts.has("service/context")
	if activated != not _service_policy.is_empty():
		return _failure("market_quote_service_context_unavailable")
	var count := 0
	for value: Variant in _table.transaction_receipts.values():
		if not value is Dictionary:
			return _failure("invalid_market_quote_ledger")
		if value.get("kind") not in [RECEIPT_KIND, "chapter_service"]:
			continue
		if not _integer(value.get("day"), 1, MAX_DAY) or int(value.day) > day:
			return _failure("invalid_market_quote_day")
		if value.get("kind") == RECEIPT_KIND and value.get("offer_id") == offer_id and int(value.day) == day:
			count += 1
	var offer: Dictionary = _offers[offer_id]
	var benefits := _benefits(_table, offer_id, day, _service_policy)
	var remaining := -1
	if benefits.quota_limit > 0:
		remaining = maxi(0, int(benefits.quota_limit) - int(benefits.quota_index) + 1)
	elif int(offer.limit_per_day) > 0:
		remaining = maxi(0, int(offer.limit_per_day) - count)
	var outputs: Array = offer.outputs.duplicate(true)
	if benefits.premium_coins > 0:
		outputs[0].count = int(outputs[0].count) + int(benefits.premium_coins)
	return {"ok": true, "inputs": offer.inputs.duplicate(true), "outputs": outputs,
		"remaining": remaining, "premium_coins": int(benefits.premium_coins)}


# day 必须是有限的正整数；使用 Variant 是为了拒绝 NaN/小数而不是让引擎静默截断。
# 本层验证来源许可、坐标范围和时间不倒退；不自行证明屏幕投影或实际游戏时钟。
func execute(offer_id: String, input_instance_ids: Array[String], source_id: String, source_position: Vector2, day: Variant, facts: Array[String], transaction_id: String) -> Dictionary:
	if _table == null:
		return _failure("market_not_configured")
	var error := validate_catalog(_offers, _sources, _table)
	if error.is_empty():
		error = _table_error(_table, _offers, _sources, _service_policy, _operations)
	if not error.is_empty():
		return _failure(error)
	if not _service_policy.is_empty() and not _table.transaction_receipts.has("service/context"):
		return _failure("market_service_policy_not_activated")
	if not _offers.has(offer_id):
		return _failure("unknown_offer")
	var offer: Dictionary = _offers[offer_id]
	if not _sources.has(source_id) or offer.mode not in _sources[source_id].modes:
		return _failure("unknown_or_disallowed_source")
	if not _position([source_position.x, source_position.y]):
		return _failure("invalid_source_position")
	if not _integer(day, 1, MAX_DAY):
		return _failure("invalid_day")
	if not _strings(input_instance_ids, false) or not _strings(facts) or not _transaction_id(transaction_id):
		return _failure("invalid_request_identity")
	var sorted_ids := input_instance_ids.duplicate()
	sorted_ids.sort()
	var sorted_facts := facts.duplicate()
	sorted_facts.sort()
	var request := {"offer_id": offer_id, "input_instance_ids": sorted_ids, "source_id": source_id,
		"source_position": [source_position.x, source_position.y], "day": int(day), "facts": sorted_facts}
	if _table.transaction_receipts.has(transaction_id):
		var prior: Variant = _table.transaction_receipts[transaction_id]
		if not prior is Dictionary or prior.get("kind") != RECEIPT_KIND or Runner.canonical_digest(prior.get("request")) != Runner.canonical_digest(request):
			return _failure("transaction_request_conflict")
		var replay: Dictionary = prior.duplicate(true)
		replay["ok"] = true
		replay["already_applied"] = true
		return replay
	var today_count := 0
	for receipt: Dictionary in _table.transaction_receipts.values():
		if receipt.get("kind") == "chapter_service" and int(receipt.get("day", 0)) > int(day):
			return _failure("market_day_cannot_regress")
		if receipt.get("kind") != RECEIPT_KIND:
			continue
		if int(receipt.day) > int(day):
			return _failure("market_day_cannot_regress")
		if int(receipt.day) == int(day) and receipt.offer_id == offer_id:
			today_count += 1
	var benefits := _benefits(_table, offer_id, int(day), _service_policy)
	if benefits.quota_limit > 0 and benefits.quota_index > benefits.quota_limit:
		return _failure("shared_daily_order_limit_reached")
	if benefits.quota_limit == 0 and int(offer.limit_per_day) > 0 and today_count >= int(offer.limit_per_day):
		return _failure("daily_offer_limit_reached")
	for fact: String in offer.requires_facts:
		if fact not in facts:
			return _failure("missing_required_fact")
	var actual: Dictionary = {}
	for id: String in input_instance_ids:
		if not _table.cards.has(id):
			return _failure("unknown_input_instance")
		var card: Dictionary = _table.cards[id]
		var definition_id := _table.definition_id_for_card(id)
		var definition := _table.content_card_definition(definition_id)
		if not _ordinary_definition(definition_id, _table) or card.kind != StringName(definition.kind) or card.category != StringName(definition.category) or card.zone != &"board":
			return _failure("input_is_not_ordinary_board_goods")
		for protected_field: String in ["npc_id", "order_id", "customer_id", "bound_to", "bound_sigil"]:
			if card.metadata.has(protected_field):
				return _failure("input_has_protected_identity")
		if _table.sigil_instance_locked(id):
			return _failure("input_instance_locked")
		actual[definition_id] = int(actual.get(definition_id, 0)) + 1
	if actual != _counts(offer.inputs):
		return _failure("input_multiset_mismatch")
	var effective_outputs: Array = offer.outputs.duplicate(true)
	if benefits.premium_coins > 0:
		effective_outputs[0].count = int(effective_outputs[0].count) + int(benefits.premium_coins)
	var output_count := _total(effective_outputs)
	if _table.card_count() - input_instance_ids.size() + output_count > TableState.MAX_CARDS:
		return _failure("capacity_exceeded")
	var candidate := _table.fork_empty()
	candidate.restore(_table.snapshot())
	for id: String in input_instance_ids:
		if not candidate.remove_card(id):
			return _failure("candidate_input_removal_failed")
	var outputs: Array[String] = []
	for output: Dictionary in effective_outputs:
		var remaining := int(output.count)
		while remaining > 0:
			var amount := mini(remaining, TableState.MAX_STACK)
			var stack := candidate.create_defined(output.card_id, source_position, amount)
			if stack.is_empty():
				return _failure("candidate_output_creation_failed")
			for id: String in candidate.stacks[stack].cards:
				outputs.append(id)
				candidate.cards[id].metadata.production_transaction_id = transaction_id
				candidate.cards[id].metadata.production_source_position = request.source_position.duplicate()
			remaining -= amount
	var receipt := {"kind": RECEIPT_KIND, "version": 1, "status": "completed", "offer_id": offer_id,
		"offer_fingerprint": Runner.canonical_digest(offer), "transaction_id": transaction_id, "day": int(day),
		"input_instance_ids": sorted_ids, "output_instance_ids": outputs,
		"source_position": request.source_position.duplicate(), "request": request}
	if not _service_policy.is_empty():
		receipt.version = 2
		receipt["service_policy_fingerprint"] = Runner.canonical_digest(_service_policy)
		for key: String in benefits:
			receipt[key] = benefits[key]
	candidate.transaction_receipts[transaction_id] = receipt
	error = _table_error(candidate, _offers, _sources, _service_policy, _operations)
	if not error.is_empty():
		return _failure(error)
	# 无 await/对外信号，单次替换提交整笔交易；仍在提交前复核实时实例锁。
	for id: String in input_instance_ids:
		if _table.sigil_instance_locked(id):
			return _failure("input_instance_locked")
	_table.restore(candidate.snapshot())
	var result := receipt.duplicate(true)
	result["ok"] = true
	result["already_applied"] = false
	return result


static func catalog_fingerprint(offers: Dictionary, sources: Dictionary) -> String:
	return Runner.canonical_digest({"offers": offers, "sources": sources})


static func validate_catalog(offers: Dictionary, sources: Dictionary, context_table: TableState = null) -> String:
	if sources.is_empty() or sources.size() > 10000 or offers.is_empty() or offers.size() > 1000:
		return "invalid_market_catalog_size"
	for id: Variant in sources:
		var source: Variant = sources[id]
		if not _identifier(id) or not _fields(source, ["modes"]) or not _strings(source.modes, false):
			return "invalid_market_source"
		for mode: String in source.modes:
			if mode not in ["buy", "sell"]:
				return "invalid_market_source_mode"
	for id: Variant in offers:
		var offer: Variant = offers[id]
		if not _identifier(id) or not _fields(offer, ["id", "mode", "inputs", "outputs", "requires_facts", "limit_per_day"]) or offer.id != id:
			return "invalid_offer_fields"
		if offer.mode not in ["buy", "sell"] or not _integer(offer.limit_per_day, 0, MAX_DAY) or not _strings(offer.requires_facts):
			return "invalid_offer_rules"
		for field: String in ["inputs", "outputs"]:
			var rules: Variant = offer[field]
			if not rules is Array or rules.is_empty():
				return "missing_offer_goods"
			var seen: Dictionary = {}
			var total := 0
			for rule: Variant in rules:
				if not _fields(rule, ["card_id", "count"]) or not rule.card_id is String or not _integer(rule.count, 1, TableState.MAX_CARDS) or seen.has(rule.card_id):
					return "invalid_offer_quantity"
				if not _ordinary_definition(rule.card_id, context_table):
					return "offer_contains_unavailable_or_protected_goods"
				var coin_side: bool = (offer.mode == "buy" and field == "inputs") or (offer.mode == "sell" and field == "outputs")
				if (rule.card_id == "card.coin") != coin_side:
					return "offer_must_exchange_physical_coins_for_goods"
				seen[rule.card_id] = true
				total += int(rule.count)
			if total > TableState.MAX_CARDS:
				return "offer_quantity_exceeds_capacity"
	return ""


# offers 与 sources 必须显式提供；旧价格或已遗失的来源目录不自动降级接受。
static func validate_receipt(transaction_id: String, value: Variant, offers: Dictionary, sources: Dictionary = {}, context_table: TableState = null, service_policy: Dictionary = {}, operations: Dictionary = {}) -> String:
	var catalog_error := validate_catalog(offers, sources, context_table)
	if not catalog_error.is_empty():
		return catalog_error
	if context_table != null:
		catalog_error = _activation_error(context_table, offers, sources, service_policy, operations)
		if not catalog_error.is_empty():
			return catalog_error
	var fields: Array = ["kind", "version", "status", "offer_id", "offer_fingerprint", "transaction_id", "day", "input_instance_ids", "output_instance_ids", "source_position", "request"]
	if value is Dictionary and value.get("version") == 2:
		fields.append_array(["service_policy_fingerprint", "quota_index", "quota_limit", "premium_coins", "unlock_transaction_id"])
	if not _fields(value, fields):
		return "invalid_market_receipt_fields"
	var receipt: Dictionary = value
	if not _transaction_id(transaction_id) or receipt.transaction_id != transaction_id or receipt.kind != RECEIPT_KIND or not _integer(receipt.version, 1, 2) or receipt.status != "completed":
		return "invalid_market_receipt_identity"
	if not receipt.offer_id is String or not offers.has(receipt.offer_id):
		return "unknown_market_receipt_offer"
	var offer: Dictionary = offers[receipt.offer_id]
	if receipt.offer_fingerprint != Runner.canonical_digest(offer):
		return "market_offer_fingerprint_mismatch"
	if not _integer(receipt.day, 1, MAX_DAY) or not _position(receipt.source_position) or not _strings(receipt.input_instance_ids, false) or not _strings(receipt.output_instance_ids, false):
		return "invalid_market_receipt_values"
	var policy_error := _receipt_policy_error(receipt, offers, service_policy, operations, context_table)
	if not policy_error.is_empty():
		return policy_error
	if receipt.input_instance_ids.size() != _total(offer.inputs) or receipt.output_instance_ids.size() != _total(offer.outputs) + int(receipt.get("premium_coins", 0)):
		return "market_receipt_quantity_mismatch"
	var ids: Dictionary = {}
	for id: Variant in receipt.input_instance_ids + receipt.output_instance_ids:
		if not _instance_id(id) or ids.has(id):
			return "invalid_market_receipt_instances"
		ids[id] = true
	if not _fields(receipt.request, ["offer_id", "input_instance_ids", "source_id", "source_position", "day", "facts"]):
		return "invalid_market_request_fields"
	var request: Dictionary = receipt.request
	if not _integer(request.day, 1, MAX_DAY) or not _position(request.source_position):
		return "invalid_market_request_values"
	if not request.source_id is String or not sources.has(request.source_id) or offer.mode not in sources[request.source_id].modes:
		return "unknown_market_receipt_source"
	if request.offer_id != receipt.offer_id or request.day != receipt.day or request.input_instance_ids != receipt.input_instance_ids or Runner.canonical_digest(request.source_position) != Runner.canonical_digest(receipt.source_position) or not _strings(request.facts):
		return "market_receipt_request_mismatch"
	for fact: String in offer.requires_facts:
		if fact not in request.facts:
			return "market_receipt_missing_fact"
	return ""


static func validate_table(table: TableState, offers: Dictionary, sources: Dictionary, service_policy: Dictionary = {}, operations: Dictionary = {}) -> String:
	var catalog_error := validate_catalog(offers, sources, table)
	if catalog_error.is_empty():
		catalog_error = validate_service_policy(service_policy, operations, offers, table)
	return catalog_error if not catalog_error.is_empty() else _table_error(table, offers, sources, service_policy, operations)


static func _table_error(table: TableState, offers: Dictionary, sources: Dictionary, service_policy: Dictionary = {}, operations: Dictionary = {}) -> String:
	var error := table.validate()
	if not error.is_empty():
		return "invalid_market_table: " + error
	error = _activation_error(table, offers, sources, service_policy, operations)
	if not error.is_empty():
		return error
	var quotas: Dictionary = {}
	var shared_indices: Dictionary = {}
	var baseline_counts: Dictionary = {}
	var consumed: Dictionary = {}
	var produced: Dictionary = {}
	for tx: Variant in table.transaction_receipts:
		var receipt: Variant = table.transaction_receipts[tx]
		if not tx is String or not receipt is Dictionary:
			return "invalid_market_ledger_key"
		if not tx.begins_with("market/") and not (receipt is Dictionary and receipt.get("kind") == RECEIPT_KIND):
			continue
		error = validate_receipt(tx, receipt, offers, sources, table, service_policy, operations)
		if not error.is_empty():
			return error
		var quota_key := str(int(receipt.day)) + ":" + str(receipt.offer_id)
		quotas[quota_key] = int(quotas.get(quota_key, 0)) + 1
		var grouped: bool = not service_policy.is_empty() and receipt.offer_id in service_policy.rule.offer_ids
		var quota := 0 if grouped else int(offers[receipt.offer_id].limit_per_day)
		if quota > 0 and int(quotas[quota_key]) > quota:
			return "market_ledger_exceeds_daily_limit"
		if grouped:
			var day_key := str(int(receipt.day))
			if receipt.version == 1:
				baseline_counts[day_key] = int(baseline_counts.get(day_key, 0)) + 1
			else:
				if not shared_indices.has(day_key):
					shared_indices[day_key] = []
				if receipt.quota_index in shared_indices[day_key]:
					return "shared_order_index_reused"
				shared_indices[day_key].append(int(receipt.quota_index))
		for id: String in receipt.input_instance_ids:
			if consumed.has(id) or table.cards.has(id) or int(id.trim_prefix("card_")) >= table.next_card_id:
				return "market_input_already_consumed_or_reappeared"
			consumed[id] = tx
		for id: String in receipt.output_instance_ids:
			if produced.has(id) or int(id.trim_prefix("card_")) >= table.next_card_id:
				return "market_output_identity_reused"
			produced[id] = tx
	for day_key: String in shared_indices:
		var indices: Array = shared_indices[day_key]
		indices.sort()
		for index: int in range(indices.size()):
			if indices[index] != int(baseline_counts.get(day_key, 0)) + index + 1:
				return "shared_order_index_gap"
	return ""


# 单独使用市场组件也核对固定上下文；不能拿改价目录或删掉政策的旧执行器绕过。
static func _activation_error(table: TableState, offers: Dictionary, sources: Dictionary, policy: Dictionary, operations: Dictionary) -> String:
	if not table.transaction_receipts.has("service/context"):
		return ""
	var activation: Variant = table.transaction_receipts["service/context"]
	if policy.is_empty() or not _fields(activation, ["kind", "version", "status", "action", "transaction_id", "day", "context", "market_baseline"]) or activation.kind != "chapter_service" or activation.action != "activate_context" or activation.status != "completed" or activation.transaction_id != "service/context" or not _integer(activation.version, 1, 1) or not _integer(activation.day, 1, MAX_DAY):
		return "active_service_policy_context_missing_or_mismatched"
	if not _fields(activation.context, ["version", "catalog_fingerprint", "operation_catalog_fingerprint", "market_catalog_fingerprint"]) or not _integer(activation.context.version, 1, 1) or not activation.market_baseline is Dictionary:
		return "invalid_market_service_activation"
	if activation.context.catalog_fingerprint != policy.get("catalog_fingerprint") or activation.context.operation_catalog_fingerprint != Runner.canonical_digest(operations) or activation.context.market_catalog_fingerprint != Runner.canonical_digest({"offers": offers, "sources": sources}):
		return "market_service_activation_catalog_mismatch"
	for id: Variant in activation.market_baseline:
		if not id is String or not table.transaction_receipts.has(id) or not table.transaction_receipts[id] is Dictionary or table.transaction_receipts[id].get("kind") != RECEIPT_KIND or Runner.canonical_digest(table.transaction_receipts[id]) != activation.market_baseline[id]:
			return "market_service_activation_baseline_mismatch"
	return ""


# 可选政策只约束明确列出的成品报价；材料回收与购买保持原有实体卡交易。
static func validate_service_policy(policy: Dictionary, operations: Dictionary, offers: Dictionary, table: TableState = null) -> String:
	if policy.is_empty():
		return ""
	var fields := ["catalog_fingerprint", "rule"]
	if policy.has("workbench_policy"):
		fields.append("workbench_policy")
	if not _fields(policy, fields) or not policy.catalog_fingerprint is String or policy.catalog_fingerprint.length() != 64:
		return "invalid_market_service_policy"
	var workbench_error := Operations.validate_workbench_policy(policy.get("workbench_policy"), operations)
	if not workbench_error.is_empty():
		return workbench_error
	var rule: Variant = policy.rule
	if not _fields(rule, ["id", "name_key", "description_key", "unlock_operation_id", "offer_ids", "ordinary_daily_limit", "upgraded_daily_limit", "first_order_bonus"]) or not _identifier(rule.id) or not rule.name_key is String or not rule.description_key is String or not rule.unlock_operation_id is String or not operations.has(rule.unlock_operation_id):
		return "invalid_market_service_rule"
	if not _strings(rule.offer_ids, false) or not _integer(rule.ordinary_daily_limit, 1, 100) or not _integer(rule.upgraded_daily_limit, int(rule.ordinary_daily_limit), 100) or not _integer(rule.first_order_bonus, 0, 100):
		return "invalid_market_service_limits"
	for offer_id: String in rule.offer_ids:
		if not offers.has(offer_id) or offers[offer_id].mode != "sell" or offers[offer_id].outputs.size() != 1 or offers[offer_id].outputs[0].card_id != "card.coin":
			return "service_policy_requires_real_product_sale"
		for item: Dictionary in offers[offer_id].inputs:
			if not _ordinary_definition(item.card_id, table):
				return "service_policy_product_not_sellable"
	return ""


static func _benefits(table: TableState, offer_id: String, day: int, policy: Dictionary) -> Dictionary:
	var result := {"quota_index": 0, "quota_limit": 0, "premium_coins": 0, "unlock_transaction_id": ""}
	if policy.is_empty() or offer_id not in policy.rule.offer_ids:
		return result
	result.quota_index = 1
	result.quota_limit = int(policy.rule.ordinary_daily_limit)
	for tx: String in table.transaction_receipts:
		var receipt: Dictionary = table.transaction_receipts[tx]
		if receipt.get("kind") == RECEIPT_KIND and int(receipt.day) == day and receipt.offer_id in policy.rule.offer_ids:
			result.quota_index += 1
		if receipt.get("kind") == "chapter_operation" and receipt.get("operation_id") == policy.rule.unlock_operation_id and receipt.get("status") == "completed":
			result.unlock_transaction_id = tx
	if not result.unlock_transaction_id.is_empty():
		result.quota_limit = int(policy.rule.upgraded_daily_limit)
		if result.quota_index == 1:
			result.premium_coins = int(policy.rule.first_order_bonus)
	return result


static func _receipt_policy_error(receipt: Dictionary, offers: Dictionary, policy: Dictionary, operations: Dictionary, table: TableState) -> String:
	var error := validate_service_policy(policy, operations, offers, table)
	if not error.is_empty():
		return error
	var activation: Dictionary = table.transaction_receipts.get("service/context", {}) if table != null else {}
	if receipt.version == 1:
		if not activation.is_empty() and activation.get("market_baseline", {}).get(receipt.transaction_id) != Runner.canonical_digest(receipt):
			return "legacy_market_receipt_after_service_activation"
		return ""
	if policy.is_empty() or table == null or activation.is_empty() or receipt.service_policy_fingerprint != Runner.canonical_digest(policy):
		return "market_receipt_service_context_mismatch"
	if int(receipt.day) < int(activation.get("day", 0)) or not _integer(receipt.quota_index, 0, 100) or not _integer(receipt.quota_limit, 0, 100) or not _integer(receipt.premium_coins, 0, 100) or not receipt.unlock_transaction_id is String:
		return "invalid_market_service_receipt_values"
	if receipt.offer_id not in policy.rule.offer_ids:
		return "" if receipt.quota_index == 0 and receipt.quota_limit == 0 and receipt.premium_coins == 0 and receipt.unlock_transaction_id.is_empty() else "ungrouped_offer_cannot_claim_service"
	var quota := int(policy.rule.ordinary_daily_limit)
	var premium := 0
	if not receipt.unlock_transaction_id.is_empty():
		if not table.transaction_receipts.has(receipt.unlock_transaction_id):
			return "market_service_unlock_missing"
		var unlock: Dictionary = table.transaction_receipts[receipt.unlock_transaction_id]
		if unlock.get("kind") != "chapter_operation" or unlock.get("status") != "completed" or unlock.get("operation_id") != policy.rule.unlock_operation_id:
			return "market_service_unlock_mismatch"
		error = Operations.validate_receipt(receipt.unlock_transaction_id, unlock, operations, table, null, policy.get("workbench_policy"))
		if not error.is_empty():
			return error
		quota = int(policy.rule.upgraded_daily_limit)
		if receipt.quota_index == 1:
			premium = int(policy.rule.first_order_bonus)
	if receipt.quota_index < 1 or receipt.quota_index > quota or receipt.quota_limit != quota or receipt.premium_coins != premium:
		return "market_service_quota_or_premium_mismatch"
	return ""


static func _ordinary_definition(id: String, context_table: TableState = null) -> bool:
	var definition := ContentCatalog.card_definition(id) if context_table == null else context_table.content_card_definition(id)
	if definition.is_empty() or definition.get("protected", false) or definition.get("unique", false) or id in ["card.hero", "card.messenger"]:
		return false
	for tag: String in definition.get("tags", []):
		if tag in ["sigil", "person", "npc", "quest", "owned", "facility", "place"]:
			return false
	return id == "card.coin" or bool(definition.get("sellable", id == "card.goods"))


static func _counts(rules: Array) -> Dictionary:
	var result: Dictionary = {}
	for rule: Dictionary in rules:
		result[rule.card_id] = int(rule.count)
	return result


static func _total(rules: Array) -> int:
	var total := 0
	for rule: Dictionary in rules:
		total += int(rule.count)
	return total


static func _fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: Variant in fields:
		if not value.has(field):
			return false
	return true


static func _strings(value: Variant, allow_empty: bool = true) -> bool:
	if not value is Array or (not allow_empty and value.is_empty()):
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not item is String or item.is_empty() or seen.has(item):
			return false
		seen[item] = true
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and float(value) >= minimum and float(value) <= maximum


static func _position(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for number: Variant in value:
		if not (number is float or number is int) or not is_finite(float(number)) or absf(float(number)) > MAX_SOURCE_COORDINATE:
			return false
	return true


static func _identifier(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 200:
		return false
	for c: String in value:
		if c not in "abcdefghijklmnopqrstuvwxyz0123456789_.":
			return false
	return true


static func _transaction_id(value: Variant) -> bool:
	return value is String and value.begins_with("market/") and _identifier(value.trim_prefix("market/"))


static func _instance_id(value: Variant) -> bool:
	if not value is String or not value.begins_with("card_"):
		return false
	var tail: String = value.trim_prefix("card_")
	return tail.is_valid_int() and int(tail) > 0 and value == "card_%04d" % int(tail)


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
