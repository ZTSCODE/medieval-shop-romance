class_name ChapterRuntime
extends RefCounted

signal changed
signal outputs_created(ids: Array[String], source_position: Vector2, source_id: String)
signal market_outputs_created(ids: Array[String], source_id: String)
signal recipe_completed(recipe_id: String)
signal npc_encountered(npc_id: String)
signal failed(reason: String)

const Factory = preload("res://scripts/content/module_world_factory.gd")
const Presentation = preload("res://scripts/content/module_dialogue_flow.gd")
const Checkpoint = preload("res://scripts/content/module_checkpoint.gd")
const Services = preload("res://scripts/content/chapter_service_effects.gd")
const Relationships = preload("res://scripts/content/chapter_relationship_progress.gd")
const Canonical = preload("res://scripts/content/module_recipe_runner.gd")
const Appointments = preload("res://scripts/content/chapter_appointment_service.gd")

var package: Dictionary = {}
var world: Dictionary = {}
var table: TableState
var dialogue: ModuleDialogueFlow
var appointment_service: RefCounted
var story_sources: Dictionary = {}
var scene_npc_id := ""
var _pending_story_effects: Array[String] = []
var _event_retry_remaining := 0.0
var _market_preview_cache: Dictionary = {}
var _relationship_signature := ""
var _relationship_projection: Dictionary = {}
var _checkpoint_template: Dictionary = {}
var current_day := 1


func configure(content_package: Dictionary, restored_world: Dictionary = {}, director: Dictionary = {}, checkpoint_template: Dictionary = {}) -> Dictionary:
	if content_package.get("ok") != true:
		return {"ok": false, "error": content_package.get("error", "invalid_chapter_package")}
	var candidate := restored_world
	if candidate.is_empty():
		candidate = Factory.create(content_package.bundle, content_package.action_bindings,
			content_package.event_definitions, content_package.scene_rules, content_package.market_catalog, true, content_package.operations, {}, content_package.service_catalog, content_package.customer_catalog)
	if candidate.get("ok") != true:
		return candidate
	package = content_package
	world = candidate
	table = world.table
	appointment_service = Appointments.new()
	var appointments_ready: Dictionary = appointment_service.configure(table, world.story, package.operations, package.scene_rules)
	if not appointments_ready.ok:
		return appointments_ready
	story_sources = director.get("story_sources", {}).duplicate(true)
	scene_npc_id = director.get("scene_npc_id", "")
	dialogue = Presentation.new()
	dialogue.configure(world.story, scene_npc_id)
	world.story.changed.connect(_on_story_changed)
	world.story.story_completed.connect(_on_story_completed)
	_rebuild_pending_effects()
	_relationship_signature = ""
	_relationship_projection.clear()
	if not restored_world.is_empty() and not checkpoint_template.is_empty():
		_checkpoint_template = checkpoint_template.duplicate(true)
	else:
		var first_checkpoint: Dictionary = checkpoint()
		if not first_checkpoint.has("table"):
			return {"ok": false, "error": "invalid_initial_checkpoint"}
		_checkpoint_template = first_checkpoint.duplicate(true)
		for field: String in ["table", "story", "runner", "bridge"]:
			_checkpoint_template.erase(field)
	return {"ok": true}


func relationship_projection() -> Dictionary:
	if not package.has("relationship_catalog"):
		return {"ok": false, "error": "relationship_catalog_unavailable"}
	var story_state: Dictionary = world.story.to_data().state
	var relationship_receipts := {}
	for tx: Variant in table.transaction_receipts:
		var receipt: Variant = table.transaction_receipts[tx]
		if not tx is String or not receipt is Dictionary:
			relationship_receipts[tx] = receipt
			continue
		if receipt.get("kind") in ["chapter_operation", "chapter_event"] or receipt.has("operation_fingerprint") or receipt.has("event_fingerprint") or tx.begins_with("operation/") or tx.begins_with("event/"):
			relationship_receipts[tx] = receipt
	# 普通合成收据不会改变关系证据，不应让每次开始配方都重算整份关系目录。
	var signature := Canonical.canonical_digest({"completed": story_state.completed, "facts": story_state.facts,
		"receipts": relationship_receipts})
	if signature == _relationship_signature and not _relationship_projection.is_empty():
		return _relationship_projection.duplicate(true)
	var projected := Relationships.evaluate(table, world.story, package.relationship_catalog, package.operations, package.event_definitions,
		package.service_catalog.get("workbench", {}))
	if projected.ok:
		var completed: Array = story_state.completed
		for npc_id: String in projected.npcs:
			var total := 0
			var seen := 0
			for story_id: String in package.scene_rules:
				if package.scene_rules[story_id].npc_id == npc_id:
					total += 1
					seen += int(story_id in completed)
			projected.npcs[npc_id].story_seen = seen
			projected.npcs[npc_id].story_total = total
		_relationship_signature = signature
		_relationship_projection = projected.duplicate(true)
	return projected


