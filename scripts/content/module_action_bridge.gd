class_name ModuleActionBridge
extends RefCounted

const Runner = preload("res://scripts/content/module_recipe_runner.gd")
const Story = preload("res://scripts/content/module_story_session.gd")
const Checkpoint = preload("res://scripts/content/module_checkpoint.gd")
const Operations = preload("res://scripts/content/chapter_operation_runner.gd")
const Services = preload("res://scripts/content/chapter_service_effects.gd")
const SCHEMA_VERSION := 1

var _table: TableState
var _session: Story
var _bindings: Dictionary = {}
var _recipes: Dictionary = {}
var _market_catalog: Dictionary = {}
var _event_definitions: Variant = null
var _event_catalog_fingerprint := ""
var _operations: Variant = null
var _service_catalog: Variant = null
var _customer_catalog: Variant = null
var _configuration_digest := ""
var _arm: Dictionary = {}
var _settled: Dictionary = {}
var _busy := false


# 每个绑定声明 recipe_id 或 operation_id 中的一种；只核对真实完成证明，不代办工作。
# operation 的重要参与对象在 arm 时记录实例 ID，外观相同的替代品不能交差。
func configure(table: TableState, session: Story, bindings: Dictionary, recipes: Dictionary, market_catalog: Dictionary = {}, event_definitions: Variant = null, operations: Variant = null, service_catalog: Variant = null, customer_catalog: Variant = null) -> Dictionary:
	if _busy or not _arm.is_empty() or not _settled.is_empty():
		return _failure("bridge_progress_prevents_reconfiguration")
	if table == null or session == null or session.to_data().catalog_fingerprint.is_empty():
		return _failure("missing_or_unconfigured_participant")
	var validator := Runner.new()
	var checked := validator.configure(table.fork_empty(), recipes)
	if not checked.ok:
		return _failure("invalid_recipe_context")
	if not table.validate().is_empty():
		return _failure("invalid_table")
	var event_error := Checkpoint.validate_event_context(table, session, event_definitions)
	if not event_error.is_empty():
		return _failure(event_error)
	var operation_error := Checkpoint.validate_operation_context(table, session, operations, Services.workbench_policy(service_catalog))
	if not operation_error.is_empty():
		return _failure(operation_error)
	var service_error := Checkpoint.validate_service_context(table, session, service_catalog, operations, market_catalog)
	if not service_error.is_empty():
		return _failure(service_error)
	if not market_catalog.is_empty():
		if not _fields(market_catalog, ["offers", "sources"]) or not market_catalog.offers is Dictionary or not market_catalog.sources is Dictionary:
			return _failure("invalid_market_catalog_context")
		var market_script: Script = load("res://scripts/content/module_market_exchange.gd")
		var policy := Services.market_policy(service_catalog) if service_catalog is Dictionary else {}
		var market_error: String = market_script.validate_table(table, market_catalog.offers, market_catalog.sources, policy, operations if operations is Dictionary else {})
		if not market_error.is_empty():
			return _failure(market_error)
	var candidate := bindings.duplicate(true)
	for action: Variant in candidate:
		var binding: Variant = candidate[action]
		var proof_field := _proof_field(binding)
		if not action is String or not _fields(binding, ["story_id", "node_id", proof_field]):
			return _failure("invalid_action_binding_fields")
		for field: String in ["story_id", "node_id", proof_field]:
			if not binding[field] is String or str(binding[field]).is_empty():
				return _failure("invalid_action_binding_identity")
		if not session.action_binding_exists(binding.story_id, binding.node_id, action):
			return _failure("action_binding_not_in_story_catalog")
		if proof_field == "recipe_id" and not recipes.has(binding.recipe_id):
			return _failure("action_binding_recipe_unavailable")
		if proof_field == "operation_id" and (not operations is Dictionary or not operations.has(binding.operation_id)):
			return _failure("action_binding_operation_unavailable")
	_table = table
	_session = session
	_bindings = candidate
	_recipes = recipes.duplicate(true)
	_market_catalog = market_catalog.duplicate(true)
	_event_definitions = event_definitions.duplicate(true) if event_definitions is Dictionary else null
	_event_catalog_fingerprint = Runner.canonical_digest(_event_definitions) if _event_definitions != null else ""
	_operations = operations.duplicate(true) if operations is Dictionary else null
	_service_catalog = service_catalog.duplicate(true) if service_catalog is Dictionary else null
	_customer_catalog = customer_catalog.duplicate(true) if customer_catalog is Dictionary else null
	var configuration := {"bindings": _bindings, "recipes": _recipes,
		"story_catalog": session.to_data().catalog_fingerprint, "market_catalog": _market_catalog}
	if _event_definitions != null:
		configuration["event_catalog_fingerprint"] = _event_catalog_fingerprint
	if _operations != null:
		configuration["operation_catalog_fingerprint"] = Runner.canonical_digest(_operations)
	if _service_catalog != null:
		configuration["service_context"] = Services.context_for(_service_catalog, _operations, _market_catalog)
	if _customer_catalog != null:
		configuration["customer_catalog_fingerprint"] = Runner.canonical_digest(_customer_catalog)
	_configuration_digest = Runner.canonical_digest(configuration)
	return {"ok": true, "error": ""}


