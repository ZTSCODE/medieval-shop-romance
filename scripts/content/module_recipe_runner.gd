class_name ModuleRecipeRunner
extends RefCounted

signal job_committed(result: Dictionary)
signal job_cancelled(result: Dictionary)

const SAVE_VERSION := 1
const LOCK_META := &"module_recipe_runtime_locks"

var _table: TableState
var _recipes: Dictionary = {}
var _recipes_by_participants: Dictionary = {}
var _jobs: Dictionary = {}
var _terminal: Dictionary = {}
var _recipe_digest := ""
var _nonce := ""
var _next_serial := 1
var _configuration_generation := 0


func configure(table: TableState, recipes: Dictionary) -> Dictionary:
	if table == null:
		return _failure("missing_table")
	if not _jobs.is_empty():
		return _failure("active_jobs_prevent_reconfiguration")
	var checked: Dictionary = {}
	for key: Variant in recipes:
		if not key is String or not recipes[key] is Dictionary:
			return _failure("invalid_recipe_entry")
		var recipe: Dictionary = recipes[key].duplicate(true)
		var error := _recipe_error(str(key), recipe, table)
		if not error.is_empty():
			return _failure(error)
		checked[str(key)] = recipe
	if not table.validate().is_empty():
		return _failure("invalid_table")
	_release_all_locks()
	_table = table
	_recipes = checked
	_recipes_by_participants.clear()
	for id: String in _recipes:
		var key := _recipe_participants_key(_recipes[id])
		if not _recipes_by_participants.has(key):
			_recipes_by_participants[key] = []
		_recipes_by_participants[key].append(id)
	_recipe_digest = _digest(checked)
	_configuration_generation += 1
	_nonce = "%s_%s_%d" % [get_instance_id(), Time.get_ticks_usec(), _configuration_generation]
	_next_serial = 1
	_terminal.clear()
	return {"ok": true, "recipe_count": checked.size()}


func begin(recipe_id: String, instance_ids: Array[String], source_id: String, facts: Array[String] = []) -> Dictionary:
	if _table == null:
		return _failure("not_configured")
	var transaction_id := "recipe/%s/%d" % [_nonce, _next_serial]
	var plan := _plan(recipe_id, instance_ids, source_id, facts, transaction_id)
	if not bool(plan.get("ok", false)):
		return plan
	var locks := _lock_map()
	for id: String in instance_ids:
		if locks.has(id) and _live_owner(locks[id]) != null:
			return _failure("instance_locked")
	if _table.transaction_receipts.has(transaction_id):
		return _failure("transaction_id_already_used")
	_next_serial += 1
	var job: Dictionary = plan.job
	_jobs[transaction_id] = job
	_acquire_locks(job)
	return {"ok": true, "job_id": transaction_id, "transaction_id": transaction_id, "source_position": job.source_position}


func matching_recipes(instance_ids: Array[String], facts: Array[String] = []) -> Array[String]:
	var matches: Array[String] = []
	if _table == null or instance_ids.is_empty():
		return matches
	var definitions: Array[String] = []
	for card_id: String in instance_ids:
		if not _table.cards.has(card_id):
			return matches
		var definition := _table.definition_id_for_card(card_id)
		if definition.is_empty():
			return matches
		definitions.append(definition)
	definitions.sort()
	var candidate_ids: Array = _recipes_by_participants.get(JSON.stringify(definitions), [])
	for id: String in candidate_ids:
		var duplicate_unique := false
		for output: Dictionary in _recipes[id].outputs:
			if not _table.content_card_definition(output.card_id).get("unique", false):
				continue
			for card_id: String in _table.cards:
				if _table.definition_id_for_card(card_id) == output.card_id:
					duplicate_unique = true
					break
		if duplicate_unique:
			continue
		if _plan(id, instance_ids, instance_ids[0], facts, "query").get("ok", false):
			matches.append(id)
	matches.sort()
	return matches


func _recipe_participants_key(recipe: Dictionary) -> String:
	var definitions: Array[String] = []
	for rule: Dictionary in recipe.inputs:
		for count in int(rule.count):
			definitions.append(String(rule.card_id))
	for rule: Dictionary in recipe.reusable:
		for count in int(rule.count):
			definitions.append(String(rule.card_id))
	definitions.sort()
	return JSON.stringify(definitions)


