class_name ChapterAppointmentService
extends RefCounted

const KIND := "chapter_appointment"
const FIRST_PREFIX := "appointment/first/"
const RETURN_PREFIX := "appointment/revisit/"

var table: TableState
var story: RefCounted
var operations: Dictionary = {}
var rules: Dictionary = {}


func configure(table_context: TableState, story_session: RefCounted, operation_catalog: Dictionary, scene_rules: Dictionary) -> Dictionary:
	if table_context == null or story_session == null or not operation_catalog is Dictionary or not scene_rules is Dictionary:
		return _failure("appointment_context_missing")
	table = table_context
	story = story_session
	operations = operation_catalog
	rules = scene_rules
	for tx: String in table.transaction_receipts:
		var receipt: Variant = table.transaction_receipts[tx]
		if tx.begins_with(FIRST_PREFIX) or tx.begins_with(RETURN_PREFIX) or receipt is Dictionary and receipt.get("kind") == KIND:
			var error := validate_receipt(tx, receipt, operations, table, story)
			if not error.is_empty():
				return _failure(error)
	return {"ok": true}


func can_revisit(story_id: String, npc_instance_id: String, day: int) -> Dictionary:
	if table == null or story == null or not story_id.begins_with("story.ch01.return_visit."):
		return _failure("unknown_appointment_story")
	var slug := story_id.trim_prefix("story.ch01.return_visit.")
	var first_id := FIRST_PREFIX + slug
	var op_id := "operation.ch01.visit_contact_" + slug
	var first_story := "story.ch01.contact_visit." + slug
	if not rules.has(story_id) or not operations.has(op_id) or not table.transaction_receipts.has(first_id):
		return _failure("appointment_not_yet_established")
	if first_story not in story.to_data().state.completed:
		return _failure("first_meeting_not_completed")
	var first: Dictionary = table.transaction_receipts[first_id]
	if day <= int(first.day):
		return _failure("appointment_next_day_required")
	if table.transaction_receipts.has(RETURN_PREFIX + slug + "/%d" % day):
		return _failure("appointment_already_kept_today")
	if not table.cards.has(npc_instance_id) or table.cards[npc_instance_id].zone != &"board":
		return _failure("appointment_npc_not_present")
	var op: Dictionary = operations[op_id]
	if table.definition_id_for_card(npc_instance_id) != op.source_card_id or table.cards[npc_instance_id].metadata.get("npc_id") != rules[story_id].npc_id:
		return _failure("appointment_wrong_person")
	for id: String in table.cards:
		if table.cards[id].zone == &"queue" and table.cards[id].metadata.get("npc_id") == rules[story_id].npc_id:
			return _failure("appointment_npc_busy_with_customer")
	var stack := table.stack_for(npc_instance_id)
	if stack.is_empty() or not table.stacks.has(stack) or table.stacks[stack].cards.size() != 4:
		return _failure("appointment_cards_not_combined")
	var ids: Array = table.stacks[stack].cards
	var expected := _definitions_for(op)
	var actual: Dictionary = {}
	var appointment_id := ""
	var location_id := ""
	for id: String in ids:
		var definition := table.definition_id_for_card(id)
		actual[definition] = int(actual.get(definition, 0)) + 1
		if definition == "card.ch01.appointment":
			appointment_id = id
		elif definition != "card.hero" and definition != op.source_card_id:
			location_id = id
		var locks: Dictionary = table.get_meta(&"module_recipe_runtime_locks", {})
		if locks.has(id) or table.sigil_instance_locked(id):
			return _failure("appointment_participant_busy")
	if actual != expected or appointment_id != first.appointment_instance_id or npc_instance_id != first.npc_instance_id or location_id != first.location_instance_id:
		return _failure("appointment_wrong_cards_or_place")
	var metadata: Dictionary = table.cards[appointment_id].metadata
	if metadata.get("state") != "standing" or metadata.get("purpose") != "meeting_window" or metadata.get("addressee") != rules[story_id].npc_id:
		return _failure("appointment_original_not_standing")
	return {"ok": true, "slug": slug, "npc_instance_id": npc_instance_id,
		"appointment_instance_id": appointment_id, "location_instance_id": location_id,
		"operation_transaction_id": first.operation_transaction_id}