# 必须在进入 action 后、实际工作完成前调用；重复 arm 不重置收据基线。
# 未在配方完成前 arm 的行动须重新完成一次工作，不能追认既有收据。
func arm_current_action() -> Dictionary:
	var error := _ready_error()
	if not error.is_empty():
		return _failure(error)
	if _session.to_data().state.paused:
		return _failure("story_is_paused")
	error = _history_error(_settled)
	if not error.is_empty():
		return _failure(error)
	var context := _current_binding()
	if not context.ok:
		return context
	var progress := _progress_digest()
	if not _arm.is_empty() and _arm.entry_story_digest == progress:
		error = _arm_error(_arm)
		return {"ok": true, "already_armed": true} if error.is_empty() else _failure(error)
	var proof_field := _proof_field(context)
	var arm := {"story_id": context.story_id, "node_id": context.node_id, "action_id": context.action_id,
		proof_field: context[proof_field], "entry_story_digest": progress, "prior_receipts": _receipt_digests()}
	if proof_field == "operation_id":
		var targets := _operation_targets(context.operation_id)
		if not targets.ok:
			return targets
		arm["target_instances"] = targets.targets
	_arm = arm
	return {"ok": true, "already_armed": false}


# 绑定给剧情 action 的一次性操作，必须在相应 action 已 arm 后才向普通操作菜单开放。
func can_execute_operation(operation_id: String, instance_ids: Array[String] = []) -> bool:
	if not _operations is Dictionary or not _operations.has(operation_id):
		return false
	var bound := false
	for binding: Dictionary in _bindings.values():
		if binding.get("operation_id") == operation_id:
			bound = true
	if not bound:
		return true
	if not _ready_error().is_empty() or _session.to_data().state.paused or _arm.get("operation_id") != operation_id or not _arm_error(_arm).is_empty():
		return false
	if not instance_ids.is_empty():
		for id: String in _arm.target_instances.values():
			if id not in instance_ids:
				return false
	return true


# 先完整校验，再只调用一次 session.complete_action。失败不消费收据、不改剧情/arm。
# table 为事务来源；bridge 不能接受调用方自行拼出的 receipt。
func submit(transaction_id: String) -> Dictionary:
	var error := _ready_error()
	if not error.is_empty():
		return _failure(error)
	if _session.to_data().state.paused:
		return _failure("story_is_paused")
	error = _history_error(_settled)
	if not error.is_empty():
		return _failure(error)
	error = _arm_error(_arm)
	if not error.is_empty():
		return _failure(error)
	if _session.to_data().state.transactions.has(transaction_id):
		return _failure("transaction_already_consumed")
	if _arm.prior_receipts.has(transaction_id):
		return _failure("transaction_predates_action_arm")
	var proof_field := _proof_field(_arm)
	error = _receipt_error(transaction_id, proof_field, str(_arm[proof_field]), _arm.get("target_instances", {}))
	if not error.is_empty():
		return _failure(error)
	var proof := {"story_id": _arm.story_id, "node_id": _arm.node_id, "action_id": _arm.action_id,
		proof_field: _arm[proof_field], "entry_story_digest": _arm.entry_story_digest,
		"prior_receipts_digest": Runner.canonical_digest(_arm.prior_receipts),
		"receipt_digest": Runner.canonical_digest(_table.transaction_receipts[transaction_id])}
	if proof_field == "operation_id":
		proof["target_instances"] = _arm.target_instances.duplicate(true)
	_busy = true
	var completed := _session.complete_action(str(_arm.action_id), transaction_id)
	if completed.ok:
		_settled[transaction_id] = proof
		_arm = {}
	_busy = false
	return {"ok": true, "transaction_id": transaction_id} if completed.ok else _failure("session_refused_action: " + str(completed.error))


