class_name ChapterRelationshipProgress
extends RefCounted

const Story = preload("res://scripts/content/module_story_session.gd")
const Operations = preload("res://scripts/content/chapter_operation_runner.gd")
const Events = preload("res://scripts/content/module_event_effects.gd")
const Canonical = preload("res://scripts/content/module_recipe_runner.gd")
const MAX_MILESTONES := 256
const SIGNAL_VALUES := {
	"met": ["yes"],
	"player_intent": ["personal", "friendship", "deferred"],
	"meeting_consent": ["agreed"],
	"appointment_recorded": ["yes"],
	"regular_contact": ["ready"],
	"private_time": ["shared_personal", "shared_friendship", "deferred"],
	"disclosure": ["confided_pursuit", "kept_private"],
}


# 只核对外部给定的上下文，不激活全局模块，也不向进度写入奖励。
static func validate_catalog(catalog: Variant, table: TableState, story: Story, ops: Dictionary, events: Dictionary, workbench_policy: Variant = null) -> String:
	if table == null or story == null or story.to_data().catalog_fingerprint.is_empty():
		return "relationship_context_missing"
	if not _fields(catalog, ["schema_version", "module_id", "affection_cap", "npcs", "milestones"]):
		return "invalid_relationship_catalog_fields"
	if not _integer(catalog.schema_version, 1, 1) or catalog.module_id != "chapter_01" or not _integer(catalog.affection_cap, 1, 60):
		return "invalid_relationship_catalog_version_or_cap"
	if not _strings(catalog.npcs, "^npc\\.[a-z0-9_.]+$", false) or catalog.npcs.size() > 16:
		return "invalid_relationship_npcs"
	for id: String in catalog.npcs:
		if table.content_npc_definition(id).is_empty():
			return "unknown_relationship_npc"
	if not catalog.milestones is Dictionary or catalog.milestones.is_empty() or catalog.milestones.size() > MAX_MILESTONES:
		return "invalid_relationship_milestones"
	var operation_error := Operations.validate_catalog(ops, table, story, workbench_policy)
	if not operation_error.is_empty():
		return "relationship_operation_catalog: " + operation_error
	var event_checker := Events.new()
	var event_check: Dictionary = event_checker.configure(table, story, events)
	if not event_check.ok:
		return "relationship_event_context: " + str(event_check.get("error", "invalid"))
	var sums: Dictionary = {}
	var reward_sources: Dictionary = {}
	for id: Variant in catalog.milestones:
		var item: Variant = catalog.milestones[id]
		if not _matches(id, "^relationship\\.ch01\\.[a-z0-9_.]+$") or not _fields(item, ["id", "npc_id", "title_key", "detail_key", "affection_delta", "requires_stories", "requires_facts", "any_fact_groups", "requires_operations", "any_operation_groups", "requires_events", "signals", "priority"]):
			return "invalid_relationship_milestone_fields"
		if item.id != id or item.npc_id not in catalog.npcs or not _matches(item.title_key, "^[A-Z][A-Z0-9_]*$") or not _matches(item.detail_key, "^[A-Z][A-Z0-9_]*$"):
			return "invalid_relationship_milestone_identity"
		if not _integer(item.affection_delta, 0, 10) or not _integer(item.priority, 0, 100):
			return "invalid_relationship_weight_or_priority"
		if not _strings(item.requires_stories, "^story\\.[a-z0-9_.]+$", false) or not _strings(item.requires_facts, "^fact\\.ch01\\.[a-z0-9_.]+$"):
			return "invalid_relationship_story_or_fact_list"
		if not _strings(item.requires_operations, "^operation\\.[a-z0-9_.]+$") or not _strings(item.requires_events, "^event\\.[a-z0-9_.]+$"):
			return "invalid_relationship_evidence_list"
		if not _groups(item.any_fact_groups, "^fact\\.ch01\\.[a-z0-9_.]+$") or not _groups(item.any_operation_groups, "^operation\\.[a-z0-9_.]+$"):
			return "invalid_relationship_alternatives"
		for required: String in item.requires_stories:
			if not story.story_exists(required):
				return "unknown_relationship_story"
		var operation_ids: Array = item.requires_operations.duplicate()
		for group: Array in item.any_operation_groups:
			operation_ids.append_array(group)
		for required: String in operation_ids:
			if not ops.has(required):
				return "unknown_relationship_operation"
		for required: String in item.requires_events:
			if not events.has(required) or events[required].trigger_story_id not in item.requires_stories:
				return "relationship_event_trigger_not_required"
		if int(item.affection_delta) > 0 and operation_ids.is_empty() and item.requires_events.is_empty():
			return "relationship_reward_requires_actual_work_or_event"
		if int(item.affection_delta) > 0:
			var source_ids: Array = []
			for source: String in operation_ids:
				if source not in source_ids:
					source_ids.append(source)
			for source: String in item.requires_events:
				if source not in source_ids:
					source_ids.append(source)
			for source: String in source_ids:
				var token := str(item.npc_id) + "/" + source
				if reward_sources.has(token):
					return "relationship_source_rewarded_twice_for_npc"
				reward_sources[token] = id
		if not item.signals is Dictionary or item.signals.size() > SIGNAL_VALUES.size():
			return "invalid_relationship_signals"
		for key: Variant in item.signals:
			if not key is String or not SIGNAL_VALUES.has(key) or not item.signals[key] is String or item.signals[key] not in SIGNAL_VALUES[key]:
				return "invalid_relationship_signal_value"
		sums[item.npc_id] = int(sums.get(item.npc_id, 0)) + int(item.affection_delta)
	for sum: int in sums.values():
		if sum > int(catalog.affection_cap):
			return "relationship_authored_rewards_exceed_chapter_cap"
	return ""