func story_options(npc_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in world.scheduler.eligible_for_npc(npc_id):
		if id.begins_with("story.ch01.return_visit."):
			var found := false
			for card_id: String in table.cards:
				if table.cards[card_id].zone == &"board" and table.cards[card_id].metadata.get("npc_id") == npc_id and appointment_service.can_revisit(id, card_id, current_day).ok:
					found = true
					break
			if not found:
				continue
		var key: String = package.get("story_topics", {}).get(id, "DIALOGUE_CHOOSE_REPLY")
		result.append({"kind": "story", "id": id, "text_key": key})
	return result


func npc_interaction_available(npc_id: String) -> bool:
	return bool(npc_interactions_available([npc_id]).get(npc_id, false))


func npc_interactions_available(npc_ids: Array[String], virtual_cards: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	if npc_ids.is_empty():
		return result
	var scene_matches: Dictionary = world.scheduler.preview_eligible_for_npcs(npc_ids, virtual_cards)
	for npc_id: String in npc_ids:
		result[npc_id] = false
		for story_id: String in scene_matches.get(npc_id, []):
			if not story_id.begins_with("story.ch01.return_visit."):
				result[npc_id] = true
				break
			for card_id: String in table.cards:
				if table.cards[card_id].zone == &"board" and table.cards[card_id].metadata.get("npc_id") == npc_id and appointment_service.can_revisit(story_id, card_id, current_day).ok:
					result[npc_id] = true
					break
			if result[npc_id]:
				break
	if result.values().all(func(available: bool) -> bool: return available):
		return result
	var board_counts: Dictionary = {}
	for card_id: String in table.cards:
		if table.cards[card_id].zone == &"board":
			var definition_id := table.definition_id_for_card(card_id)
			board_counts[definition_id] = int(board_counts.get(definition_id, 0)) + 1
	var story_state: Dictionary = world.story.to_data().state
	var current_facts := facts()
	var completed_operations: Dictionary = {}
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("kind") == "chapter_operation" and receipt.get("status") == "completed":
			completed_operations[receipt.operation_id] = true
	for npc_id: String in npc_ids:
		if result[npc_id]:
			continue
		var npc_definition := table.content_npc_definition(npc_id)
		var npc_card_id: String = npc_definition.get("card_id", "")
		if not npc_card_id.is_empty():
			var candidate_counts := board_counts
			if virtual_cards.has(npc_id):
				candidate_counts = board_counts.duplicate()
				candidate_counts[npc_card_id] = int(candidate_counts.get(npc_card_id, 0)) + 1
			result[npc_id] = _npc_operation_available(npc_card_id, candidate_counts, story_state, current_facts, completed_operations)
	return result


func reconcile_npc_presence() -> bool:
	if dialogue.is_active() or not _pending_story_effects.is_empty():
		return false
	var reservations := _npc_receipt_reservations()
	if reservations.is_empty():
		return false
	var npc_ids: Array[String] = []
	var virtual_cards: Dictionary = {}
	for card_id: String in reservations:
		var entry: Dictionary = reservations[card_id]
		if entry.npc_id not in npc_ids:
			npc_ids.append(entry.npc_id)
		if not table.cards.has(card_id):
			virtual_cards[entry.npc_id] = entry.definition_id
	var availability := npc_interactions_available(npc_ids, virtual_cards)
	var changed_cards := false
	for card_id: String in reservations:
		var entry: Dictionary = reservations[card_id]
		if table.cards.has(card_id):
			if availability.get(entry.npc_id, false) or _npc_has_dependent_receipt(card_id):
				continue
			var stack_id := table.stack_for(card_id)
			if not stack_id.is_empty() and table.stacks[stack_id].cards.size() == 1 and table.remove_card(card_id):
				changed_cards = true
		elif availability.get(entry.npc_id, false):
			if table.materialize_reserved_npc(card_id, entry.definition_id, entry.npc_id, entry.position):
				var created: Array[String] = [card_id]
				outputs_created.emit(created, entry.position, entry.source_id)
				changed_cards = true
	return changed_cards


func _npc_receipt_reservations() -> Dictionary:
	var reservations: Dictionary = {}
	var removed: Dictionary = {}
	for receipt: Dictionary in table.transaction_receipts.values():
		for card_id: String in receipt.get("removed_ids", []):
			removed[card_id] = true
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("status") != "completed":
			continue
		var grants: Array = []
		if receipt.get("kind") == "chapter_operation":
			grants = package.operations.get(receipt.get("operation_id", ""), {}).get("creates", [])
		elif receipt.get("kind") == "chapter_event":
			grants = package.event_definitions.get(receipt.get("event_id", ""), {}).get("grants", [])
		if grants.is_empty():
			continue
		var created: Array = receipt.get("created_ids", [])
		var at: Array = receipt.get("source_position", [])
		if at.size() != 2:
			continue
		var position := Vector2(float(at[0]), float(at[1]))
		var offset := 0
		for grant: Dictionary in grants:
			for count_index in int(grant.count):
				if offset >= created.size():
					break
				var card_id: String = created[offset]
				offset += 1
				if removed.has(card_id) or not grant.metadata.has("npc_id"):
					continue
				reservations[card_id] = {"npc_id": String(grant.metadata.npc_id), "definition_id": String(grant.card_id),
					"position": position, "source_id": String(receipt.get("source_id", receipt.get("source_instance_id", "")))}
	return reservations


func _npc_has_dependent_receipt(card_id: String) -> bool:
	for receipt: Dictionary in table.transaction_receipts.values():
		if card_id == receipt.get("source_id", "") or card_id == receipt.get("source_instance_id", "") or card_id == receipt.get("npc_instance_id", ""):
			return true
		for field: String in ["participant_ids", "input_instance_ids", "reusable_instance_ids"]:
			if card_id in receipt.get(field, []):
				return true
	return false


func _npc_operation_available(npc_card_id: String, board_counts: Dictionary, story_state: Dictionary, current_facts: Array, completed_operations: Dictionary) -> bool:
	for operation: Dictionary in package.operations.values():
		var required: Dictionary = {}
		for participant: Dictionary in operation.participants:
			required[participant.card_id] = int(participant.count)
		if not required.has(npc_card_id):
			continue
		if not operation.repeatable and completed_operations.has(operation.id):
			continue
		var allowed := true
		for story_id: String in operation.requires_stories:
			if story_id not in story_state.completed:
				allowed = false
		for fact_id: String in operation.requires_facts:
			if fact_id not in current_facts:
				allowed = false
		for fact_id: String in operation.forbidden_facts:
			if fact_id in current_facts:
				allowed = false
		for definition_id: String in required:
			if int(board_counts.get(definition_id, 0)) < int(required[definition_id]):
				allowed = false
		if allowed:
			return true
	return false


func request_story(id: String, npc_instance_id: String) -> Dictionary:
	if not table.cards.has(npc_instance_id):
		return {"ok": false, "error": "missing_story_source"}
	var reservation := {}
	if id.begins_with("story.ch01.return_visit."):
		reservation = appointment_service.reserve_revisit(id, npc_instance_id, current_day)
		if not reservation.ok:
			return reservation
	var npc_id: String = table.cards[npc_instance_id].metadata.get("npc_id", "")
	var previous_npc := scene_npc_id
	scene_npc_id = npc_id
	# 先登记实际来源，完成事件才能从同一实例发放或离场。
	var previous_source: Variant = story_sources.get(id)
	story_sources[id] = npc_instance_id
	dialogue.configure(world.story, npc_id)
	var result: Dictionary = world.scheduler.request(id, npc_instance_id)
	if not result.ok:
		if reservation.has("transaction_id"):
			appointment_service.rollback_revisit(reservation.transaction_id)
		scene_npc_id = previous_npc
		if previous_source == null:
			story_sources.erase(id)
		else:
			story_sources[id] = previous_source
		dialogue.configure(world.story, previous_npc)
	else:
		npc_encountered.emit(npc_id)
	return result


func facts() -> Array[String]:
	var result: Array[String] = []
	result.assign(world.story.to_data().state.facts)
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("status") != "completed":
			continue
		for fact: String in receipt.get("grants_facts", []):
			if fact not in result:
				result.append(fact)
	result.sort()
	return result


func options_for_stack(stack_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not table.stacks.has(stack_id) or dialogue.is_active():
		return result
	var probe_started := HitchProbe.stamp()
	var ids: Array[String] = []
	ids.assign(table.stacks[stack_id].cards)
	for id: String in ids:
		if table.sigil_instance_locked(id):
			return result
	for id: String in world.runner.matching_recipes(ids, facts()):
		var recipe: Dictionary = package.bundle.content.recipes[id]
		result.append({"kind": "recipe", "id": id, "text_key": recipe.name_key})
	if world.has("operation_runner"):
		for id: String in world.operation_runner.matching_operations(ids, facts()):
			if not _operation_action_available(id, ids):
				continue
			result.append({"kind": "operation", "id": id, "text_key": package.operations[id].name_key})
	result.append_array(_service_options(ids))
	var shop_action := _shop_option(ids)
	if not shop_action.is_empty():
		result.append(shop_action)
	HitchProbe.record("stack_options", probe_started)
	return result


func begin_option(option: Dictionary, stack_id: String, already_checked: bool = false) -> Dictionary:
	if not table.stacks.has(stack_id):
		return {"ok": false, "error": "missing_stack"}
	if not already_checked:
		var actual := options_for_stack(stack_id)
		if option not in actual:
			return {"ok": false, "error": "option_no_longer_available"}
	var ids: Array[String] = []
	ids.assign(table.stacks[stack_id].cards)
	var result: Dictionary
	if option.kind == "service":
		var service_result: Dictionary = world.services.prepare(package.service_catalog.hearth.id, option.id, ids, current_day, "service/prep/ch01_%s_%s" % [table.next_card_id, table.transaction_receipts.size()])
		if service_result.ok:
			changed.emit()
		return service_result
	elif option.kind == "shop":
		var shop_id := _shop_card_id()
		if shop_id.is_empty():
			return {"ok": false, "error": "chapter_shop_missing"}
		table.cards[shop_id].metadata.chapter_open = not shop_open()
		changed.emit()
		return {"ok": true, "is_open": shop_open()}
	elif option.kind == "operation":
		result = world.operation_runner.begin(option.id, ids, facts())
	else:
		var source := ids[0]
		var source_rank := -1
		# 可复用工具或地点作为真实产物来源，绝不使用屏幕中心。
		var recipe: Dictionary = package.bundle.content.recipes[option.id]
		for id: String in ids:
			for rule: Dictionary in recipe.reusable:
				if table.definition_id_for_card(id) == rule.card_id and rule.card_id != "card.hero":
					var definition := table.content_card_definition(rule.card_id)
					var rank := 3 if definition.category == "location" else (2 if definition.category == "resource" else 1)
					if recipe.get("transform", {}).get("from") == rule.card_id:
						rank = 4
					if rank > source_rank:
						source_rank = rank
						source = id
		result = world.runner.begin(option.id, ids, source, facts())
	if result.ok:
		changed.emit()
	return result


func shop_open() -> bool:
	var id := _shop_card_id()
	return not id.is_empty() and table.cards[id].metadata.get("chapter_open") == true


func _shop_card_id() -> String:
	for id: String in table.cards:
		if table.definition_id_for_card(id) == "card.shop" and table.cards[id].zone == &"board":
			return id
	return ""


func _shop_option(ids: Array[String]) -> Dictionary:
	if ids.size() != 2 or not runtime_permission("market_unlock_fact"):
		return {}
	var kinds: Array[String] = []
	for id: String in ids:
		kinds.append(table.definition_id_for_card(id))
	kinds.sort()
	if kinds != ["card.hero", "card.shop"]:
		return {}
	return {"kind": "shop", "id": "shop/close" if shop_open() else "shop/open",
		"text_key": "CARD_SHOP_CLOSED_TITLE" if shop_open() else "CARD_SHOP_OPEN_TITLE"}


func _operation_action_available(operation_id: String, instance_ids: Array[String]) -> bool:
	for binding: Dictionary in package.action_bindings.values():
		if binding.get("operation_id") == operation_id:
			return world.bridge.has_method("can_execute_operation") and world.bridge.can_execute_operation(operation_id, instance_ids)
	return true


func advance(delta: float, suspended: bool) -> void:
	if not suspended:
		_ensure_services_active()
	for receipt: Dictionary in world.runner.advance(delta, suspended):
		_settle_receipt(receipt)
	if world.has("operation_runner"):
		for receipt: Dictionary in world.operation_runner.advance(delta, suspended):
			_settle_receipt(receipt)
	if not suspended and not _pending_story_effects.is_empty():
		_event_retry_remaining -= maxf(delta, 0.0)
		if _event_retry_remaining <= 0.0:
			_event_retry_remaining = 0.35
			_retry_story_effects()
	if not suspended:
		_ensure_services_active()


func _ensure_services_active() -> void:
	if not world.has("services") or world.services == null or table.transaction_receipts.has("service/context") or not runtime_permission("market_unlock_fact"):
		return
	var activated: Dictionary = world.services.activate(current_day)
	if not activated.ok:
		failed.emit(str(activated.error))
	else:
		_market_preview_cache.clear()
		changed.emit()


func _service_options(ids: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not world.has("services") or world.services == null or not table.transaction_receipts.has("service/context"):
		return result
	var actual: Dictionary = {}
	for id: String in ids:
		var definition := table.definition_id_for_card(id)
		actual[definition] = int(actual.get(definition, 0)) + 1
	for task_id: String in package.service_catalog.hearth.tasks:
		var task: Dictionary = package.service_catalog.hearth.tasks[task_id]
		var expected: Dictionary = {}
		for rule: Dictionary in package.operations[task.preparation_operation_id].participants:
			if rule.card_id != task.meal_card_id:
				expected[rule.card_id] = int(rule.count)
		if actual != expected:
			continue
		var candidate := table.fork_empty()
		candidate.restore(table.snapshot())
		var service := Services.new()
		if not service.configure(candidate, world.story, package.service_catalog, package.operations, package.market_catalog).ok:
			continue
		var outcome := service.prepare(package.service_catalog.hearth.id, task_id, ids, current_day, "service/prep/preview")
		if outcome.ok:
			result.append({"kind": "service", "id": task_id, "text_key": package.service_catalog.hearth.name_key})
	return result


func work_progress() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for job: Dictionary in world.runner.active_jobs():
		result.append({"stack_id": job.stack_id, "progress": float(job.elapsed) / float(package.bundle.content.recipes[job.recipe_id].duration)})
	if world.has("operation_runner"):
		for job: Dictionary in world.operation_runner.active_jobs():
			var duration: float = float(job.get("execution_profile", {}).get("effective_duration", package.operations[job.operation_id].duration))
			result.append({"stack_id": job.stack_id, "progress": clampf(float(job.elapsed) / duration, 0.0, 1.0)})
	return result


func market_remaining(offer_id: String, day: int) -> int:
	var terms: Dictionary = world.market.terms(offer_id, day)
	return int(terms.remaining) if terms.ok else 0


func market_inputs(offer_id: String, dragged_ids: Array[String]) -> Array[String]:
	var selected: Array[String] = []
	if not package.market_catalog.offers.has(offer_id):
		return selected
	var required: Dictionary = {}
	for entry: Dictionary in package.market_catalog.offers[offer_id].inputs:
		required[entry.card_id] = int(entry.count)
	var allowed := required.duplicate()
	for id: String in dragged_ids:
		if not table.cards.has(id) or table.cards[id].zone != &"board" or table.sigil_instance_locked(id):
			return []
		var definition := table.definition_id_for_card(id)
		# 一叠可找零，但不能把主角、工具或混合商品一并当作付款。
		if not allowed.has(definition):
			return []
		if int(required[definition]) > 0:
			selected.append(id)
			required[definition] -= 1
	for remaining: int in required.values():
		if remaining > 0:
			return []
	return selected


func market_preview(offer_id: String, dragged_ids: Array[String], source_id: String, day: int) -> Dictionary:
	if not runtime_permission("market_unlock_fact"):
		return {"ok": false, "error": "market_not_reached"}
	var inputs := market_inputs(offer_id, dragged_ids)
	if inputs.is_empty():
		return {"ok": false, "error": "insufficient_or_invalid_cards"}
	var key := str([offer_id, inputs, source_id, day, table.cards.size(), table.transaction_receipts.size(), facts()])
	if _market_preview_cache.get("key") == key:
		return _market_preview_cache.result.duplicate(true)
	var candidate := table.fork_empty()
	candidate.restore(table.snapshot())
	var exchange := ModuleMarketExchange.new()
	var result := exchange.configure(candidate, package.market_catalog.offers, package.market_catalog.sources, Services.market_policy(package.service_catalog), package.operations)
	if result.ok:
		result = exchange.execute(offer_id, inputs, source_id, Vector2.ZERO, day, facts(), "market/preview")
	_market_preview_cache = {"key": key, "result": {"ok": result.ok, "error": result.get("error", "")}}
	return _market_preview_cache.result.duplicate(true)


func trade(offer_id: String, dragged_ids: Array[String], source_id: String, source_position: Vector2, day: int) -> Dictionary:
	if not runtime_permission("market_unlock_fact"):
		return {"ok": false, "error": "market_not_reached"}
	var inputs := market_inputs(offer_id, dragged_ids)
	if inputs.is_empty():
		return {"ok": false, "error": "insufficient_or_invalid_cards"}
	var transaction := "market/ch01_%s_%s" % [table.next_card_id, table.transaction_receipts.size()]
	var result: Dictionary = world.market.execute(offer_id, inputs, source_id, source_position, day, facts(), transaction)
	if result.ok and not result.get("already_applied", false):
		var ids: Array[String] = []
		ids.assign(result.output_instance_ids)
		_place_outputs(ids, source_position)
		_market_preview_cache.clear()
		# 屏幕固定菜单的飞出位置由界面负责；模型只持有对应逻辑投影。
		market_outputs_created.emit(ids, source_id)
		changed.emit()
	return result


func director_data() -> Dictionary:
	var completed: Array[String] = []
	for receipt: Dictionary in table.transaction_receipts.values():
		if receipt.get("kind") == "chapter_operation" and receipt.get("status") == "completed" and receipt.operation_id not in completed:
			completed.append(receipt.operation_id)
	completed.sort()
	return {"schema_version": 1, "scene_npc_id": scene_npc_id if not world.story.to_data().state.story_id.is_empty() else "", "story_sources": story_sources.duplicate(true),
		"completed_operations": completed, "operation_jobs": world.operation_runner.to_data() if world.has("operation_runner") else {}, "pending_outputs": []}


func checkpoint() -> Dictionary:
	return Checkpoint.capture(table, world.story, world.runner, world.bridge, package.market_catalog, package.event_definitions, package.operations, package.service_catalog, package.customer_catalog)


func checkpoint_fast() -> Dictionary:
	if _checkpoint_template.is_empty():
		return {"ok": false, "error": "checkpoint_template_unavailable"}
	var started := HitchProbe.stamp()
	var raw: Dictionary = _checkpoint_template.duplicate(true)
	HitchProbe.record("fast_checkpoint_template", started)
	started = HitchProbe.stamp()
	raw["table"] = table.snapshot()
	HitchProbe.record("fast_checkpoint_table", started)
	started = HitchProbe.stamp()
	raw["story"] = world.story.to_data()
	HitchProbe.record("fast_checkpoint_story", started)
	started = HitchProbe.stamp()
	raw["runner"] = world.runner.to_data()
	HitchProbe.record("fast_checkpoint_runner", started)
	started = HitchProbe.stamp()
	raw["bridge"] = world.bridge.to_data_fast()
	HitchProbe.record("fast_checkpoint_bridge", started)
	started = HitchProbe.stamp()
	var normalized: Dictionary = Canonical.json_value(raw)
	HitchProbe.record("fast_checkpoint_normalize", started)
	return normalized


func dispose() -> void:
	_checkpoint_template.clear()
	if world.has("story"):
		if world.story.changed.is_connected(_on_story_changed):
			world.story.changed.disconnect(_on_story_changed)
		if world.story.story_completed.is_connected(_on_story_completed):
			world.story.story_completed.disconnect(_on_story_completed)
	if dialogue != null:
		dialogue.configure(null)
	world.clear()
	table = null


func _on_story_changed() -> void:
	var node: Dictionary = world.story.current_node()
	if node.get("type") == "action" and package.action_bindings.has(node.action_id):
		var armed: Dictionary = world.bridge.arm_current_action()
		if not armed.ok:
			failed.emit(str(armed.error))
	changed.emit()


func _on_story_completed(story_id: String, _event_id: String) -> void:
	if story_id.begins_with("story.ch01.contact_visit."):
		var recorded: Dictionary = appointment_service.record_first(story_id, String(story_sources.get(story_id, "")), current_day)
		if not recorded.ok:
			failed.emit(str(recorded.error))
	_rebuild_pending_effects()
	_event_retry_remaining = 0.0
	changed.emit()


func _rebuild_pending_effects() -> void:
	_pending_story_effects.clear()
	var completed: Array = world.story.to_data().state.completed
	for event_id: String in package.event_definitions:
		var definition: Dictionary = package.event_definitions[event_id]
		if definition.trigger_story_id not in completed or not story_sources.has(definition.trigger_story_id):
			continue
		var settled := false
		for receipt: Dictionary in table.transaction_receipts.values():
			if receipt.get("kind") == "chapter_event" and receipt.get("event_id") == event_id:
				settled = true
		if not settled:
			_pending_story_effects.append(event_id)


func _retry_story_effects() -> void:
	# 未结算事件从 completed + 来源 + 收据重建，满桌、暂停、读档均不能吞掉后果。
	for event_id: String in _pending_story_effects.duplicate():
		var definition: Dictionary = package.event_definitions[event_id]
		var source: String = story_sources.get(definition.trigger_story_id, "")
		if not table.cards.has(source) or table.definition_id_for_card(source) != definition.source_card_id:
			continue
		var receipt: Dictionary = world.effects.apply(event_id, source)
		if receipt.ok:
			_pending_story_effects.erase(event_id)
			_settle_receipt(receipt)
		elif receipt.get("error") not in ["capacity_exceeded", "event_source_locked"]:
			failed.emit(str(receipt.error))


func _settle_receipt(receipt: Dictionary) -> void:
	if not receipt.get("ok", false) or receipt.get("status") != "completed" or receipt.get("already_applied", false):
		return
	var ids: Array[String] = []
	ids.assign(receipt.get("output_instance_ids", receipt.get("created_ids", [])))
	# 解印是原实例从载体上取出，也必须从载体位置出现，不能原地闪现。
	if receipt.get("kind") == "chapter_operation":
		for transaction: String in table.transaction_receipts:
			if transaction.begins_with(receipt.transaction_id + "/sigil/"):
				var child: Dictionary = table.transaction_receipts[transaction]
				if child.get("action") == "unbind":
					var sigil: String = child.sigil_instance_id
					if table.cards.has(sigil) and table.cards[sigil].zone == &"board" and sigil not in ids:
						ids.append(sigil)
	var position: Variant = receipt.get("source_position", [0, 0])
	var source_position: Vector2 = position if position is Vector2 else Vector2(float(position[0]), float(position[1]))
	_place_outputs(ids, source_position)
	if not ids.is_empty():
		outputs_created.emit(ids, source_position, str(receipt.get("source_id", receipt.get("source_instance_id", ""))))
	if receipt.has("recipe_id"):
		recipe_completed.emit(receipt.recipe_id)
	var node: Dictionary = world.story.current_node()
	if node.get("type") == "action" and package.action_bindings.has(node.action_id):
		var binding: Dictionary = package.action_bindings[node.action_id]
		var recipe_matches: bool = binding.has("recipe_id") and binding.recipe_id == receipt.get("recipe_id")
		var operation_matches: bool = binding.has("operation_id") and binding.operation_id == receipt.get("operation_id")
		if recipe_matches or operation_matches:
			var submitted: Dictionary = world.bridge.submit(receipt.transaction_id)
			if not submitted.ok:
				failed.emit(str(submitted.error))
	changed.emit()


func _place_outputs(ids: Array[String], source: Vector2) -> void:
	var placed: Dictionary = {}
	for card_id: String in ids:
		var stack := table.stack_for(card_id)
		if stack.is_empty() or placed.has(stack):
			continue
		placed[stack] = true
		var extent := table.stack_size(stack)
		var candidates: Array[Vector2] = []
		for row in range(-8, 9):
			for column in range(-10, 11):
				candidates.append(table.clamp_position(source + Vector2(column * (TableState.CARD_SIZE.x + 24), row * (extent.y + 24)), extent))
		candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(source) < b.distance_squared_to(source))
		for point: Vector2 in candidates:
			var free := true
			for other: String in table.stacks:
				if other != stack and Rect2(point, extent).grow(8).intersects(table.stack_rect(other).grow(8)):
					free = false
					break
			if free:
				table.move_stack(stack, point)
				break


func runtime_permission(rule: String) -> bool:
	var fact := String(ContentCatalog.runtime_rules().get(rule, ""))
	return not fact.is_empty() and fact in facts()