func is_bound_to(table: TableState, session: Story) -> bool:
	return _table == table and _session == session


func validate() -> Dictionary:
	var error := _ready_error()
	if error.is_empty():
		error = _history_error(_settled)
	if error.is_empty() and not _arm.is_empty():
		error = _arm_error(_arm)
	return {"ok": true, "error": ""} if error.is_empty() else _failure(error)


# 调用方必须与同一时刻的 table/session/runner 一起保存；不能只保存这个对象。
func to_data() -> Dictionary:
	var result := validate()
	if not result.ok:
		return result
	return to_data_fast()


func to_data_fast() -> Dictionary:
	var data := {"schema_version": SCHEMA_VERSION, "configuration_digest": _configuration_digest,
		"table_digest": _table_digest(), "story_digest": Runner.canonical_digest(_session.to_data()),
		"arm": _arm.duplicate(true), "settled": _settled.duplicate(true)}
	if _event_definitions != null:
		data["event_catalog_fingerprint"] = _event_catalog_fingerprint
	return data


# 恢复至已校验的联合候选对象；完整核对后才替换本 bridge，失败保留原状态。
func restore(data: Variant) -> Dictionary:
	var error := _ready_error()
	if not error.is_empty():
		return _failure(error)
	var fields := ["schema_version", "configuration_digest", "table_digest", "story_digest", "arm", "settled"]
	if _event_definitions != null:
		fields.append("event_catalog_fingerprint")
	if not _fields(data, fields):
		return _failure("invalid_bridge_checkpoint_fields")
	if _event_definitions != null and (not data.event_catalog_fingerprint is String or data.event_catalog_fingerprint != _event_catalog_fingerprint):
		return _failure("bridge_event_catalog_mismatch")
	if not (data.schema_version is int or data.schema_version is float) or data.schema_version != SCHEMA_VERSION or data.configuration_digest != _configuration_digest:
		return _failure("bridge_configuration_mismatch")
	if data.table_digest != _table_digest() or data.story_digest != Runner.canonical_digest(_session.to_data()):
		return _failure("bridge_joint_checkpoint_mismatch")
	if not data.arm is Dictionary or not data.settled is Dictionary:
		return _failure("invalid_bridge_checkpoint_collections")
	error = _history_error(data.settled)
	if error.is_empty() and not data.arm.is_empty():
		error = _arm_error(data.arm)
	if not error.is_empty():
		return _failure(error)
	_arm = data.arm.duplicate(true)
	_settled = data.settled.duplicate(true)
	return {"ok": true, "error": ""}


func _ready_error() -> String:
	if _busy:
		return "bridge_is_committing"
	if _table == null or _session == null:
		return "bridge_not_configured"
	if not _table.validate().is_empty():
		return "invalid_table"
	var operation_error := Checkpoint.validate_operation_context(_table, _session, _operations, Services.workbench_policy(_service_catalog))
	if not operation_error.is_empty():
		return operation_error
	var service_error := Checkpoint.validate_service_context(_table, _session, _service_catalog, _operations, _market_catalog)
	if not service_error.is_empty():
		return service_error
	return Checkpoint.validate_event_context(_table, _session, _event_definitions)