static func evaluate(table: TableState, story: Story, catalog: Variant, ops: Dictionary, events: Dictionary, workbench_policy: Variant = null) -> Dictionary:
	var error := validate_catalog(catalog, table, story, ops, events, workbench_policy)
	if not error.is_empty():
		return _failure(error)
	var state: Dictionary = story.to_data().state
	if not _strings(state.completed, "^story\\.[a-z0-9_.]+$") or not _strings(state.facts, "^fact\\.[a-z0-9_.]+$"):
		return _failure("invalid_relationship_story_state")
	var proofs := _validated_proofs(table, story, ops, events, workbench_policy)
	if not proofs.ok:
		return proofs
	var npcs: Dictionary = {}
	var signal_priorities: Dictionary = {}
	for npc_id: String in catalog.npcs:
		npcs[npc_id] = {"affection": 0, "trust": 0, "cap": int(catalog.affection_cap), "met": false,
			"signals": {"player_intent": "unexpressed", "meeting_consent": "unconfirmed", "appointment_recorded": "no", "regular_contact": "unarranged", "private_time": "unshared", "disclosure": "unshared"},
			"milestones": [], "source_ids": []}
		signal_priorities[npc_id] = {}
	var ids: Array = catalog.milestones.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var left: int = int(catalog.milestones[a].priority)
		var right: int = int(catalog.milestones[b].priority)
		return a < b if left == right else left < right)
	for id: String in ids:
		var item: Dictionary = catalog.milestones[id]
		var witness := _witness(item, state, proofs)
		if witness.is_empty():
			continue
		var result: Dictionary = npcs[item.npc_id]
		result.affection = mini(int(result.affection) + int(item.affection_delta), int(catalog.affection_cap))
		result.trust = result.affection
		result.milestones.append({"id": id, "title_key": item.title_key, "detail_key": item.detail_key,
			"affection_delta": int(item.affection_delta), "evidence": witness})
		for source: String in witness.source_ids:
			if source not in result.source_ids:
				result.source_ids.append(source)
		for key: String in item.signals:
			var priorities: Dictionary = signal_priorities[item.npc_id]
			var priority := int(item.priority)
			if priorities.has(key) and int(priorities[key]) == priority and result.signals.get(key) != item.signals[key]:
				return _failure("ambiguous_relationship_signal: " + item.npc_id + "/" + key)
			if not priorities.has(key) or priority > int(priorities[key]):
				priorities[key] = priority
				result.signals[key] = item.signals[key]
		result.met = result.signals.get("met", "no") == "yes"
	for npc_id: String in npcs:
		npcs[npc_id].source_ids.sort()
	return {"ok": true, "error": "", "catalog_fingerprint": Canonical.canonical_digest(catalog), "npcs": npcs}


