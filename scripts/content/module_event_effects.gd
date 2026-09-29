class_name ModuleEventEffects
extends RefCounted

const StorySession = preload("res://scripts/content/module_story_session.gd")
const RECEIPT_KIND := "chapter_event"
const TRANSACTION_PREFIX := "event/"
const MAX_EVENTS := 512
const METADATA_FIELDS := ["state", "npc_id", "addressee", "inner_seal"]

var _table: TableState
var _story: StorySession
var _events: Dictionary = {}


func configure(table: TableState, story_session: StorySession, event_definitions: Dictionary) -> Dictionary:
	if table == null or story_session == null or String(story_session.to_data().catalog_fingerprint).is_empty():
		return _failure("missing_event_context")
	if event_definitions.size() > MAX_EVENTS:
		return _failure("too_many_event_definitions")
	var checked := {}
	for id: Variant in event_definitions:
		var error := _definition_error(id, event_definitions[id], table)
		if not error.is_empty():
			return _failure(error)
		if not story_session.story_exists(event_definitions[id].trigger_story_id):
			return _failure("unknown_trigger_story")
		checked[id] = _normalized(event_definitions[id])
	var error := _table_error(table, story_session, checked)
	if not error.is_empty():
		return _failure(error)
	_table = table
	_story = story_session
	_events = checked
	return {"ok": true, "error": ""}


# 本层只结算已完成剧情的后果，不生成制作、转印或订单已经完成的证明。
func apply(event_id: String, source_instance_id: String) -> Dictionary:
	if _table == null or _story == null:
		return _failure("not_configured")
	if not _events.has(event_id):
		return _failure("unknown_event")
	var error := _definition_error(event_id, _events[event_id], _table)
	if not error.is_empty():
		return _failure(error)
	error = _table_error(_table, _story, _events)
	if not error.is_empty():
		return _failure(error)
	var event: Dictionary = _events[event_id]
	if not _story.story_exists(event.trigger_story_id) or event.trigger_story_id not in _story.to_data().state.completed:
		return _failure("trigger_story_not_completed")
	var transaction_id := TRANSACTION_PREFIX + event_id
	if _table.transaction_receipts.has(transaction_id):
		var previous: Dictionary = _table.transaction_receipts[transaction_id]
		if previous.source_instance_id != source_instance_id:
			return _failure("event_source_conflict")
		return _result(previous, true)
	if not _table.cards.has(source_instance_id) or _table.cards[source_instance_id].zone != &"board" or _table.stack_for(source_instance_id).is_empty():
		return _failure("event_source_not_on_board")
	if _table.definition_id_for_card(source_instance_id) != event.source_card_id:
		return _failure("event_source_definition_mismatch")
	var source_card: Dictionary = _table.cards[source_instance_id]
	var source_definition := _table.content_card_definition(event.source_card_id)
	if source_definition.category == "character" and event.source_card_id != "card.hero":
		var npc: Variant = source_card.metadata.get("npc_id")
		if not _npc_matches(npc, event.source_card_id, _table):
			return _failure("event_source_npc_mismatch")
	if _table.sigil_instance_locked(source_instance_id):
		return _failure("event_source_locked")
	var grant_count := 0
	for grant: Dictionary in event.grants:
		grant_count += int(grant.count)
	if _table.card_count() - event.removes.size() + grant_count > TableState.MAX_CARDS:
		return _failure("capacity_exceeded")
	var source := _table.card_position(source_instance_id)
	var candidate := _table.fork_empty()
	candidate.restore(_table.snapshot())
	var removed: Array[String] = []
	if not event.removes.is_empty():
		var stack := candidate.stack_for(source_instance_id)
		var survivor_position := Vector2.ZERO
		var survivor_found := false
		for id: String in candidate.stacks[stack].cards:
			if id != source_instance_id:
				survivor_position = candidate.card_position(id)
				survivor_found = true
				break
		if not candidate.remove_card(source_instance_id):
			return _failure("event_source_removal_refused")
		if survivor_found:
			candidate.move_stack(stack, survivor_position)
		removed.append(source_instance_id)
	var created: Array[String] = []
	for grant: Dictionary in event.grants:
		if grant.metadata.has("npc_id") and _npc_present(candidate, grant.metadata.npc_id):
			return _failure("event_npc_already_present")
		var remaining := int(grant.count)
		while remaining > 0:
			var count := mini(remaining, TableState.MAX_STACK)
			var stack := candidate.create_defined(grant.card_id, source, count)
			if stack.is_empty() or candidate.stacks[stack].cards.size() != count:
				return _failure("event_grant_refused")
			for id: String in candidate.stacks[stack].cards:
				for field: String in grant.metadata:
					candidate.cards[id].metadata[field] = grant.metadata[field]
				created.append(id)
			remaining -= count
	var receipt := {"kind": RECEIPT_KIND, "version": 1, "transaction_id": transaction_id,
		"event_id": event_id, "event_fingerprint": _fingerprint(event), "source_instance_id": source_instance_id,
		"source_position": [source.x, source.y], "created_ids": created, "removed_ids": removed,
		"grants_facts": event.grants_facts.duplicate(), "status": "completed"}
	candidate.transaction_receipts[transaction_id] = receipt
	error = _table_error(candidate, _story, _events)
	if not error.is_empty():
		return _failure(error)
	if _table.sigil_instance_locked(source_instance_id):
		return _failure("event_source_locked")
	_table.restore(candidate.snapshot())
	return _result(receipt, false)


