class_name ModuleSigilBindings
extends RefCounted

const RECEIPT_KIND := "sigil_binding"
const GRANT_PREFIX := "sigil/grant/"

var _table: TableState


func configure(table: TableState) -> Dictionary:
	if table == null:
		return _failure("missing_table")
	var result := _validate_table(table)
	if not result.ok:
		return result
	_table = table
	return {"ok": true, "error": ""}


func validate() -> Dictionary:
	return _failure("not_configured") if _table == null else _validate_table(_table)


func bind(sigil_instance: String, host_instance: String, transaction_id: String) -> Dictionary:
	var request := {"sigil_instance_id": sigil_instance, "host_instance_id": host_instance}
	var initial := _prepare("bind", request, transaction_id)
	if not initial.ok or initial.get("already_applied", false):
		return initial
	if not _table.cards.has(sigil_instance) or not _table.cards.has(host_instance):
		return _failure("unknown_instance")
	if _table.sigil_instance_locked(sigil_instance) or _table.sigil_instance_locked(host_instance):
		return _failure("instance_locked")
	var candidate := _candidate()
	var source := candidate.card_position(host_instance)
	if not candidate.bind_sigil(sigil_instance, host_instance):
		return _failure("binding_not_permitted")
	return _commit(candidate, "bind", request, transaction_id, sigil_instance, host_instance, source)


func unbind(sigil_instance: String, transaction_id: String) -> Dictionary:
	var request := {"sigil_instance_id": sigil_instance}
	var initial := _prepare("unbind", request, transaction_id)
	if not initial.ok or initial.get("already_applied", false):
		return initial
	if not _table.cards.has(sigil_instance) or _table.cards[sigil_instance].zone != &"bound":
		return _failure("sigil_not_bound")
	var host_instance := String(_table.cards[sigil_instance].metadata.bound_to)
	if _table.sigil_instance_locked(sigil_instance) or _table.sigil_instance_locked(host_instance):
		return _failure("instance_locked")
	var candidate := _candidate()
	var source := candidate.card_position(host_instance)
	if not candidate.unbind_sigil(sigil_instance):
		return _failure("unbinding_not_permitted")
	return _commit(candidate, "unbind", request, transaction_id, sigil_instance, host_instance, source)


# 仅供已经验证剧情许可的上层调用；本层不自行判定事件是否已经发生。
func grant_bound(event_id: String, sigil_definition: String, host_instance: String) -> Dictionary:
	if not _matches(event_id, "^event\\.[a-z0-9_.]+$"):
		return _failure("invalid_grant_event")
	var transaction_id := GRANT_PREFIX + event_id
	var request := {"event_id": event_id, "sigil_definition_id": sigil_definition, "host_instance_id": host_instance}
	var initial := _prepare("grant_bound", request, transaction_id)
	if not initial.ok or initial.get("already_applied", false):
		return initial
	if not _table.cards.has(host_instance):
		return _failure("unknown_host")
	if _table.sigil_instance_locked(host_instance):
		return _failure("instance_locked")
	if _table.card_count() >= TableState.MAX_CARDS:
		return _failure("capacity_exceeded")
	if not TableState.sigil_definition_compatible(sigil_definition, _table.definition_id_for_card(host_instance), _table):
		return _failure("incompatible_sigil_definition")
	var candidate := _candidate()
	var source := candidate.card_position(host_instance)
	var stack := candidate.create_defined(sigil_definition, source)
	if stack.is_empty():
		return _failure("sigil_creation_refused")
	var sigil_instance: String = candidate.stacks[stack].cards[0]
	if not candidate.bind_sigil(sigil_instance, host_instance):
		return _failure("binding_not_permitted")
	return _commit(candidate, "grant_bound", request, transaction_id, sigil_instance, host_instance, source)


func _prepare(action: String, request: Dictionary, transaction_id: String) -> Dictionary:
	var result := validate()
	if not result.ok:
		return result
	if not _transaction_valid(transaction_id) or transaction_id.begins_with("recipe/"):
		return _failure("invalid_transaction_id")
	if action != "grant_bound" and transaction_id.begins_with(GRANT_PREFIX):
		return _failure("reserved_grant_transaction")
	if _table.transaction_receipts.has(transaction_id):
		var previous: Variant = _table.transaction_receipts[transaction_id]
		if not previous is Dictionary or previous.get("kind") != RECEIPT_KIND or previous.get("action") != action or _digest(previous.get("request")) != _digest(request):
			return _failure("transaction_request_conflict")
		var replay: Dictionary = previous.duplicate(true)
		replay["ok"] = true
		replay["already_applied"] = true
		return replay
	return {"ok": true, "error": ""}


func _candidate() -> TableState:
	var candidate := _table.fork_empty()
	candidate.restore(_table.snapshot())
	return candidate