# 只采信完成的真实操作与剧情后果；普通交易、配方和任意 grants_facts 不能冒充关系证据。
static func _validated_proofs(table: TableState, story: Story, ops: Dictionary, events: Dictionary, workbench_policy: Variant = null) -> Dictionary:
	var operation_proofs: Dictionary = {}
	var event_proofs: Dictionary = {}
	for tx: Variant in table.transaction_receipts:
		var value: Variant = table.transaction_receipts[tx]
		if not tx is String or not value is Dictionary:
			return _failure("invalid_relationship_ledger_entry")
		var operation_owned: bool = value.get("kind") == Operations.RECEIPT_KIND or value.has("operation_fingerprint") or (tx.begins_with("operation/") and tx.count("/") == 2)
		if operation_owned:
			var error := Operations.validate_receipt(tx, value, ops, table, story, workbench_policy)
			if not error.is_empty():
				return _failure("invalid_relationship_operation_proof: " + error)
			if value.status == "completed":
				if not operation_proofs.has(value.operation_id):
					operation_proofs[value.operation_id] = []
				operation_proofs[value.operation_id].append(tx)
		elif value.get("kind") == Events.RECEIPT_KIND or value.has("event_fingerprint") or tx.begins_with(Events.TRANSACTION_PREFIX):
			var error := Events.validate_receipt(tx, value, events, table)
			if not error.is_empty():
				return _failure("invalid_relationship_event_proof: " + error)
			if events[value.event_id].trigger_story_id not in story.to_data().state.completed:
				return _failure("relationship_event_without_completed_story")
			event_proofs[value.event_id] = tx
	for ids: Array in operation_proofs.values():
		ids.sort()
	return {"ok": true, "operations": operation_proofs, "events": event_proofs}


static func _witness(item: Dictionary, state: Dictionary, proofs: Dictionary) -> Dictionary:
	for id: String in item.requires_stories:
		if id not in state.completed:
			return {}
	var facts: Array = item.requires_facts.duplicate()
	for fact: String in facts:
		if fact not in state.facts:
			return {}
	for group: Array in item.any_fact_groups:
		var matched := ""
		for fact: String in group:
			if fact in state.facts:
				matched = fact
				break
		if matched.is_empty():
			return {}
		if matched not in facts:
			facts.append(matched)
	var operation_ids: Array = item.requires_operations.duplicate()
	for id: String in operation_ids:
		if not proofs.operations.has(id):
			return {}
	for group: Array in item.any_operation_groups:
		var matched := ""
		for id: String in group:
			if proofs.operations.has(id):
				matched = id
				break
		if matched.is_empty():
			return {}
		if matched not in operation_ids:
			operation_ids.append(matched)
	var witness := {"stories": item.requires_stories.duplicate(), "facts": facts, "operations": {}, "events": {}, "source_ids": []}
	for id: String in item.requires_stories:
		witness.source_ids.append(id)
	for fact: String in facts:
		witness.source_ids.append(fact)
	for id: String in operation_ids:
		var tx: String = proofs.operations[id][0]
		witness.operations[id] = tx
		witness.source_ids.append(tx)
	for id: String in item.requires_events:
		if not proofs.events.has(id):
			return {}
		witness.events[id] = proofs.events[id]
		witness.source_ids.append(proofs.events[id])
	return witness


static func _fields(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key: String in keys:
		if not value.has(key):
			return false
	return true


static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value) and float(value) >= low and float(value) <= high


static func _matches(value: Variant, pattern: String) -> bool:
	if not value is String:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func _strings(value: Variant, pattern: String, allow_empty := true) -> bool:
	if not value is Array or (not allow_empty and value.is_empty()) or value.size() > 256:
		return false
	var seen: Dictionary = {}
	for text: Variant in value:
		if not _matches(text, pattern) or seen.has(text):
			return false
		seen[text] = true
	return true


static func _groups(value: Variant, pattern: String) -> bool:
	if not value is Array or value.size() > 16:
		return false
	for group: Variant in value:
		if not _strings(group, pattern, false):
			return false
	return true


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "npcs": {}}