static func validate_receipt(transaction_id: String, value: Variant, event_definitions: Dictionary, table_context: TableState = null) -> String:
	var context := table_context if table_context != null else TableState.new()
	if not _fields(value, ["kind", "version", "transaction_id", "event_id", "event_fingerprint", "source_instance_id", "source_position", "created_ids", "removed_ids", "grants_facts", "status"]):
		return "invalid_event_receipt_fields"
	for field: String in ["kind", "transaction_id", "event_id", "event_fingerprint", "source_instance_id", "status"]:
		if not value[field] is String:
			return "invalid_event_receipt_field_type"
	if value.kind != RECEIPT_KIND or not _integer(value.version, 1, 1) or value.status != "completed":
		return "invalid_event_receipt_kind_or_version"
	if not _matches(value.event_id, "^event\\.[a-z0-9_.]+$") or transaction_id != TRANSACTION_PREFIX + String(value.event_id) or value.transaction_id != transaction_id:
		return "invalid_event_receipt_identity"
	if not event_definitions.has(value.event_id):
		return "unknown_receipt_event"
	var event: Variant = event_definitions[value.event_id]
	var error := _definition_error(value.event_id, event, context)
	if not error.is_empty():
		return error
	if value.event_fingerprint != _fingerprint(event):
		return "event_receipt_fingerprint_mismatch"
	if not _instance_id(value.source_instance_id) or not _position(value.source_position):
		return "invalid_event_receipt_source"
	var at := Vector2(float(value.source_position[0]), float(value.source_position[1]))
	if not TableState.WORLD_BOUNDS.encloses(Rect2(at, TableState.CARD_SIZE)):
		return "event_receipt_source_outside_board"
	if not _instance_list(value.created_ids) or not _instance_list(value.removed_ids):
		return "invalid_event_receipt_instances"
	var count := 0
	for grant: Dictionary in event.grants:
		count += int(grant.count)
	if value.created_ids.size() != count or value.removed_ids.size() != event.removes.size():
		return "event_receipt_count_mismatch"
	if value.source_instance_id in value.created_ids or (not value.removed_ids.is_empty() and value.removed_ids != [value.source_instance_id]):
		return "event_receipt_reused_or_wrong_instance"
	var previous_serial := int(String(value.source_instance_id).trim_prefix("card_"))
	var first_created := true
	for id: String in value.created_ids:
		if id in value.removed_ids:
			return "event_receipt_created_removed_overlap"
		var serial := int(id.trim_prefix("card_"))
		if serial <= previous_serial or (not first_created and serial != previous_serial + 1):
			return "event_receipt_creation_order_invalid"
		previous_serial = serial
		first_created = false
	if not _fact_list(value.grants_facts) or value.grants_facts != event.grants_facts:
		return "event_receipt_facts_mismatch"
	if table_context != null:
		for id: String in value.removed_ids:
			if table_context.cards.has(id):
				return "removed_event_source_reappeared"
		for id: String in [value.source_instance_id] + value.created_ids + value.removed_ids:
			if int(id.trim_prefix("card_")) >= table_context.next_card_id:
				return "event_receipt_instance_exceeds_allocator"
	return ""