func record_first(story_id: String, npc_instance_id: String, day: int) -> Dictionary:
	if table == null or not story_id.begins_with("story.ch01.contact_visit."):
		return _failure("unknown_first_appointment")
	var slug := story_id.trim_prefix("story.ch01.contact_visit.")
	var tx := FIRST_PREFIX + slug
	var op_id := "operation.ch01.visit_contact_" + slug
	if table.transaction_receipts.has(tx) or not operations.has(op_id) or not table.cards.has(npc_instance_id):
		return _failure("first_appointment_record_unavailable")
	var op: Dictionary = operations[op_id]
	var source_receipt: Dictionary = {}
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("kind") == "chapter_operation" and receipt.get("status") == "completed" and receipt.get("operation_id") == op_id and receipt.get("source_id") == npc_instance_id:
			source_receipt = receipt
	if source_receipt.is_empty():
		return _failure("first_appointment_operation_missing")
	var appointment_id := ""
	var location_id := ""
	for id: String in source_receipt.participant_ids:
		if not table.cards.has(id):
			return _failure("first_appointment_participant_missing")
		var definition := table.definition_id_for_card(id)
		if definition == "card.ch01.appointment":
			appointment_id = id
		elif definition != "card.hero" and definition != op.source_card_id:
			location_id = id
	if appointment_id.is_empty() or location_id.is_empty():
		return _failure("first_appointment_original_missing")
	var receipt := _receipt(tx, "first", slug, day, story_id, source_receipt.transaction_id,
		npc_instance_id, appointment_id, location_id)
	var error := validate_receipt(tx, receipt, operations, table, story)
	if not error.is_empty():
		return _failure(error)
	table.transaction_receipts[tx] = receipt
	return {"ok": true, "transaction_id": tx}


func reserve_revisit(story_id: String, npc_instance_id: String, day: int) -> Dictionary:
	var eligible := can_revisit(story_id, npc_instance_id, day)
	if not eligible.ok:
		return eligible
	var tx: String = RETURN_PREFIX + eligible.slug + "/%d" % day
	var receipt := _receipt(tx, "revisit", eligible.slug, day, story_id, eligible.operation_transaction_id,
		npc_instance_id, eligible.appointment_instance_id, eligible.location_instance_id)
	var error := validate_receipt(tx, receipt, operations, table, story, true)
	if not error.is_empty():
		return _failure(error)
	table.transaction_receipts[tx] = receipt
	return {"ok": true, "transaction_id": tx}


func rollback_revisit(transaction_id: String) -> void:
	if transaction_id.begins_with(RETURN_PREFIX):
		table.transaction_receipts.erase(transaction_id)