func _current_binding() -> Dictionary:
	var node := _session.current_node()
	if node.is_empty() or node.type != "action" or node.replaying:
		return _failure("no_original_action_waiting")
	if not _bindings.has(node.action_id):
		return _failure("action_is_not_implemented_by_recipe_bridge")
	var binding: Dictionary = _bindings[node.action_id]
	if node.story_id != binding.story_id or node.node_id != binding.node_id:
		return _failure("action_story_or_node_mismatch")
	var field := _proof_field(binding)
	return {"ok": true, "story_id": node.story_id, "node_id": node.node_id,
		"action_id": node.action_id, field: binding[field]}


func _arm_error(arm: Dictionary) -> String:
	if arm.is_empty():
		return "action_not_armed"
	var proof_field := _proof_field(arm)
	var fields := ["story_id", "node_id", "action_id", proof_field, "entry_story_digest", "prior_receipts"]
	if proof_field == "operation_id":
		fields.append("target_instances")
	if not _fields(arm, fields) or not arm.prior_receipts is Dictionary:
		return "invalid_arm_fields"
	var context := _current_binding()
	if not context.ok:
		return str(context.error)
	for field: String in ["story_id", "node_id", "action_id", proof_field]:
		if not context.has(field) or arm[field] != context[field]:
			return "arm_current_action_mismatch"
	if proof_field == "operation_id" and not _valid_target_map(arm.operation_id, arm.target_instances):
		return "invalid_operation_target_instances"
	if arm.entry_story_digest != _progress_digest():
		return "arm_story_history_changed"
	for id: Variant in arm.prior_receipts:
		if not id is String or not _table.transaction_receipts.has(id) or arm.prior_receipts[id] != Runner.canonical_digest(_table.transaction_receipts[id]):
			return "arm_prior_receipt_changed_or_missing"
	return ""


func _history_error(settled: Dictionary) -> String:
	var consumed: Dictionary = _session.to_data().state.transactions
	for id: Variant in settled:
		var proof: Variant = settled[id]
		var proof_field := _proof_field(proof)
		var fields := ["story_id", "node_id", "action_id", proof_field, "entry_story_digest", "prior_receipts_digest", "receipt_digest"]
		if proof_field == "operation_id":
			fields.append("target_instances")
		if not id is String or not _fields(proof, fields):
			return "invalid_bridge_settlement_fields"
		if not consumed.has(id) or not _bindings.has(proof.action_id):
			return "bridge_settlement_not_in_story"
		var binding: Dictionary = _bindings[proof.action_id]
		for field: String in ["story_id", "node_id", "action_id"]:
			if proof[field] != consumed[id][field]:
				return "bridge_settlement_story_mismatch"
		if proof.story_id != binding.story_id or proof.node_id != binding.node_id or not binding.has(proof_field) or proof[proof_field] != binding[proof_field]:
			return "bridge_settlement_binding_mismatch"
		if proof_field == "operation_id" and not _valid_target_map(proof.operation_id, proof.target_instances):
			return "invalid_operation_target_instances"
		for field: String in ["entry_story_digest", "prior_receipts_digest", "receipt_digest"]:
			if not _hash(proof[field]):
				return "invalid_bridge_settlement_digest"
		var receipt_error := _receipt_error(id, proof_field, binding[proof_field], proof.get("target_instances", {}))
		if not receipt_error.is_empty():
			return receipt_error
		if proof.receipt_digest != Runner.canonical_digest(_table.transaction_receipts[id]):
			return "bridge_settlement_receipt_changed"
	for id: Variant in consumed:
		if _bindings.has(consumed[id].action_id) and not settled.has(id):
			return "settled_action_missing_bridge_proof"
	return ""


func _receipt_error(id: String, proof_field: String, proof_id: String, target_instances: Dictionary = {}) -> String:
	if not _table.transaction_receipts.has(id):
		return "transaction_receipt_missing"
	var receipt: Variant = _table.transaction_receipts[id]
	if not receipt is Dictionary or receipt.get("status") != "completed":
		return "transaction_is_not_completed"
	if proof_field == "operation_id":
		if receipt.get("kind") != Operations.RECEIPT_KIND or receipt.get("operation_id") != proof_id:
			return "transaction_operation_mismatch"
		var error := Operations.validate_receipt(id, receipt, _operations, _table, _session, Services.workbench_policy(_service_catalog))
		if not error.is_empty():
			return error
		for target: String in target_instances.values():
			if target not in receipt.participant_ids:
				return "operation_target_instance_mismatch"
	else:
		if receipt.get("recipe_id") != proof_id or receipt.get("kind", "") != "":
			return "transaction_recipe_mismatch"
		if receipt.get("recipe_fingerprint") != Runner.canonical_digest(_recipes[proof_id]):
			return "transaction_recipe_fingerprint_mismatch"
	# 共用联合检查点的严格收据校验，包含消耗/产物计数、来源和实例身份。
	return Checkpoint.validate_receipts(_table, _recipes, _market_catalog, _event_definitions, _operations, _service_catalog, _session, _customer_catalog)