func advance(delta: float, suspended: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if _table == null:
		return events
	if not is_finite(delta) or delta < 0.0:
		events.append(_failure("invalid_delta"))
		return events
	for key: Variant in _jobs.keys():
		var id := str(key)
		if not _jobs.has(id):
			continue
		var job: Dictionary = _jobs[id]
		if _table.transaction_receipts.has(id):
			_release_job_locks(job)
			_jobs.erase(id)
			_terminal[id] = _table.transaction_receipts[id].duplicate(true)
			events.append({"ok": true, "status": "already_recorded", "transaction_id": id})
			continue
		var error := _live_job_error(job)
		if not error.is_empty():
			events.append(_cancel(id, error))
			continue
		job.source_position = _table.card_position(str(job.source_id))
		if suspended:
			continue
		var duration := float(_recipes[job.recipe_id].duration)
		job.elapsed = minf(float(job.elapsed) + delta, duration)
		if float(job.elapsed) < duration:
			continue
		var result := _commit(job)
		if str(result.get("error", "")) == "capacity_exceeded":
			job.state = "waiting_for_capacity"
			continue
		if not bool(result.get("ok", false)):
			events.append(_cancel(id, str(result.get("error", "commit_failed"))))
			continue
		_release_job_locks(job)
		_jobs.erase(id)
		_terminal[id] = _table.transaction_receipts[id].duplicate(true)
		events.append(result)
		job_committed.emit(result.duplicate(true))
	return events


func cancel(job_id: String) -> Dictionary:
	if not _jobs.has(job_id):
		return _failure("unknown_active_job")
	return _cancel(job_id, "cancelled_by_caller")


func get_job(job_id: String) -> Dictionary:
	return _jobs.get(job_id, {}).duplicate(true)


func active_jobs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for job: Dictionary in _jobs.values():
		result.append(job.duplicate(true))
	return result


func to_data() -> Dictionary:
	if _table == null:
		return _failure("not_configured")
	var jobs: Array[Dictionary] = []
	for job: Dictionary in _jobs.values():
		var saved: Dictionary = job.duplicate(true)
		var position: Vector2 = job.source_position
		if _table.cards.has(str(job.source_id)):
			position = _table.card_position(str(job.source_id))
		saved.source_position = [position.x, position.y]
		jobs.append(saved)
	return json_value({"version": SAVE_VERSION, "recipe_digest": _recipe_digest,
		"table_digest": _table_digest(), "nonce": _nonce,
		"next_serial": _next_serial, "jobs": jobs, "terminal": _terminal.duplicate(true)})


func restore(data: Dictionary) -> Dictionary:
	if _table == null:
		return _failure("not_configured")
	if not _integer(data.get("version"), SAVE_VERSION, SAVE_VERSION):
		return _failure("invalid_save_version")
	if data.get("recipe_digest") != _recipe_digest:
		return _failure("recipe_configuration_mismatch")
	if data.get("table_digest") != _table_digest():
		return _failure("table_snapshot_mismatch")
	if not data.get("nonce") is String or str(data.nonce).is_empty() or str(data.nonce).contains("/"):
		return _failure("invalid_nonce")
	if not _integer(data.get("next_serial"), 1, 2147483647):
		return _failure("invalid_next_serial")
	if not data.get("jobs") is Array or not data.get("terminal") is Dictionary:
		return _failure("invalid_save_collections")
	var incoming: Dictionary = {}
	var claimed: Dictionary = {}
	var prefix := "recipe/%s/" % str(data.nonce)
	# 本地 terminal 可以只含当前会话历史，但编号不能退到棋盘已经登记的事务之前。
	for recorded_id: Variant in _table.transaction_receipts:
		if recorded_id is String and recorded_id.begins_with(prefix) and not _transaction_id_valid(recorded_id, prefix, int(data.next_serial)):
			return _failure("saved_serial_precedes_table_receipt")
	var locks := _lock_map()
	for raw: Variant in data.jobs:
		if not raw is Dictionary:
			return _failure("invalid_saved_job")
		var saved: Dictionary = raw
		var id := str(saved.get("transaction_id", ""))
		if not _transaction_id_valid(id, prefix, int(data.next_serial)) or incoming.has(id) or data.terminal.has(id):
			return _failure("invalid_or_duplicate_transaction")
		if _table.transaction_receipts.has(id):
			return _failure("active_transaction_already_recorded")
		if not _string_array(saved.get("participant_ids")) or not _string_array(saved.get("facts")):
			return _failure("invalid_saved_instances_or_facts")
		var ids: Array[String] = []
		ids.assign(saved.participant_ids)
		var facts: Array[String] = []
		facts.assign(saved.facts)
		var plan := _plan(str(saved.get("recipe_id", "")), ids, str(saved.get("source_id", "")), facts, id)
		if not bool(plan.get("ok", false)):
			return _failure("saved_job_no_longer_valid")
		var fresh: Dictionary = plan.job
		for field: String in ["original_definitions", "membership_revisions", "input_instance_ids", "reusable_instance_ids", "stack_id", "transformed_instance_id"]:
			if field == "membership_revisions":
				if not _same_revisions(saved.get(field), fresh[field]):
					return _failure("saved_job_revision_mismatch")
			elif not saved.has(field) or _digest(saved[field]) != _digest(fresh[field]):
				return _failure("saved_job_identity_mismatch")
		if not _number(saved.get("elapsed")) or float(saved.elapsed) < 0.0:
			return _failure("invalid_saved_elapsed")
		var duration := float(_recipes[fresh.recipe_id].duration)
		var persisted_elapsed := float(json_value(float(saved.elapsed)))
		var persisted_duration := float(json_value(duration))
		if persisted_elapsed > persisted_duration:
			return _failure("invalid_saved_elapsed")
		if saved.get("state") not in ["running", "waiting_for_capacity"]:
			return _failure("invalid_saved_state")
		if saved.state == "waiting_for_capacity" and persisted_elapsed != persisted_duration:
			return _failure("premature_capacity_wait")
		if not _position_array(saved.get("source_position")):
			return _failure("invalid_saved_position")
		var saved_position := Vector2(float(saved.source_position[0]), float(saved.source_position[1]))
		if not saved_position.is_equal_approx(fresh.source_position):
			return _failure("saved_source_position_mismatch")
		for card_id: String in ids:
			if claimed.has(card_id):
				return _failure("saved_instance_locked_twice")
			if locks.has(card_id):
				var owner: Object = _live_owner(locks[card_id])
				if owner != null and owner != self:
					return _failure("instance_locked_by_other_runner")
			claimed[card_id] = true
		# 同一规范化末刻可能向上或向下舍入；恢复原末刻，不能让容量等待多等一帧。
		fresh.elapsed = duration if persisted_elapsed == persisted_duration else float(saved.elapsed)
		fresh.state = str(saved.state)
		incoming[id] = fresh
	for terminal_id: Variant in data.terminal:
		if not terminal_id is String or not _transaction_id_valid(terminal_id, prefix, int(data.next_serial)):
			return _failure("invalid_terminal_id")
		if not _table.transaction_receipts.has(terminal_id) or _digest(data.terminal[terminal_id]) != _digest(_table.transaction_receipts[terminal_id]):
			return _failure("terminal_receipt_mismatch")
	_release_all_locks()
	_jobs = incoming
	_terminal = data.terminal.duplicate(true)
	_nonce = str(data.nonce)
	_next_serial = int(data.next_serial)
	for job: Dictionary in _jobs.values():
		_acquire_locks(job)
	return {"ok": true, "active_jobs": _jobs.size()}


func _recipe_error(id: String, recipe: Dictionary, context_table: TableState = null) -> String:
	if id.is_empty() or recipe.get("id") != id:
		return "recipe_id_mismatch"
	if recipe.get("action") not in ["craft", "transform"]:
		return "unsupported_action"
	if not _number(recipe.get("duration")) or float(recipe.duration) <= 0.0:
		return "invalid_duration"
	for field: String in ["inputs", "reusable", "outputs"]:
		var rules := _rule_counts(recipe.get(field), context_table)
		if not bool(rules.get("ok", false)):
			return "invalid_" + field
	if not _string_array(recipe.get("requires_facts", [])) or not _string_array(recipe.get("grants_facts", [])):
		return "invalid_facts"
	var inputs: Dictionary = _rule_counts(recipe.inputs, context_table).counts
	var reusable: Dictionary = _rule_counts(recipe.reusable, context_table).counts
	if not recipe.get("reusable_conditions", []) is Array:
		return "invalid_reusable_conditions"
	var conditioned := {}
	for condition: Variant in recipe.get("reusable_conditions", []):
		if not condition is Dictionary or condition.size() != 2 or not condition.get("card_id") is String or not condition.get("bound_sigil") is String:
			return "invalid_reusable_condition"
		if int(reusable.get(condition.card_id, 0)) != 1 or conditioned.has(condition.card_id):
			return "ambiguous_reusable_condition"
		conditioned[condition.card_id] = true
		var sigil := _content_definition(condition.bound_sigil, context_table)
		var binding_context := context_table if context_table != null else _table
		if "sigil" not in sigil.get("tags", []) or not TableState.sigil_definition_compatible(condition.bound_sigil, condition.card_id, binding_context):
			return "incompatible_reusable_sigil"
	if _sum_counts(_rule_counts(recipe.outputs, context_table).counts) > TableState.MAX_CARDS:
		return "too_many_outputs"
	if inputs.is_empty() and reusable.is_empty():
		return "no_participants"
	if _sum_counts(inputs) + _sum_counts(reusable) > TableState.MAX_STACK:
		return "too_many_participants"
	if recipe.action == "transform":
		if not recipe.get("transform") is Dictionary:
			return "missing_transform"
		var transform: Dictionary = recipe.transform
		if not transform.get("from") is String or not transform.get("to") is String:
			return "invalid_transform_identity"
		if int(reusable.get(transform.from, 0)) != 1 or _content_definition(transform.to, context_table).is_empty():
			return "invalid_transform_reusable"
		if not _state_map(transform.get("require_metadata", {})) or not _state_map(transform.get("set_metadata", {})):
			return "unsupported_transform_metadata"
		if transform.from == transform.to:
			var required: Dictionary = transform.get("require_metadata", {})
			var changed: Dictionary = transform.get("set_metadata", {})
			if not required.has("state") or not changed.has("state") or required.state == changed.state:
				return "transform_does_not_change_state"
		if _rule_counts(recipe.outputs, context_table).counts.has(transform.to):
			return "transform_output_would_duplicate_instance"
	return ""


func _plan(recipe_id: String, ids: Array[String], source_id: String, facts: Array[String], transaction_id: String) -> Dictionary:
	if not _recipes.has(recipe_id):
		return _failure("unknown_recipe")
	if ids.is_empty() or source_id not in ids or not _string_array(ids) or not _string_array(facts):
		return _failure("invalid_participants_or_source")
	var recipe: Dictionary = _recipes[recipe_id]
	if not _recipe_error(recipe_id, recipe).is_empty():
		return _failure("recipe_definitions_unavailable")
	for fact: String in recipe.get("requires_facts", []):
		if fact not in facts:
			return _failure("missing_required_fact")
	var stack_id := _table.stack_for(source_id)
	if stack_id.is_empty() or not _table.stacks.has(stack_id):
		return _failure("source_not_on_board")
	var actual: Dictionary = {}
	var definitions: Dictionary = {}
	var revisions: Dictionary = {}
	for id: String in ids:
		if not _table.cards.has(id) or _table.stack_for(id) != stack_id:
			return _failure("participants_not_combined")
		var definition := _table.definition_id_for_card(id)
		if definition.is_empty():
			return _failure("unknown_card_definition")
		actual[definition] = int(actual.get(definition, 0)) + 1
		definitions[id] = definition
		revisions[id] = _table.membership_revision_for_card(id)
	var stack_cards: Array = _table.stacks[stack_id].cards
	if stack_cards.size() != ids.size():
		return _failure("extra_cards_in_stack")
	var expected: Dictionary = _rule_counts(recipe.inputs).counts.duplicate()
	var reusable_counts: Dictionary = _rule_counts(recipe.reusable).counts
	for definition: String in reusable_counts:
		expected[definition] = int(expected.get(definition, 0)) + int(reusable_counts[definition])
	if _digest(actual) != _digest(expected):
		return _failure("multiset_mismatch")
	if not _reusable_conditions_match(recipe, ids):
		return _failure("reusable_condition_not_met")
	var reusable_ids: Array[String] = []
	var transformed_id := ""
	if recipe.action == "transform":
		for id: String in ids:
			if definitions[id] == recipe.transform.from and _transform_state_matches(id, recipe.transform):
				transformed_id = id
				reusable_ids.append(id)
				break
		if transformed_id.is_empty():
			return _failure("transform_state_mismatch")
	for definition: String in reusable_counts:
		var needed := int(reusable_counts[definition])
		for id: String in reusable_ids:
			if definitions[id] == definition:
				needed -= 1
		for id: String in ids:
			if needed > 0 and definitions[id] == definition and id not in reusable_ids:
				reusable_ids.append(id)
				needed -= 1
	var input_ids: Array[String] = []
	for id: String in ids:
		if id not in reusable_ids:
			input_ids.append(id)
	return {"ok": true, "job": {"transaction_id": transaction_id, "recipe_id": recipe_id,
		"participant_ids": ids.duplicate(), "source_id": source_id, "stack_id": stack_id,
		"original_definitions": definitions, "membership_revisions": revisions,
		"input_instance_ids": input_ids, "reusable_instance_ids": reusable_ids,
		"transformed_instance_id": transformed_id, "facts": facts.duplicate(),
		"source_position": _table.card_position(source_id), "elapsed": 0.0, "state": "running"}}


func _live_job_error(job: Dictionary) -> String:
	if not _recipe_error(str(job.recipe_id), _recipes[job.recipe_id]).is_empty():
		return "recipe_definitions_unavailable"
	for id: String in job.participant_ids:
		if not _table.cards.has(id):
			return "participant_removed"
		if _table.definition_id_for_card(id) != job.original_definitions[id]:
			return "participant_definition_changed"
		if _table.membership_revision_for_card(id) != int(job.membership_revisions[id]):
			return "combination_revision_changed"
		if _table.stack_for(id) != job.stack_id:
			return "participants_separated"
	if not _table.stacks.has(job.stack_id) or _table.stacks[job.stack_id].cards.size() != job.participant_ids.size():
		return "combination_changed"
	var recipe: Dictionary = _recipes[job.recipe_id]
	if not _reusable_conditions_match(recipe, job.participant_ids):
		return "reusable_condition_changed"
	if recipe.action == "transform" and not _transform_state_matches(job.transformed_instance_id, recipe.transform):
		return "transform_state_changed"
	return ""


func _reusable_conditions_match(recipe: Dictionary, ids: Array) -> bool:
	for condition: Dictionary in recipe.get("reusable_conditions", []):
		var matched := false
		for id: String in ids:
			if _table.definition_id_for_card(id) != condition.card_id:
				continue
			var sigil_id: String = _table.cards[id].metadata.get("bound_sigil", "")
			if not _table.cards.has(sigil_id) or _table.definition_id_for_card(sigil_id) != condition.bound_sigil:
				return false
			var sigil: Dictionary = _table.cards[sigil_id]
			if sigil.get("zone") != &"bound" or sigil.metadata.get("bound_to", "") != id:
				return false
			matched = true
		if not matched:
			return false
	return true


func _commit(job: Dictionary) -> Dictionary:
	var id := str(job.transaction_id)
	if _table.transaction_receipts.has(id):
		return _failure("transaction_already_recorded")
	var error := _live_job_error(job)
	if not error.is_empty():
		return _failure(error)
	var recipe: Dictionary = _recipes[job.recipe_id]
	var output_count := _sum_counts(_rule_counts(recipe.outputs).counts)
	if _table.card_count() - job.input_instance_ids.size() + output_count > TableState.MAX_CARDS:
		return _failure("capacity_exceeded")
	var candidate := _table.fork_empty()
	candidate.restore(_table.snapshot())
	var source: Vector2 = _table.card_position(str(job.source_id))
	for card_id: String in job.input_instance_ids:
		if not candidate.remove_card(card_id):
			return _failure("candidate_input_missing")
	if recipe.action == "transform":
		var changed_id := str(job.transformed_instance_id)
		if not candidate.replace_definition(changed_id, str(recipe.transform.to)):
			return _failure("candidate_transform_failed")
		var state_change: Dictionary = recipe.transform.get("set_metadata", {})
		if state_change.has("state"):
			candidate.cards[changed_id].metadata["state"] = state_change.state
	var output_ids: Array[String] = []
	for output: Dictionary in recipe.outputs:
		var remaining := int(output.count)
		while remaining > 0:
			var count := mini(remaining, TableState.MAX_STACK)
			var stack := candidate.create_defined(str(output.card_id), source, count)
			if stack.is_empty() or candidate.stacks[stack].cards.size() != count:
				return _failure("candidate_output_failed")
			for card_id: String in candidate.stacks[stack].cards:
				output_ids.append(card_id)
				candidate.cards[card_id].metadata["production_transaction_id"] = id
				candidate.cards[card_id].metadata["production_source_position"] = [source.x, source.y]
			remaining -= count
	if not candidate.validate().is_empty():
		return _failure("candidate_table_invalid")
	var result := {"ok": true, "status": "completed", "job_id": id, "transaction_id": id,
		"recipe_id": job.recipe_id, "recipe_fingerprint": canonical_digest(recipe), "source_id": job.source_id, "source_position": [source.x, source.y],
		"input_instance_ids": job.input_instance_ids.duplicate(), "reusable_instance_ids": job.reusable_instance_ids.duplicate(),
		"output_instance_ids": output_ids, "transformed_instance_id": job.transformed_instance_id,
		"grants_facts": recipe.get("grants_facts", []).duplicate()}
	candidate.transaction_receipts[id] = result.duplicate(true)
	_table.restore(candidate.snapshot())
	result.source_position = source
	return result


func _cancel(id: String, reason: String) -> Dictionary:
	var job: Dictionary = _jobs[id]
	var result := {"ok": true, "status": "cancelled", "job_id": id, "transaction_id": id,
		"recipe_id": job.recipe_id, "reason": reason, "grants_facts": []}
	if not _table.transaction_receipts.has(id):
		_table.transaction_receipts[id] = result.duplicate(true)
	_terminal[id] = _table.transaction_receipts[id].duplicate(true)
	_release_job_locks(job)
	_jobs.erase(id)
	job_cancelled.emit(result.duplicate(true))
	return result


func _transform_state_matches(id: String, transform: Dictionary) -> bool:
	if not _table.cards.has(id):
		return false
	var required: Dictionary = transform.get("require_metadata", {})
	var metadata: Dictionary = _table.cards[id].get("metadata", {})
	return not required.has("state") or metadata.get("state") == required.state


func _lock_map() -> Dictionary:
	if _table == null:
		return {}
	var locks: Dictionary = _table.get_meta(LOCK_META, {})
	for id: Variant in locks.keys():
		if _live_owner(locks[id]) == null:
			locks.erase(id)
	_table.set_meta(LOCK_META, locks)
	return locks


func _live_owner(entry: Variant) -> Object:
	if not entry is Dictionary or not entry.get("owner") is WeakRef:
		return null
	return entry.owner.get_ref()


func _acquire_locks(job: Dictionary) -> void:
	var locks := _lock_map()
	for id: String in job.participant_ids:
		locks[id] = {"owner": weakref(self), "job_id": job.transaction_id}
	_table.set_meta(LOCK_META, locks)


func _release_job_locks(job: Dictionary) -> void:
	var locks := _lock_map()
	for id: String in job.participant_ids:
		if locks.has(id) and _live_owner(locks[id]) == self and locks[id].job_id == job.transaction_id:
			locks.erase(id)
	_table.set_meta(LOCK_META, locks)


func _release_all_locks() -> void:
	if _table == null:
		return
	for job: Dictionary in _jobs.values():
		_release_job_locks(job)


func _rule_counts(value: Variant, context_table: TableState = null) -> Dictionary:
	if not value is Array:
		return _failure("rules_not_array")
	var counts: Dictionary = {}
	for raw: Variant in value:
		if not raw is Dictionary or not raw.get("card_id") is String or not _integer(raw.get("count"), 1, TableState.MAX_CARDS):
			return _failure("invalid_rule")
		var id := str(raw.card_id)
		if _content_definition(id, context_table).is_empty() or counts.has(id):
			return _failure("unknown_or_duplicate_definition")
		counts[id] = int(raw.count)
	return {"ok": true, "counts": counts}


func _content_definition(id: String, context_table: TableState = null) -> Dictionary:
	var source := context_table if context_table != null else _table
	return source.content_card_definition(id) if source != null else ContentCatalog.card_definition(id)


func _sum_counts(counts: Dictionary) -> int:
	var result := 0
	for count: Variant in counts.values():
		result += int(count)
	return result


func _same_revisions(saved: Variant, current: Dictionary) -> bool:
	if not saved is Dictionary or saved.size() != current.size():
		return false
	for id: String in current:
		if not saved.has(id) or not _number(saved[id]) or float(saved[id]) != float(current[id]):
			return false
	return true


func _state_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		if key != "state" or not value[key] is String or str(value[key]).is_empty():
			return false
	return true


func _string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not item is String or str(item).is_empty() or seen.has(item):
			return false
		seen[item] = true
	return true


func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum


func _position_array(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])