static func validate_receipt(tx: String, receipt: Variant, operation_catalog: Dictionary, table_context: TableState, story_session: RefCounted, allow_unstarted: bool = false) -> String:
	var fields := ["kind", "version", "status", "action", "transaction_id", "slug", "day", "story_id",
		"operation_transaction_id", "npc_instance_id", "appointment_instance_id", "location_instance_id", "source_position"]
	if not _fields(receipt, fields) or receipt.kind != KIND or receipt.version != 1 or receipt.status != "completed" or receipt.transaction_id != tx:
		return "invalid_appointment_receipt_fields"
	if not receipt.slug is String or receipt.slug.is_empty() or not _integer(receipt.day, 1, 1000000000):
		return "invalid_appointment_receipt_identity"
	var slug: String = receipt.slug
	var op_id := "operation.ch01.visit_contact_" + slug
	if not operation_catalog.has(op_id) or not story_session.story_exists(receipt.story_id):
		return "appointment_catalog_context_missing"
	var first_story := "story.ch01.contact_visit." + slug
	var repeat_story := "story.ch01.return_visit." + slug
	if receipt.action == "first":
		if tx != FIRST_PREFIX + slug or receipt.story_id != first_story or first_story not in story_session.to_data().state.completed:
			return "invalid_first_appointment_receipt"
	elif receipt.action == "revisit":
		if tx != RETURN_PREFIX + slug + "/%d" % int(receipt.day) or receipt.story_id != repeat_story:
			return "invalid_revisit_appointment_receipt"
		if not table_context.transaction_receipts.has(FIRST_PREFIX + slug) or int(table_context.transaction_receipts[FIRST_PREFIX + slug].get("day", 0)) >= int(receipt.day):
			return "revisit_without_prior_day_meeting"
		var state: Dictionary = story_session.to_data().state
		if not allow_unstarted and receipt.story_id not in state.completed and state.story_id != receipt.story_id:
			return "revisit_without_started_conversation"
	else:
		return "unknown_appointment_action"
	if not table_context.transaction_receipts.has(receipt.operation_transaction_id):
		return "appointment_original_operation_missing"
	var operation: Variant = table_context.transaction_receipts[receipt.operation_transaction_id]
	if not operation is Dictionary or operation.get("kind") != "chapter_operation" or operation.get("status") != "completed" or operation.get("operation_id") != op_id:
		return "appointment_original_operation_mismatch"
	var op: Dictionary = operation_catalog[op_id]
	for id: Variant in [receipt.npc_instance_id, receipt.appointment_instance_id, receipt.location_instance_id]:
		if not id is String or not table_context.cards.has(id) or id not in operation.participant_ids:
			return "appointment_participant_missing"
	if receipt.npc_instance_id != operation.source_id or table_context.definition_id_for_card(receipt.npc_instance_id) != op.source_card_id:
		return "appointment_npc_identity_mismatch"
	if table_context.definition_id_for_card(receipt.appointment_instance_id) != "card.ch01.appointment":
		return "appointment_original_card_mismatch"
	if table_context.cards[receipt.appointment_instance_id].metadata.get("state") != "standing" or table_context.cards[receipt.appointment_instance_id].metadata.get("addressee") != table_context.cards[receipt.npc_instance_id].metadata.get("npc_id"):
		return "appointment_original_card_state_mismatch"
	var place := ""
	for item: Dictionary in op.participants:
		if item.card_id not in ["card.hero", op.source_card_id, "card.ch01.appointment"]:
			place = item.card_id
	if place.is_empty() or table_context.definition_id_for_card(receipt.location_instance_id) != place:
		return "appointment_place_mismatch"
	if not receipt.source_position is Array or receipt.source_position.size() != 2:
		return "appointment_position_invalid"
	for coordinate: Variant in receipt.source_position:
		if not coordinate is float and not coordinate is int or not is_finite(float(coordinate)):
			return "appointment_position_invalid"
	var point := Vector2(float(receipt.source_position[0]), float(receipt.source_position[1]))
	if not TableState.WORLD_BOUNDS.encloses(Rect2(point, TableState.CARD_SIZE)):
		return "appointment_position_invalid"
	return ""


func _receipt(tx: String, action: String, slug: String, day: int, story_id: String, operation_tx: String,
		npc_instance_id: String, appointment_instance_id: String, location_instance_id: String) -> Dictionary:
	var point := table.card_position(npc_instance_id)
	return {"kind": KIND, "version": 1, "status": "completed", "action": action, "transaction_id": tx,
		"slug": slug, "day": day, "story_id": story_id, "operation_transaction_id": operation_tx,
		"npc_instance_id": npc_instance_id, "appointment_instance_id": appointment_instance_id,
		"location_instance_id": location_instance_id, "source_position": [point.x, point.y]}


static func _definitions_for(op: Dictionary) -> Dictionary:
	var result := {}
	for rule: Dictionary in op.participants:
		result[rule.card_id] = int(rule.count)
	return result


static func _fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