func _operation_targets(operation_id: String) -> Dictionary:
	var op: Dictionary = _operations[operation_id]
	var relevant := _important_target_definitions(op)
	var targets: Dictionary = {}
	for definition: String in relevant:
		var matches: Array[String] = []
		for id: String in _table.cards:
			# 同定义的唯一一张也可能属于另一封信／另一张委托，不能仅因数量为一就锁错对象。
			if _table.cards[id].zone == &"board" and _table.definition_id_for_card(id) == definition and _target_metadata_matches(id, definition, op):
				matches.append(id)
		if matches.size() > 1:
			return _failure("ambiguous_operation_action_target")
		if matches.size() == 1:
			targets[definition] = matches[0]
	return {"ok": true, "targets": targets}


func _important_target_definitions(op: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var metadata_targets: Dictionary = {}
	for condition: Dictionary in op.requires_metadata:
		metadata_targets[condition.card_id] = true
	for transform: Dictionary in op.transforms:
		metadata_targets[transform.card_id] = true
	for participant: Dictionary in op.participants:
		if int(participant.count) != 1:
			continue
		var definition := _table.content_card_definition(participant.card_id)
		if definition.get("unique", false) or definition.get("protected", false) or definition.category in ["character", "location"] or metadata_targets.has(participant.card_id) or op.source_card_id == participant.card_id:
			result[participant.card_id] = true
	return result


func _target_metadata_matches(id: String, definition: String, op: Dictionary) -> bool:
	var metadata: Dictionary = _table.cards[id].metadata
	for condition: Dictionary in op.requires_metadata:
		if condition.card_id != definition:
			continue
		for key: String in condition.values:
			if key == "bound_sigil_definition_id":
				var sigil: String = metadata.get("bound_sigil", "")
				if not _table.cards.has(sigil) or _table.definition_id_for_card(sigil) != condition.values[key] or _table.cards[sigil].zone != &"bound" or _table.cards[sigil].metadata.get("bound_to") != id:
					return false
			elif metadata.get(key) != condition.values[key]:
				return false
	return true


func _valid_target_map(operation_id: String, value: Variant) -> bool:
	if not _operations is Dictionary or not _operations.has(operation_id) or not value is Dictionary:
		return false
	var allowed := _important_target_definitions(_operations[operation_id])
	var seen: Dictionary = {}
	for definition: Variant in value:
		var id: Variant = value[definition]
		if not allowed.has(definition) or not id is String or not id.begins_with("card_") or not id.trim_prefix("card_").is_valid_int() or int(id.trim_prefix("card_")) <= 0 or int(id.trim_prefix("card_")) >= _table.next_card_id or seen.has(id):
			return false
		seen[id] = true
	return true


static func _proof_field(value: Variant) -> String:
	return "operation_id" if value is Dictionary and value.has("operation_id") else "recipe_id"


func _progress_digest() -> String:
	var data := _session.to_data()
	data.state.erase("paused")
	return Runner.canonical_digest(data)


func _table_digest() -> String:
	var data := _table.snapshot()
	for field: String in ["next_card_id", "next_stack_id", "next_z"]:
		data.erase(field)
	return Runner.canonical_digest(data)


func _receipt_digests() -> Dictionary:
	var result: Dictionary = {}
	for id: Variant in _table.transaction_receipts:
		result[id] = Runner.canonical_digest(_table.transaction_receipts[id])
	return result


static func _fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: Variant in fields:
		if not value.has(field):
			return false
	return true


static func _hash(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for c: String in value:
		if c not in "0123456789abcdef":
			return false
	return true


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
