class_name ChapterOperationRunner
extends RefCounted

const SHOP_QUEUE_STATE_FIELDS := ["chapter_arrival_remaining", "chapter_arrivals_day", "chapter_arrivals_today",
	"chapter_next_ticket", "chapter_sales", "chapter_sale_records", "chapter_arrival_records"]

signal job_committed(result: Dictionary)
signal job_cancelled(result: Dictionary)

const RecipeRunner = preload("res://scripts/content/module_recipe_runner.gd")
const Story = preload("res://scripts/content/module_story_session.gd")
const Sigils = preload("res://scripts/content/module_sigil_bindings.gd")
const RECEIPT_KIND := "chapter_operation"
const LOCK_META := &"module_recipe_runtime_locks"
const VERSION := 1
const RESERVED_METADATA := ["definition_id", "module_id", "membership_revision", "bound_to", "bound_sigil", "production_transaction_id", "production_source_position"]

var _table: TableState
var _story: Story
var _ops: Dictionary = {}
var _jobs: Dictionary = {}
var _terminal: Dictionary = {}
var _catalog_fingerprint := ""
var _nonce := ""
var _next_serial := 1
var _generation := 0
var _emitting := false
var _workbench_policy: Variant = null


func configure(table: TableState, story_session: Story, ops: Dictionary, workbench_policy: Variant = null) -> Dictionary:
	if _emitting or not _jobs.is_empty():
		return _failure("operation_runner_busy")
	if table == null or story_session == null or story_session.to_data().catalog_fingerprint.is_empty():
		return _failure("operation_context_missing")
	if not table.validate().is_empty():
		return _failure("invalid_table")
	var policy_error := validate_workbench_policy(workbench_policy, ops)
	if not policy_error.is_empty():
		return _failure(policy_error)
	for id: Variant in ops:
		var error := _operation_error(id, ops[id], table, story_session)
		if not error.is_empty():
			return _failure(error)
	for id: Variant in table.transaction_receipts:
		var receipt: Variant = table.transaction_receipts[id]
		if receipt is Dictionary and receipt.get("kind") == RECEIPT_KIND:
			var error := validate_receipt(str(id), receipt, ops, table, story_session, workbench_policy)
			if not error.is_empty():
				return _failure(error)
	_release_all()
	_table = table
	_story = story_session
	_ops = ops.duplicate(true)
	_workbench_policy = workbench_policy.duplicate(true) if workbench_policy is Dictionary else null
	var fingerprint_context := {"ops": _ops, "story_catalog": _story.to_data().catalog_fingerprint}
	if _workbench_policy != null:
		fingerprint_context["workbench_policy"] = _workbench_policy
	_catalog_fingerprint = RecipeRunner.canonical_digest(fingerprint_context)
	_generation += 1
	_nonce = "%s_%s_%s" % [get_instance_id(), Time.get_ticks_usec(), _generation]
	_next_serial = 1
	_terminal.clear()
	return {"ok": true, "error": ""}


static func validate_catalog(ops: Dictionary, table: TableState, story_session: Story, workbench_policy: Variant = null) -> String:
	if table == null or story_session == null:
		return "operation_context_missing"
	for id: Variant in ops:
		var error := _operation_error(id, ops[id], table, story_session)
		if not error.is_empty():
			return error
	return validate_workbench_policy(workbench_policy, ops)


func begin(op_id: String, instance_ids: Array[String], facts: Array[String] = []) -> Dictionary:
	if _table == null or _emitting:
		return _failure("operation_runner_not_available")
	var tx := "operation/%s/%d" % [_nonce, _next_serial]
	var plan := _plan(op_id, instance_ids, facts, tx)
	if not plan.ok:
		return plan
	for id: String in plan.job.lock_ids:
		var locks := _lock_map()
		if locks.has(id) and _owner(locks[id]) != null:
			return _failure("instance_locked")
	var prepared := _build_candidate(plan.job)
	if not prepared.ok and prepared.get("error") != "capacity_exceeded":
		return _failure(str(prepared.error))
	_next_serial += 1
	_jobs[tx] = plan.job
	_acquire(plan.job)
	return {"ok": true, "job_id": tx, "transaction_id": tx, "source_position": plan.job.source_position}


func matching_operations(instance_ids: Array[String], facts: Array[String] = []) -> Array[String]:
	var result: Array[String] = []
	if _table == null or _emitting:
		return result
	var probe_started := HitchProbe.stamp()
	var actual: Dictionary = {}
	for card_id: String in instance_ids:
		if not _table.cards.has(card_id):
			return result
		var definition_id := _table.definition_id_for_card(card_id)
		actual[definition_id] = int(actual.get(definition_id, 0)) + 1
	var tx := "operation/%s/%d" % [_nonce, _next_serial]
	var locks: Dictionary = _table.get_meta(LOCK_META, {})
	for id: String in _ops:
		if _counts(_ops[id].participants) != actual:
			continue
		var plan := _plan(id, instance_ids, facts, tx)
		if not plan.ok:
			continue
		var blocked := false
		for card_id: String in plan.job.lock_ids:
			if locks.has(card_id) and _owner(locks[card_id]) != null:
				blocked = true
		if blocked:
			continue
		var candidate := _build_candidate(plan.job)
		if candidate.ok or candidate.get("error") == "capacity_exceeded":
			result.append(id)
	result.sort()
	HitchProbe.record("operation_match", probe_started)
	return result