func _commit(candidate: TableState, action: String, request: Dictionary, transaction_id: String, sigil_instance: String, host_instance: String, source: Vector2) -> Dictionary:
	var receipt := {"kind": RECEIPT_KIND, "version": 1, "action": action, "transaction_id": transaction_id,
		"status": "completed", "request": request.duplicate(true), "sigil_instance_id": sigil_instance,
		"sigil_definition_id": candidate.definition_id_for_card(sigil_instance), "host_instance_id": host_instance,
		"source_position": [source.x, source.y]}
	candidate.transaction_receipts[transaction_id] = receipt
	var checked := _validate_table(candidate)
	if not checked.ok:
		return checked
	# 操作同步完成，没有 await 或对外信号；提交前再确认配方没有占用这两张牌。
	if _table.sigil_instance_locked(sigil_instance) or _table.sigil_instance_locked(host_instance):
		return _failure("instance_locked")
	_table.restore(candidate.snapshot())
	var result := receipt.duplicate(true)
	result["ok"] = true
	result["already_applied"] = false
	return result


static func validate_receipt(transaction_id: String, value: Variant, context_table: TableState = null) -> String:
	if not value is Dictionary:
		return "invalid_sigil_receipt"
	var receipt: Dictionary = value
	var fields := ["kind", "version", "action", "transaction_id", "status", "request", "sigil_instance_id", "sigil_definition_id", "host_instance_id", "source_position"]
	if receipt.size() != fields.size():
		return "invalid_sigil_receipt_fields"
	for field: String in fields:
		if not receipt.has(field):
			return "missing_sigil_receipt_field"
	for field: String in ["kind", "action", "transaction_id", "status", "sigil_instance_id", "sigil_definition_id", "host_instance_id"]:
		if not receipt[field] is String:
			return "invalid_sigil_receipt_field_type"
	if receipt.kind != RECEIPT_KIND or not (receipt.version is int or receipt.version is float) or receipt.version != 1:
		return "invalid_sigil_receipt_version"
	if not _transaction_valid(transaction_id) or transaction_id.begins_with("recipe/") or receipt.transaction_id != transaction_id or receipt.status != "completed":
		return "invalid_sigil_receipt_identity"
	if receipt.action not in ["bind", "unbind", "grant_bound"] or not receipt.request is Dictionary:
		return "invalid_sigil_receipt_action"
	if not _instance_valid(receipt.sigil_instance_id) or not _instance_valid(receipt.host_instance_id) or receipt.sigil_instance_id == receipt.host_instance_id:
		return "invalid_sigil_receipt_instances"
	if not _matches(receipt.sigil_definition_id, "^card\\.[a-z0-9_.]+$"):
		return "invalid_sigil_receipt_definition"
	var definition := context_table.content_card_definition(receipt.sigil_definition_id) if context_table != null else ContentCatalog.card_definition(receipt.sigil_definition_id)
	if "sigil" not in definition.get("tags", []) or not definition.get("unique", false) or not definition.get("protected", false) or definition.get("sellable", true):
		return "unavailable_sigil_receipt_definition"
	if not receipt.source_position is Array or receipt.source_position.size() != 2 or not _number(receipt.source_position[0]) or not _number(receipt.source_position[1]):
		return "invalid_sigil_receipt_position"
	if not TableState.WORLD_BOUNDS.has_point(Vector2(float(receipt.source_position[0]), float(receipt.source_position[1]))):
		return "sigil_receipt_position_outside_board"
	var request: Dictionary = receipt.request
	for value_in_request: Variant in request.values():
		if not value_in_request is String:
			return "invalid_sigil_request_type"
	if receipt.action == "grant_bound":
		if request.size() != 3 or not _matches(request.get("event_id"), "^event\\.[a-z0-9_.]+$") or transaction_id != GRANT_PREFIX + String(request.event_id):
			return "invalid_sigil_grant_event"
		if request.get("sigil_definition_id") != receipt.sigil_definition_id or request.get("host_instance_id") != receipt.host_instance_id:
			return "sigil_grant_request_mismatch"
	else:
		if transaction_id.begins_with(GRANT_PREFIX):
			return "reserved_sigil_grant_receipt"
		if request.get("sigil_instance_id") != receipt.sigil_instance_id or request.size() != (2 if receipt.action == "bind" else 1):
			return "sigil_request_mismatch"
		if receipt.action == "bind" and request.get("host_instance_id") != receipt.host_instance_id:
			return "sigil_host_request_mismatch"
	return ""


static func _validate_table(table: TableState) -> Dictionary:
	var error := table.validate()
	if not error.is_empty():
		return _failure("invalid_table: " + error)
	for transaction_id: Variant in table.transaction_receipts:
		if not transaction_id is String:
			return _failure("invalid_receipt_id")
		var receipt: Variant = table.transaction_receipts[transaction_id]
		var sigil_receipt: bool = receipt is Dictionary and (receipt.has("sigil_instance_id") or receipt.has("sigil_definition_id") or (receipt.get("kind") is String and receipt.kind == RECEIPT_KIND))
		if transaction_id.begins_with(GRANT_PREFIX) or sigil_receipt:
			error = validate_receipt(transaction_id, receipt, table)
			if not error.is_empty():
				return _failure(error)
	return {"ok": true, "error": ""}


static func _transaction_valid(value: Variant) -> bool:
	return _matches(value, "^[a-zA-Z0-9][a-zA-Z0-9_./:-]{0,199}$") and not ".." in String(value)


static func _instance_valid(value: Variant) -> bool:
	return _matches(value, "^card_[0-9]{4,}$")


static func _matches(value: Variant, pattern: String) -> bool:
	if not value is String or value.is_empty() or value.length() > 240:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _digest(value: Variant) -> String:
	return JSON.stringify(value, "", true, true).sha256_text()


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