func _transaction_id_valid(id: String, prefix: String, next_serial: int) -> bool:
	if not id.begins_with(prefix):
		return false
	var suffix := id.trim_prefix(prefix)
	return suffix.is_valid_int() and str(int(suffix)) == suffix and int(suffix) > 0 and int(suffix) < next_serial


func _digest(value: Variant) -> String:
	return canonical_digest(value)


static func canonical_digest(value: Variant) -> String:
	return JSON.stringify(json_value(value), "", true, true).sha256_text()


static func json_value(value: Variant) -> Variant:
	# JSON 不保留 int/float 身份。Godot 解析十进制时还可能产生 float64 末位偏移，
	# 而 Vector2 恢复时会回到 binary32；收据中的同一坐标若仍留作 float64 就会分裂。
	# 持久化非整数统一到实际 Vector2 的 binary32 精度（最近偶数舍入，最多半个 ULP）。
	# binary32 后 abs(x)<=1e-6 规范为0：默认 JSON 的极小普通十进制解析会丢失有效位；该绝对
	# 下限远小于一个逻辑像素/一帧时间。不是摘要容差比较，所有字段仍逐字节严格哈希。
	# JSON 安全整数仍精确保留。已有开发档若目录指纹因此不同，应拒绝而非重写旧摘要。
	if value is StringName:
		return String(value)
	if value is Vector2:
		return [json_value(value.x), json_value(value.y)]
	if value is float and is_finite(value):
		if absf(value) <= float(9007199254740991) and floorf(value) == value:
			return int(value)
		var scalar: float = PackedFloat32Array([value])[0]
		# 超出可表示范围不生成 INF；各字段自己的范围校验继续负责拒绝该输入。
		if is_finite(scalar):
			if absf(scalar) <= 0.000001:
				return 0
			if absf(scalar) <= float(9007199254740991) and floorf(scalar) == scalar:
				return int(scalar)
			return scalar
	if value is Dictionary:
		var converted: Dictionary = {}
		for key: Variant in value:
			converted[String(key)] = json_value(value[key])
		return converted
	if value is Array:
		var converted: Array = []
		for item: Variant in value:
			converted.append(json_value(item))
		return converted
	return value


func _table_digest() -> String:
	var snapshot := _table.snapshot()
	# 分配计数只增不减，载入旧联合快照时可高于保存值；实例、堆叠与收据仍须精确相同。
	for field: String in ["next_card_id", "next_stack_id", "next_z"]:
		snapshot.erase(field)
	return _digest(snapshot)


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