func advance(delta: float, suspended: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if _table == null or _emitting:
		return events
	if not is_finite(delta) or delta < 0:
		return [_failure("invalid_delta")]
	for tx: String in _jobs.keys():
		if not _jobs.has(tx):
			continue
		var job: Dictionary = _jobs[tx]
		if _table.transaction_receipts.has(tx):
			_release(job)
			_jobs.erase(tx)
			_terminal[tx] = _table.transaction_receipts[tx].duplicate(true)
			events.append({"ok": true, "status": "already_recorded", "transaction_id": tx})
			continue
		var error := _live_error(job)
		if not error.is_empty():
			events.append(_cancel(tx, error))
			continue
		job.source_position = _table.card_position(job.origin_id)
		if suspended or _story.to_data().state.paused:
			continue
		var duration := _job_duration(job)
		job.elapsed = minf(float(job.elapsed) + delta, duration)
		if float(job.elapsed) < duration:
			continue
		var built := _build_candidate(job)
		if not built.ok:
			if built.error == "capacity_exceeded":
				job.state = "waiting_for_capacity"
			else:
				events.append(_cancel(tx, str(built.error)))
			continue
		_table.restore(built.table.snapshot())
		_release(job)
		_jobs.erase(tx)
		_terminal[tx] = built.receipt.duplicate(true)
		var result: Dictionary = built.receipt.duplicate(true)
		result["ok"] = true
		events.append(result)
		_emitting = true
		job_committed.emit(result.duplicate(true))
		_emitting = false
	return events


func cancel(transaction_id: String) -> Dictionary:
	if _emitting or not _jobs.has(transaction_id):
		return _failure("unknown_active_operation")
	return _cancel(transaction_id, "cancelled_by_caller")


func active_jobs() -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	for job: Dictionary in _jobs.values():
		jobs.append(job.duplicate(true))
	return jobs


func get_job(transaction_id: String) -> Dictionary:
	return _jobs.get(transaction_id, {}).duplicate(true)


func to_data() -> Dictionary:
	if _table == null or _emitting:
		return _failure("operation_runner_not_available")
	var jobs := active_jobs()
	for job: Dictionary in jobs:
		if _table.cards.has(job.origin_id):
			job.source_position = _table.card_position(job.origin_id)
	return RecipeRunner.json_value({"version": VERSION, "catalog_fingerprint": _catalog_fingerprint,
		"table_digest": _table_digest(), "nonce": _nonce, "next_serial": _next_serial, "jobs": jobs, "terminal": _terminal.duplicate(true)})


func restore(data: Variant) -> Dictionary:
	if _table == null or _emitting:
		return _failure("operation_runner_not_available")
	if not _fields(data, ["version", "catalog_fingerprint", "table_digest", "nonce", "next_serial", "jobs", "terminal"]):
		return _failure("invalid_operation_checkpoint_fields")
	if not _integer(data.version, VERSION, VERSION) or data.catalog_fingerprint != _catalog_fingerprint or data.table_digest != _table_digest():
		return _failure("operation_checkpoint_context_mismatch")
	if not data.nonce is String or data.nonce.is_empty() or data.nonce.contains("/") or not _integer(data.next_serial, 1, 2147483647) or not data.jobs is Array or not data.terminal is Dictionary:
		return _failure("invalid_operation_checkpoint_identity")
	var prefix := "operation/%s/" % str(data.nonce)
	var incoming: Dictionary = {}
	var claimed: Dictionary = {}
	for id: Variant in _table.transaction_receipts:
		if id is String and id.begins_with(prefix) and _table.transaction_receipts[id].get("kind") == RECEIPT_KIND and not _own_transaction(id, prefix, int(data.next_serial)):
			return _failure("operation_serial_precedes_ledger")
	for saved: Variant in data.jobs:
		var job_fields := ["transaction_id", "operation_id", "participant_ids", "stack_id", "tracked_cards", "lock_ids", "facts", "source_id", "origin_id", "source_position", "elapsed", "state"]
		if _workbench_policy != null:
			job_fields.append("execution_profile")
		if not _fields(saved, job_fields):
			return _failure("invalid_saved_operation_job")
		var tx: Variant = saved.transaction_id
		if not tx is String or not _own_transaction(tx, prefix, int(data.next_serial)) or incoming.has(tx) or data.terminal.has(tx) or _table.transaction_receipts.has(tx):
			return _failure("invalid_or_already_recorded_operation")
		if not _strings(saved.participant_ids, false) or not _strings(saved.facts):
			return _failure("invalid_operation_saved_lists")
		var ids: Array[String] = []
		ids.assign(saved.participant_ids)
		var facts: Array[String] = []
		facts.assign(saved.facts)
		var plan := _plan(str(saved.operation_id), ids, facts, tx)
		if not plan.ok:
			return _failure("saved_operation_no_longer_valid: " + str(plan.error))
		var job: Dictionary = plan.job
		if _workbench_policy != null:
			var profile_error := _profile_error(saved.execution_profile, _ops[job.operation_id], _workbench_policy, _ops, _table, _story)
			if not profile_error.is_empty():
				return _failure(profile_error)
			job.execution_profile = saved.execution_profile.duplicate(true)
		for field: String in ["stack_id", "tracked_cards", "lock_ids", "source_id", "origin_id"]:
			if RecipeRunner.canonical_digest(saved[field]) != RecipeRunner.canonical_digest(job[field]):
				return _failure("saved_operation_participant_changed")
		if not _number(saved.elapsed) or float(saved.elapsed) < 0 or saved.state not in ["running", "waiting_for_capacity"]:
			return _failure("invalid_saved_operation_progress")
		var duration := _job_duration(job)
		var normalized_elapsed := float(RecipeRunner.json_value(float(saved.elapsed)))
		var normalized_duration := float(RecipeRunner.json_value(duration))
		if normalized_elapsed > normalized_duration:
			return _failure("invalid_saved_operation_progress")
		if saved.state == "waiting_for_capacity" and normalized_elapsed != normalized_duration:
			return _failure("premature_operation_capacity_wait")
		if not _position(saved.source_position) or not Vector2(float(saved.source_position[0]), float(saved.source_position[1])).is_equal_approx(job.source_position):
			return _failure("saved_operation_source_mismatch")
		for id: String in job.lock_ids:
			if claimed.has(id) or _foreign_lock(id):
				return _failure("operation_restore_instance_locked")
			claimed[id] = true
		job.elapsed = duration if normalized_elapsed == normalized_duration else float(saved.elapsed)
		job.state = saved.state
		incoming[tx] = job
	for tx: Variant in data.terminal:
		if not tx is String or not _own_transaction(tx, prefix, int(data.next_serial)) or not _table.transaction_receipts.has(tx) or RecipeRunner.canonical_digest(data.terminal[tx]) != RecipeRunner.canonical_digest(_table.transaction_receipts[tx]):
			return _failure("operation_terminal_receipt_mismatch")
	_release_all()
	_jobs = incoming
	_terminal = data.terminal.duplicate(true)
	_nonce = data.nonce
	_next_serial = int(data.next_serial)
	for job: Dictionary in _jobs.values():
		_acquire(job)
	return {"ok": true, "active_jobs": _jobs.size()}


func _plan(op_id: String, ids: Array[String], facts: Array[String], tx: String) -> Dictionary:
	if not _ops.has(op_id) or not _strings(ids, false) or not _strings(facts):
		return _failure("unknown_operation_or_invalid_participants")
	if not _table.validate().is_empty():
		return _failure("invalid_table")
	var op: Dictionary = _ops[op_id]
	var error := _prerequisite_error(op, facts)
	if not error.is_empty():
		return _failure(error)
	var counts: Dictionary = {}
	var refs: Dictionary = {}
	var stack := ""
	for id: String in ids:
		if not _table.cards.has(id) or _table.cards[id].zone != &"board":
			return _failure("operation_participant_not_on_board")
		var current_stack := _table.stack_for(id)
		if stack.is_empty():
			stack = current_stack
		if current_stack.is_empty() or current_stack != stack:
			return _failure("operation_participants_not_combined")
		var definition := _table.definition_id_for_card(id)
		counts[definition] = int(counts.get(definition, 0)) + 1
		refs[definition] = id
	if _table.stacks[stack].cards.size() != ids.size() or counts != _counts(op.participants):
		return _failure("operation_multiset_mismatch")
	for rule: Dictionary in op.consume:
		for id: String in ids:
			if _table.definition_id_for_card(id) == rule.card_id and (_table.cards[id].metadata.has("bound_sigil") or _table.cards[id].metadata.has("npc_id")):
				return _failure("cannot_consume_bound_carrier_or_npc")
	for condition: Dictionary in op.requires_metadata:
		var metadata := _reference_metadata(condition.card_id, refs, op)
		for key: String in condition.values:
			if key == "bound_sigil_definition_id":
				if _bound_sigil_definition(str(refs.get(condition.card_id, ""))) != condition.values[key]:
					return _failure("required_bound_sigil_mismatch")
				continue
			if metadata.get(key) != condition.values[key]:
				return _failure("required_metadata_mismatch")
	for transform: Dictionary in op.transforms:
		var metadata := _reference_metadata(transform.card_id, refs, op)
		if not transform.require_state.is_empty() and metadata.get("state") != transform.require_state:
			return _failure("required_transform_state_mismatch")
		if transform.card_id == transform.to_card_id and metadata.get("state", "") == transform.set_state:
			return _failure("transform_already_applied")
	var locks: Array[String] = ids.duplicate()
	for condition: Dictionary in op.requires_metadata:
		if condition.values.has("bound_sigil_definition_id") and refs.has(condition.card_id):
			var bound_id: String = _table.cards[refs[condition.card_id]].metadata.get("bound_sigil", "")
			if not bound_id.is_empty() and bound_id not in locks:
				locks.append(bound_id)
	for effect: Dictionary in op.sigil_effects:
		for id: String in _table.cards:
			if _table.definition_id_for_card(id) == effect.sigil_definition_id:
				if _table.cards[id].zone == &"board" and id not in ids:
					return _failure("loose_sigil_must_participate")
				if id not in locks:
					locks.append(id)
	locks.sort()
	var tracked: Dictionary = {}
	for id: String in locks:
		tracked[id] = {"definition_id": _table.definition_id_for_card(id), "zone": str(_table.cards[id].zone),
			"membership_revision": _table.membership_revision_for_card(id), "metadata": _operation_metadata(id)}
	var source_id: String = refs.get(op.source_card_id, "")
	var origin_id: String = source_id if not source_id.is_empty() else str(refs.get("card.hero", ids[0]))
	var job := {"transaction_id": tx, "operation_id": op_id, "participant_ids": ids.duplicate(),
		"stack_id": stack, "tracked_cards": tracked, "lock_ids": locks, "facts": facts.duplicate(),
		"source_id": source_id, "origin_id": origin_id, "source_position": _table.card_position(origin_id), "elapsed": 0.0, "state": "running"}
	if _workbench_policy != null:
		job["execution_profile"] = _make_profile(op)
	return {"ok": true, "job": job}


func _prerequisite_error(op: Dictionary, supplied_facts: Array) -> String:
	for required: String in op.requires_stories:
		if required not in _story.to_data().state.completed:
			return "required_story_not_completed"
	var facts := supplied_facts.duplicate()
	for fact: String in _story.to_data().state.facts:
		if fact not in facts:
			facts.append(fact)
	for receipt: Variant in _table.transaction_receipts.values():
		if not receipt is Dictionary:
			return "invalid_operation_ledger_entry"
		if receipt is Dictionary and receipt.get("kind") == RECEIPT_KIND and receipt.get("status") == "completed":
			var receipt_error := validate_receipt(str(receipt.get("transaction_id", "")), receipt, _ops, _table, _story, _workbench_policy)
			if not receipt_error.is_empty():
				return "invalid_operation_ledger: " + receipt_error
			if receipt.operation_id == op.id and not op.repeatable:
				return "one_time_operation_already_completed"
			for fact: String in receipt.grants_facts:
				if fact not in facts:
					facts.append(fact)
	for fact: String in op.requires_facts:
		if fact not in facts:
			return "required_fact_missing"
	for fact: String in op.forbidden_facts:
		if fact in facts:
			return "forbidden_fact_present"
	return ""


func _live_error(job: Dictionary) -> String:
	if not _table.validate().is_empty():
		return "operation_table_became_invalid"
	var error := _prerequisite_error(_ops[job.operation_id], job.facts)
	if not error.is_empty():
		return error
	if _workbench_policy != null:
		error = _profile_error(job.execution_profile, _ops[job.operation_id], _workbench_policy, _ops, _table, _story)
		if not error.is_empty():
			return error
	if not _table.stacks.has(job.stack_id) or _table.stacks[job.stack_id].cards.size() != job.participant_ids.size():
		return "operation_combination_changed"
	for id: String in job.participant_ids:
		if _table.stack_for(id) != job.stack_id:
			return "operation_participants_separated"
	for id: String in job.lock_ids:
		if not _table.cards.has(id):
			return "operation_participant_removed"
		var now := {"definition_id": _table.definition_id_for_card(id), "zone": str(_table.cards[id].zone),
			"membership_revision": _table.membership_revision_for_card(id), "metadata": _operation_metadata(id)}
		if RecipeRunner.canonical_digest(now) != RecipeRunner.canonical_digest(job.tracked_cards[id]):
			return "operation_participant_revision_or_state_changed"
	return ""


func _operation_metadata(card_id: String) -> Dictionary:
	var metadata: Dictionary = _table.cards[card_id].metadata.duplicate(true)
	if _table.definition_id_for_card(card_id) == "card.shop":
		# 排队计时、顾客票号与收款会变化，但不改变参与工序的实体商店状态。
		for key: String in SHOP_QUEUE_STATE_FIELDS:
			metadata.erase(key)
	return metadata


# 预检与正式完成都在隔离候选表执行；只有 advance 成功时才将整份候选一次提交。
func _build_candidate(job: Dictionary) -> Dictionary:
	var op: Dictionary = _ops[job.operation_id]
	var sigil_grants := 0
	for effect: Dictionary in op.sigil_effects:
		if effect.action == "grant_bound":
			sigil_grants += 1
	if _table.card_count() - _total(op.consume) + _total(op.creates) + sigil_grants > TableState.MAX_CARDS:
		return _failure("capacity_exceeded")
	var candidate := _table.fork_empty()
	candidate.restore(_table.snapshot())
	var source := _table.card_position(job.origin_id)
	var refs: Dictionary = {}
	for id: String in job.participant_ids:
		refs[candidate.definition_id_for_card(id)] = id
	var consumed: Array[String] = []
	for rule: Dictionary in op.consume:
		var remaining := int(rule.count)
		for id: String in job.participant_ids:
			if remaining > 0 and candidate.cards.has(id) and candidate.definition_id_for_card(id) == rule.card_id:
				if candidate.cards[id].metadata.has("bound_sigil") or candidate.cards[id].metadata.has("npc_id") or not candidate.remove_card(id):
					return _failure("candidate_consumption_refused")
				consumed.append(id)
				remaining -= 1
	var created: Array[String] = []
	for grant: Dictionary in op.creates:
		if grant.metadata.has("npc_id"):
			for card: Dictionary in candidate.cards.values():
				if card.metadata.get("npc_id") == grant.metadata.npc_id:
					return _failure("created_npc_already_exists")
		var remaining := int(grant.count)
		while remaining > 0:
			var amount := mini(remaining, TableState.MAX_STACK)
			var stack := candidate.create_defined(grant.card_id, source, amount)
			if stack.is_empty():
				return _failure("candidate_creation_refused")
			for id: String in candidate.stacks[stack].cards:
				created.append(id)
				refs[grant.card_id] = id
				candidate.cards[id].metadata.merge(grant.metadata, true)
			remaining -= amount
	var sigil_error := _sigil_phase(candidate, job, refs, created, true)
	if not sigil_error.is_empty():
		return _failure(sigil_error)
	var transformed: Array[String] = []
	for transform: Dictionary in op.transforms:
		var id: String = refs.get(transform.card_id, "")
		if not candidate.cards.has(id) or (not transform.require_state.is_empty() and candidate.cards[id].metadata.get("state") != transform.require_state):
			return _failure("candidate_transform_state_mismatch")
		if not candidate.replace_definition(id, transform.to_card_id):
			return _failure("candidate_transform_refused")
		if not transform.set_state.is_empty():
			candidate.cards[id].metadata.state = transform.set_state
		transformed.append(id)
	sigil_error = _sigil_phase(candidate, job, refs, created, false)
	if not sigil_error.is_empty():
		return _failure(sigil_error)
	for id: String in created:
		candidate.cards[id].metadata.production_transaction_id = job.transaction_id
		candidate.cards[id].metadata.production_source_position = [source.x, source.y]
	for id: String in candidate.cards:
		var metadata: Dictionary = candidate.cards[id].metadata
		if metadata.has("npc_id") and candidate.content_npc_definition(metadata.npc_id).get("card_id") != candidate.definition_id_for_card(id):
			return _failure("candidate_npc_identity_mismatch")
	var source_id: String = str(refs.get(op.source_card_id, job.source_id))
	var receipt := {"kind": RECEIPT_KIND, "version": VERSION, "operation_id": op.id,
		"operation_fingerprint": RecipeRunner.canonical_digest(op), "transaction_id": job.transaction_id, "status": "completed",
		"participant_ids": job.participant_ids.duplicate(), "consumed_ids": consumed, "created_ids": created,
		"transformed_ids": transformed, "grants_facts": op.grants_facts.duplicate(), "source_id": source_id, "source_position": [source.x, source.y]}
	if job.has("execution_profile"):
		receipt.version = 2
		receipt["execution_profile"] = job.execution_profile.duplicate(true)
	candidate.transaction_receipts[job.transaction_id] = receipt
	var error := candidate.validate()
	if error.is_empty():
		error = validate_receipt(job.transaction_id, receipt, _ops, candidate, _story, _workbench_policy)
	if not error.is_empty():
		return _failure("candidate_operation_invalid: " + error)
	return {"ok": true, "table": candidate, "receipt": receipt}


# 先拆出，再原实例转态，最后绑定；同印的拆与绑用一项 transfer 表达。
func _sigil_phase(candidate: TableState, job: Dictionary, refs: Dictionary, created: Array[String], detaching: bool) -> String:
	var effects: Array = _ops[job.operation_id].sigil_effects
	var sigils := Sigils.new()
	if not sigils.configure(candidate).ok:
		return "candidate_sigil_context_invalid"
	for index in effects.size():
		var effect: Dictionary = effects[index]
		if detaching and effect.action not in ["unbind", "transfer"]:
			continue
		if not detaching and effect.action == "unbind":
			continue
		var sigil_id := ""
		for id: String in candidate.cards:
			if candidate.definition_id_for_card(id) == effect.sigil_definition_id:
				sigil_id = id
		var child_tx := str(job.transaction_id) + "/sigil/%d" % index
		var result: Dictionary
		if detaching:
			if sigil_id.is_empty() or candidate.cards[sigil_id].zone != &"bound" or candidate.cards[sigil_id].metadata.get("bound_to") != refs.get(effect.host_from):
				return "sigil_source_host_mismatch"
			result = sigils.unbind(sigil_id, child_tx + "/unbind")
		elif effect.action == "grant_bound":
			if not sigil_id.is_empty() or candidate.transaction_receipts.has(Sigils.GRANT_PREFIX + effect.event_id):
				return "sigil_grant_already_used"
			result = sigils.grant_bound(effect.event_id, effect.sigil_definition_id, str(refs.get(effect.host_to, "")))
			if result.ok:
				created.append(result.sigil_instance_id)
		else:
			if sigil_id.is_empty():
				return "required_sigil_missing"
			result = sigils.bind(sigil_id, str(refs.get(effect.host_to, "")), child_tx + "/bind")
		if not result.ok:
			return "candidate_sigil_effect_failed: " + str(result.error)
	return ""


func _cancel(tx: String, reason: String) -> Dictionary:
	var job: Dictionary = _jobs[tx]
	var receipt := {"kind": RECEIPT_KIND, "version": VERSION, "operation_id": job.operation_id,
		"operation_fingerprint": RecipeRunner.canonical_digest(_ops[job.operation_id]), "transaction_id": tx, "status": "cancelled",
		"participant_ids": job.participant_ids.duplicate(), "consumed_ids": [], "created_ids": [], "transformed_ids": [], "grants_facts": [],
		"source_id": job.source_id, "source_position": [job.source_position.x, job.source_position.y], "reason": reason}
	if job.has("execution_profile"):
		receipt.version = 2
		receipt["execution_profile"] = job.execution_profile.duplicate(true)
	_table.transaction_receipts[tx] = receipt.duplicate(true)
	_release(job)
	_jobs.erase(tx)
	_terminal[tx] = receipt.duplicate(true)
	var result := receipt.duplicate(true)
	result["ok"] = true
	_emitting = true
	job_cancelled.emit(result.duplicate(true))
	_emitting = false
	return result


static func validate_receipt(transaction_id: String, value: Variant, ops: Dictionary, table_context: TableState = null, story_session: Story = null, workbench_policy: Variant = null) -> String:
	var fields := ["kind", "version", "operation_id", "operation_fingerprint", "transaction_id", "status", "participant_ids", "consumed_ids", "created_ids", "transformed_ids", "grants_facts", "source_id", "source_position"]
	if value is Dictionary and value.get("status") == "cancelled":
		fields.append("reason")
	if value is Dictionary and value.get("version") == 2:
		fields.append("execution_profile")
	if not _fields(value, fields) or value.kind != RECEIPT_KIND or not _integer(value.version, 1, 2) or value.transaction_id != transaction_id or not _transaction_id(transaction_id):
		return "invalid_operation_receipt_identity"
	if not value.operation_id is String or not ops.has(value.operation_id) or value.operation_fingerprint != RecipeRunner.canonical_digest(ops[value.operation_id]):
		return "operation_receipt_catalog_mismatch"
	var op: Dictionary = ops[value.operation_id]
	if value.version == 2:
		var profile_error := _profile_error(value.execution_profile, op, workbench_policy, ops, table_context, story_session)
		if not profile_error.is_empty():
			return profile_error
	var validation_context := table_context if table_context != null else TableState.new()
	var definition_error := _operation_error(value.operation_id, op, validation_context, story_session)
	if not definition_error.is_empty():
		return definition_error
	for field: String in ["participant_ids", "consumed_ids", "created_ids", "transformed_ids", "grants_facts"]:
		if not _strings(value[field]):
			return "invalid_operation_receipt_lists"
	if value.participant_ids.size() != _total(op.participants) or not _position(value.source_position) or not value.source_id is String:
		return "invalid_operation_receipt_participants_or_source"
	if not TableState.WORLD_BOUNDS.encloses(Rect2(Vector2(float(value.source_position[0]), float(value.source_position[1])), TableState.CARD_SIZE)):
		return "operation_receipt_source_outside_board"
	var all_ids: Array = value.participant_ids + value.created_ids
	for id: String in all_ids:
		if not _card_id(id) or (table_context != null and int(id.trim_prefix("card_")) >= table_context.next_card_id):
			return "invalid_operation_receipt_instance"
	if value.status == "cancelled":
		if not value.reason is String or value.reason.is_empty() or not value.consumed_ids.is_empty() or not value.created_ids.is_empty() or not value.transformed_ids.is_empty() or not value.grants_facts.is_empty():
			return "cancelled_operation_has_consequences"
		return ""
	if value.status != "completed" or value.source_id not in all_ids or value.grants_facts != op.grants_facts or value.consumed_ids.size() != _total(op.consume) or value.transformed_ids.size() != op.transforms.size():
		return "operation_receipt_consequence_mismatch"
	if story_session != null:
		for required: String in op.requires_stories:
			if required not in story_session.to_data().state.completed:
				return "operation_receipt_required_story_missing"
	var grants := 0
	for effect: Dictionary in op.sigil_effects:
		if effect.action == "grant_bound":
			grants += 1
	if value.created_ids.size() != _total(op.creates) + grants:
		return "operation_receipt_creation_count_mismatch"
	for id: String in value.consumed_ids:
		if id not in value.participant_ids or id in value.created_ids or id in value.transformed_ids or (table_context != null and table_context.cards.has(id)):
			return "operation_consumed_instance_reappeared"
	for id: String in value.created_ids:
		if id in value.participant_ids:
			return "operation_created_instance_reused"
	for id: String in value.transformed_ids:
		if id not in all_ids:
			return "operation_transform_instance_missing"
	if table_context != null:
		for index in op.sigil_effects.size():
			var effect: Dictionary = op.sigil_effects[index]
			var child_ids: Array[String] = []
			if effect.action == "grant_bound":
				child_ids.append(Sigils.GRANT_PREFIX + effect.event_id)
			if effect.action in ["unbind", "transfer"]:
				child_ids.append(transaction_id + "/sigil/%d/unbind" % index)
			if effect.action in ["bind", "transfer"]:
				child_ids.append(transaction_id + "/sigil/%d/bind" % index)
			var transferred_sigil := ""
			for child_id: String in child_ids:
				if not table_context.transaction_receipts.has(child_id):
					return "operation_sigil_child_receipt_missing"
				var child: Variant = table_context.transaction_receipts[child_id]
				var child_error := Sigils.validate_receipt(child_id, child, table_context)
				if not child_error.is_empty():
					return "invalid_operation_sigil_child: " + child_error
				var expected_action := "grant_bound" if effect.action == "grant_bound" else child_id.get_slice("/", 5)
				if child.action != expected_action or child.sigil_definition_id != effect.sigil_definition_id or child.host_instance_id not in all_ids:
					return "operation_sigil_child_does_not_match"
				if effect.action == "grant_bound" and child.sigil_instance_id not in value.created_ids:
					return "operation_sigil_grant_not_recorded_as_created"
				if not transferred_sigil.is_empty() and transferred_sigil != child.sigil_instance_id:
					return "operation_transfer_changed_sigil_identity"
				transferred_sigil = child.sigil_instance_id
	return ""


static func validate_workbench_policy(policy: Variant, ops: Dictionary) -> String:
	if policy == null:
		return ""
	if not _fields(policy, ["version", "id", "unlock_operation_id", "modifiers"]) or not _integer(policy.version, 1, 1) or not policy.id is String or not policy.id.begins_with("service.") or not policy.unlock_operation_id is String or not ops.has(policy.unlock_operation_id) or not policy.modifiers is Dictionary or policy.modifiers.is_empty():
		return "invalid_workbench_policy"
	if policy.modifiers.has(policy.unlock_operation_id):
		return "workbench_cannot_discount_its_own_unlock"
	for id: Variant in policy.modifiers:
		var modifier: Variant = policy.modifiers[id]
		if not id is String or not ops.has(id) or not modifier is Dictionary or modifier.size() != 1:
			return "invalid_workbench_operation_modifier"
		if not ops[id] is Dictionary or not _number(ops[id].get("duration")):
			return "invalid_workbench_base_duration"
		var original := float(ops[id].duration)
		if modifier.has("duration_override"):
			if not _number(modifier.duration_override) or float(modifier.duration_override) <= 0 or float(modifier.duration_override) >= original:
				return "invalid_workbench_duration_override"
		elif modifier.has("duration_multiplier"):
			if not _number(modifier.duration_multiplier) or float(modifier.duration_multiplier) <= 0 or float(modifier.duration_multiplier) >= 1:
				return "invalid_workbench_duration_multiplier"
		else:
			return "unsupported_workbench_modifier"
		if float(RecipeRunner.json_value(_modified_duration(ops[id], policy))) <= 0:
			return "workbench_duration_below_persistence_precision"
	return ""


func _make_profile(op: Dictionary) -> Dictionary:
	var unlock := ""
	if _workbench_policy.modifiers.has(op.id):
		for tx: String in _table.transaction_receipts:
			var receipt: Dictionary = _table.transaction_receipts[tx]
			if receipt.get("kind") == RECEIPT_KIND and receipt.get("status") == "completed" and receipt.get("operation_id") == _workbench_policy.unlock_operation_id:
				unlock = tx
				break
	return {"version": 1, "operation_fingerprint": RecipeRunner.canonical_digest(op),
		"policy_fingerprint": RecipeRunner.canonical_digest(_workbench_policy), "original_duration": float(op.duration),
		"effective_duration": _modified_duration(op, _workbench_policy) if not unlock.is_empty() else float(op.duration),
		"unlock_transaction_id": unlock}


func _job_duration(job: Dictionary) -> float:
	if not job.has("execution_profile"):
		return float(_ops[job.operation_id].duration)
	# 方案先严格校验。回到同一目录的原double时长，避免序列化半ULP令末刻多等一帧。
	return float(_ops[job.operation_id].duration) if job.execution_profile.unlock_transaction_id.is_empty() else _modified_duration(_ops[job.operation_id], _workbench_policy)


static func _modified_duration(op: Dictionary, policy: Dictionary) -> float:
	var modifier: Dictionary = policy.modifiers[op.id]
	return float(modifier.duration_override) if modifier.has("duration_override") else float(op.duration) * float(modifier.duration_multiplier)


static func _profile_error(profile: Variant, op: Dictionary, policy: Variant, ops: Dictionary, table: TableState, story: Story) -> String:
	if policy == null:
		return "workbench_profile_context_missing"
	var error := validate_workbench_policy(policy, ops)
	if not error.is_empty():
		return error
	if not _fields(profile, ["version", "operation_fingerprint", "policy_fingerprint", "original_duration", "effective_duration", "unlock_transaction_id"]) or not _integer(profile.version, 1, 1) or not profile.unlock_transaction_id is String or not _number(profile.original_duration) or not _number(profile.effective_duration):
		return "invalid_workbench_execution_profile"
	if profile.operation_fingerprint != RecipeRunner.canonical_digest(op) or profile.policy_fingerprint != RecipeRunner.canonical_digest(policy) or RecipeRunner.canonical_digest(profile.original_duration) != RecipeRunner.canonical_digest(float(op.duration)):
		return "workbench_execution_profile_context_mismatch"
	var effective := float(op.duration)
	if not profile.unlock_transaction_id.is_empty():
		if not policy.modifiers.has(op.id) or table == null or not table.transaction_receipts.has(profile.unlock_transaction_id):
			return "workbench_unlock_receipt_missing_or_inapplicable"
		var unlock: Variant = table.transaction_receipts[profile.unlock_transaction_id]
		if not unlock is Dictionary or unlock.get("status") != "completed" or unlock.get("operation_id") != policy.unlock_operation_id:
			return "workbench_unlock_receipt_mismatch"
		error = validate_receipt(profile.unlock_transaction_id, unlock, ops, table, story, policy)
		if not error.is_empty():
			return "invalid_workbench_unlock: " + error
		effective = _modified_duration(op, policy)
	if RecipeRunner.canonical_digest(profile.effective_duration) != RecipeRunner.canonical_digest(effective):
		return "workbench_effective_duration_mismatch"
	return ""


static func _operation_error(id: Variant, op: Variant, table: TableState, story: Story) -> String:
	if not id is String or id.is_empty() or not _fields(op, ["id", "name_key", "description_key", "duration", "participants", "consume", "creates", "transforms", "sigil_effects", "requires_stories", "requires_facts", "forbidden_facts", "requires_metadata", "grants_facts", "repeatable", "source_card_id"]) or op.id != id:
		return "invalid_operation_fields"
	if not op.name_key is String or op.name_key.is_empty() or not op.description_key is String or not _number(op.duration) or float(op.duration) <= 0 or not op.repeatable is bool or not op.source_card_id is String:
		return "invalid_operation_identity_or_duration"
	for field: String in ["requires_stories", "requires_facts", "forbidden_facts", "grants_facts"]:
		if not _strings(op[field]):
			return "invalid_operation_requirements"
	for required: String in op.requires_stories:
		if story != null and not story.story_exists(required):
			return "unknown_operation_required_story"
	for fact: String in op.requires_facts:
		if fact in op.forbidden_facts:
			return "contradictory_operation_facts"
	for field: String in ["participants", "consume", "creates"]:
		if not op[field] is Array or (field == "participants" and op[field].is_empty()):
			return "invalid_operation_card_rules"
		var seen: Dictionary = {}
		for rule: Variant in op[field]:
			if not _fields(rule, ["card_id", "count", "metadata"] if field == "creates" else ["card_id", "count"]) or not rule.card_id is String or not _integer(rule.count, 1, TableState.MAX_CARDS) or seen.has(rule.card_id):
				return "invalid_operation_card_quantity"
			var definition := table.content_card_definition(rule.card_id)
			if definition.is_empty():
				return "unknown_operation_card"
			if field == "consume" and (rule.card_id == "card.hero" or definition.category in ["character", "location"] or "sigil" in definition.get("tags", [])):
				return "forbidden_operation_consumption"
			if field == "creates":
				if rule.card_id == "card.hero" or "sigil" in definition.get("tags", []) or not _metadata(rule.metadata):
					return "forbidden_operation_creation_or_metadata"
				if (definition.get("unique", false) or definition.category == "character") and int(rule.count) != 1:
					return "invalid_unique_creation_count"
				if definition.category == "character" and not rule.metadata.has("npc_id"):
					return "created_npc_requires_identity"
				if rule.metadata.has("npc_id") and table.content_npc_definition(str(rule.metadata.npc_id)).get("card_id") != rule.card_id:
					return "created_npc_identity_mismatch"
			seen[rule.card_id] = true
	if _total(op.participants) > TableState.MAX_STACK or _total(op.creates) > TableState.MAX_CARDS:
		return "operation_count_exceeds_capacity"
	var participants := _counts(op.participants)
	var references := participants.duplicate()
	for rule: Dictionary in op.creates:
		references[rule.card_id] = int(references.get(rule.card_id, 0)) + int(rule.count)
	for rule: Dictionary in op.consume:
		if int(participants.get(rule.card_id, 0)) < int(rule.count):
			return "consume_is_not_participant_subset"
	if int(references.get(op.source_card_id, 0)) != 1:
		return "ambiguous_operation_source"
	for field: String in ["transforms", "requires_metadata", "sigil_effects"]:
		if not op[field] is Array:
			return "invalid_operation_effect_collection"
	var transformed: Dictionary = {}
	for transform: Variant in op.transforms:
		if not _fields(transform, ["card_id", "to_card_id", "require_state", "set_state"]):
			return "invalid_transform_fields"
		for field: String in ["card_id", "to_card_id", "require_state", "set_state"]:
			if not transform[field] is String:
				return "invalid_transform_identity"
		if int(references.get(transform.card_id, 0)) != 1 or transformed.has(transform.card_id) or _counts(op.consume).has(transform.card_id) or table.content_card_definition(transform.to_card_id).is_empty():
			return "ambiguous_or_consumed_transform"
		var from_definition := table.content_card_definition(transform.card_id)
		var to_definition := table.content_card_definition(transform.to_card_id)
		if "sigil" in from_definition.get("tags", []) or "sigil" in to_definition.get("tags", []) or (transform.card_id != transform.to_card_id and (from_definition.category == "character" or to_definition.category == "character")):
			return "transform_cannot_replace_character_or_sigil_identity"
		if transform.card_id == transform.to_card_id and transform.set_state.is_empty():
			return "empty_transform"
		transformed[transform.card_id] = true
	for condition: Variant in op.requires_metadata:
		if not _fields(condition, ["card_id", "values"]) or not condition.card_id is String or int(references.get(condition.card_id, 0)) != 1 or not _metadata(condition.values, true):
			return "invalid_metadata_condition"
		if condition.values.has("bound_sigil_definition_id"):
			var sigil: Variant = condition.values.bound_sigil_definition_id
			if not sigil is String or not TableState.sigil_definition_compatible(sigil, condition.card_id, table):
				return "invalid_bound_sigil_definition_condition"
	var affected_sigils: Dictionary = {}
	for effect: Variant in op.sigil_effects:
		if not _fields(effect, ["action", "sigil_definition_id", "host_from", "host_to", "event_id"]):
			return "invalid_sigil_effect_fields"
		for field: String in effect:
			if not effect[field] is String:
				return "invalid_sigil_effect_identity"
		if effect.action not in ["grant_bound", "unbind", "bind", "transfer"] or "sigil" not in table.content_card_definition(effect.sigil_definition_id).get("tags", []):
			return "unknown_sigil_effect"
		if affected_sigils.has(effect.sigil_definition_id):
			return "same_sigil_requires_one_combined_effect"
		affected_sigils[effect.sigil_definition_id] = true
		if effect.action == "transfer" and effect.host_from == effect.host_to:
			return "sigil_transfer_requires_different_hosts"
		var needs_from: bool = effect.action in ["unbind", "transfer"]
		var needs_to: bool = effect.action in ["bind", "transfer", "grant_bound"]
		if needs_from == effect.host_from.is_empty() or needs_to == effect.host_to.is_empty() or (effect.action == "grant_bound") == effect.event_id.is_empty():
			return "invalid_sigil_effect_endpoints"
		for host: String in [effect.host_from, effect.host_to]:
			if not host.is_empty() and (int(references.get(host, 0)) != 1 or _counts(op.consume).has(host)):
				return "ambiguous_or_consumed_sigil_host"
	return ""


func _reference_metadata(definition: String, refs: Dictionary, op: Dictionary) -> Dictionary:
	if refs.has(definition):
		return _table.cards[refs[definition]].metadata
	for grant: Dictionary in op.creates:
		if grant.card_id == definition:
			return grant.metadata
	return {}


func _bound_sigil_definition(host_id: String) -> String:
	if not _table.cards.has(host_id):
		return ""
	var sigil_id: String = str(_table.cards[host_id].metadata.get("bound_sigil", ""))
	if not _table.cards.has(sigil_id):
		return ""
	var sigil: Dictionary = _table.cards[sigil_id]
	var definition := _table.definition_id_for_card(sigil_id)
	if sigil.zone != &"bound" or sigil.metadata.get("bound_to") != host_id or not TableState.sigil_definition_compatible(definition, _table.definition_id_for_card(host_id), _table):
		return ""
	return definition


func _lock_map() -> Dictionary:
	var locks: Dictionary = _table.get_meta(LOCK_META, {})
	for id: Variant in locks.keys():
		if _owner(locks[id]) == null:
			locks.erase(id)
	_table.set_meta(LOCK_META, locks)
	return locks


static func _owner(entry: Variant) -> Object:
	return entry.owner.get_ref() if entry is Dictionary and entry.get("owner") is WeakRef else null


func _foreign_lock(id: String) -> bool:
	var locks := _lock_map()
	return locks.has(id) and _owner(locks[id]) != null and _owner(locks[id]) != self


func _acquire(job: Dictionary) -> void:
	var locks := _lock_map()
	for id: String in job.lock_ids:
		locks[id] = {"owner": weakref(self), "job_id": job.transaction_id}
	_table.set_meta(LOCK_META, locks)


func _release(job: Dictionary) -> void:
	var locks := _lock_map()
	for id: String in job.lock_ids:
		if locks.has(id) and _owner(locks[id]) == self and locks[id].job_id == job.transaction_id:
			locks.erase(id)
	_table.set_meta(LOCK_META, locks)


func _release_all() -> void:
	if _table != null:
		for job: Dictionary in _jobs.values():
			_release(job)


func _table_digest() -> String:
	var snapshot := _table.snapshot()
	for field: String in ["next_card_id", "next_stack_id", "next_z"]:
		snapshot.erase(field)
	return RecipeRunner.canonical_digest(snapshot)


static func _metadata(value: Variant, allow_derived: bool = false) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in value:
		if not key is String or key.is_empty() or key in RESERVED_METADATA:
			return false
		if key == "bound_sigil_definition_id" and not allow_derived:
			return false
		if not (value[key] is String or value[key] is bool or _number(value[key])):
			return false
		if key in ["state", "npc_id"] and (not value[key] is String or value[key].is_empty()):
			return false
	return true


static func _counts(rules: Array) -> Dictionary:
	var result: Dictionary = {}
	for rule: Dictionary in rules:
		result[rule.card_id] = int(rule.count)
	return result


static func _total(rules: Array) -> int:
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


static func _strings(value: Variant, allow_empty: bool = true) -> bool:
	if not value is Array or (not allow_empty and value.is_empty()):
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not item is String or item.is_empty() or seen.has(item):
			return false
		seen[item] = true
	return true


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])


static func _card_id(id: String) -> bool:
	var tail := id.trim_prefix("card_")
	return id.begins_with("card_") and tail.is_valid_int() and int(tail) > 0 and id == "card_%04d" % int(tail)


static func _transaction_id(id: String) -> bool:
	var parts := id.split("/")
	return parts.size() == 3 and parts[0] == "operation" and not parts[1].is_empty() and parts[2].is_valid_int() and int(parts[2]) > 0 and str(int(parts[2])) == parts[2]


static func _own_transaction(id: String, prefix: String, next: int) -> bool:
	return _transaction_id(id) and id.begins_with(prefix) and int(id.trim_prefix(prefix)) < next


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