static func _definition_error(id: Variant, value: Variant, table: TableState) -> String:
	if not _matches(id, "^event\\.[a-z0-9_.]+$") or not _fields(value, ["id", "trigger_story_id", "source_card_id", "grants", "removes", "grants_facts"]):
		return "invalid_event_definition_fields"
	if not value.id is String or value.id != id or not _matches(value.trigger_story_id, "^story\\.[a-z0-9_.]+$") or not _matches(value.source_card_id, "^card\\.[a-z0-9_.]+$"):
		return "invalid_event_definition_identity"
	var source := table.content_card_definition(value.source_card_id)
	if source.is_empty():
		return "unknown_event_source_definition"
	if not value.grants is Array or value.grants.size() > TableState.MAX_CARDS or not value.removes is Array or value.removes.size() > 1 or not _fact_list(value.grants_facts):
		return "invalid_event_definition_collections"
	if not value.removes.is_empty():
		if not value.removes[0] is String or value.removes[0] != value.source_card_id or value.source_card_id == "card.hero" or source.category != "character":
			return "event_can_only_remove_its_npc_source"
		var found := false
		for npc_id: String in table.content_npc_ids():
			if table.content_npc_definition(npc_id).get("card_id") == value.source_card_id:
				found = true
		if not found:
			return "event_removal_source_is_not_an_npc"
	var total := 0
	var definitions := {}
	var npcs := {}
	for grant: Variant in value.grants:
		if not _fields(grant, ["card_id", "count", "metadata"]) or not _matches(grant.card_id, "^card\\.[a-z0-9_.]+$") or not _integer(grant.count, 1, TableState.MAX_CARDS):
			return "invalid_event_grant"
		var definition := table.content_card_definition(grant.card_id)
		if definition.is_empty() or grant.card_id == "card.hero" or "sigil" in definition.get("tags", []):
			return "forbidden_or_unknown_event_grant"
		if definitions.has(grant.card_id) or grant.card_id in value.removes:
			return "duplicate_or_recreated_event_grant"
		definitions[grant.card_id] = true
		if (definition.get("unique", false) or definition.category == "character") and int(grant.count) != 1:
			return "event_unique_grant_count_invalid"
		if not grant.metadata is Dictionary or grant.metadata.size() > METADATA_FIELDS.size():
			return "invalid_event_grant_metadata"
		for field: Variant in grant.metadata:
			if not field is String or field not in METADATA_FIELDS or not _matches(grant.metadata[field], "^[a-z][a-z0-9_.:-]*$"):
				return "unsupported_event_grant_metadata"
		if definition.category == "character" and not grant.metadata.has("npc_id"):
			return "event_npc_grant_requires_identity"
		if grant.metadata.has("npc_id"):
			if not _npc_matches(grant.metadata.npc_id, grant.card_id, table) or npcs.has(grant.metadata.npc_id):
				return "event_npc_grant_identity_mismatch"
			npcs[grant.metadata.npc_id] = true
		total += int(grant.count)
		if total > TableState.MAX_CARDS:
			return "event_grant_capacity_invalid"
	return ""


static func _table_error(table: TableState, story: StorySession, definitions: Dictionary) -> String:
	var error := table.validate()
	if not error.is_empty():
		return "invalid_event_table: " + error
	for id: String in table.cards:
		var metadata: Dictionary = table.cards[id].metadata
		if metadata.has("npc_id") and not _npc_matches(metadata.npc_id, table.definition_id_for_card(id), table):
			return "invalid_event_table_npc_identity"
	var completed: Array = story.to_data().state.completed
	for transaction_id: Variant in table.transaction_receipts:
		if not transaction_id is String:
			return "invalid_transaction_key"
		var receipt: Variant = table.transaction_receipts[transaction_id]
		var owned: bool = receipt is Dictionary and (receipt.has("event_fingerprint") or (receipt.get("kind") is String and receipt.kind == RECEIPT_KIND))
		if transaction_id.begins_with(TRANSACTION_PREFIX) or owned:
			error = validate_receipt(transaction_id, receipt, definitions, table)
			if not error.is_empty():
				return error
			if not story.story_exists(definitions[receipt.event_id].trigger_story_id) or definitions[receipt.event_id].trigger_story_id not in completed:
				return "event_receipt_lacks_completed_story"
	return ""


static func _npc_matches(npc: Variant, card_definition_id: String, table: TableState) -> bool:
	if not _matches(npc, "^npc\\.[a-z0-9_.]+$"):
		return false
	return table.content_npc_definition(npc).get("card_id", "") == card_definition_id


static func _npc_present(table: TableState, npc_id: String) -> bool:
	for card: Dictionary in table.cards.values():
		if card.metadata.get("npc_id", "") == npc_id:
			return true
	return false


static func _normalized(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for grant: Dictionary in result.grants:
		grant.count = int(grant.count)
	return result


static func _fingerprint(value: Dictionary) -> String:
	return JSON.stringify(_normalized(value), "", true, true).sha256_text()


static func _fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _instance_id(value: Variant) -> bool:
	if not _matches(value, "^card_[0-9]{4,}$"):
		return false
	var serial := int(String(value).trim_prefix("card_"))
	return serial > 0 and serial < 2147483647 and value == "card_%04d" % serial


static func _instance_list(value: Variant) -> bool:
	if not value is Array or value.size() > TableState.MAX_CARDS:
		return false
	var seen := {}
	for id: Variant in value:
		if not _instance_id(id) or seen.has(id):
			return false
		seen[id] = true
	return true


static func _fact_list(value: Variant) -> bool:
	if not value is Array or value.size() > 128:
		return false
	var seen := {}
	for fact: Variant in value:
		if not _matches(fact, "^fact\\.[a-z0-9_.]+$") or seen.has(fact):
			return false
		seen[fact] = true
	return true


static func _position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= lower and float(value) <= upper


static func _matches(value: Variant, pattern: String) -> bool:
	if not value is String or value.is_empty() or value.length() > 240:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func _result(receipt: Dictionary, replay: bool) -> Dictionary:
	var result := receipt.duplicate(true)
	result["ok"] = true
	result["already_applied"] = replay
	return result


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
