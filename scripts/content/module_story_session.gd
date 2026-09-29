class_name ModuleStorySession
extends RefCounted

signal changed
signal story_completed(story_id: String, completion_event: String)
signal action_requested(story_id: String, node_id: String, action_id: String)

const SAVE_VERSION := 1
const MAX_STORIES := 256
const MAX_NODES_PER_STORY := 1024
const MAX_COMMANDS := 50000

var _stories: Dictionary = {}
var _groups: Array = []
var _known_facts: Dictionary = {}
var _fingerprint := ""
var _state: Dictionary = _empty_state()
var _commands: Array = []
var _mutating := false


func configure(stories: Dictionary, exclusive_fact_groups: Array = []) -> Dictionary:
	if _mutating:
		return _failure("Session is emitting an update")
	var candidate := stories.duplicate(true)
	var groups := exclusive_fact_groups.duplicate(true)
	var validation := _validate_catalog(candidate, groups)
	if not validation.ok:
		return validation
	var fingerprint := JSON.stringify({"stories": candidate, "groups": groups}, "", true).sha256_text()
	if fingerprint == _fingerprint:
		return _success()
	if not _commands.is_empty():
		return _failure("A session with progress cannot change its catalog")
	_stories = candidate
	_groups = groups
	_known_facts = validation.facts
	_fingerprint = fingerprint
	_state = _empty_state()
	return _success()


func start(story_id: String) -> Dictionary:
	return _execute({"op": "start", "story_id": story_id})


func story_exists(story_id: String) -> bool:
	return _stories.has(story_id)


func current_node() -> Dictionary:
	if String(_state.story_id).is_empty():
		return {}
	var result: Dictionary = _stories[_state.story_id].nodes[_state.node_id].duplicate(true)
	result["story_id"] = _state.story_id
	result["node_id"] = _state.node_id
	result["replaying"] = _state.replaying
	if result.type == "choice" and _state.replaying:
		result["locked_choice_id"] = _state.choices[_state.story_id].get(_state.node_id, "")
	return result


func action_binding_exists(story_id: String, node_id: String, action_id: String) -> bool:
	if not _stories.has(story_id) or not _stories[story_id].nodes.has(node_id):
		return false
	var node: Dictionary = _stories[story_id].nodes[node_id]
	return node.get("type") == "action" and node.get("action_id") == action_id


func advance() -> Dictionary:
	return _execute({"op": "advance"})


func choose(choice_id: String) -> Dictionary:
	return _execute({"op": "choose", "choice_id": choice_id})


func complete_action(action_id: String, transaction_id: String) -> Dictionary:
	return _execute({"op": "action", "action_id": action_id, "transaction_id": transaction_id})


func set_paused(value: bool, notify: bool = true) -> void:
	if _mutating or _state.paused == value:
		return
	_state.paused = value
	if notify:
		_mutating = true
		changed.emit()
		_mutating = false


func is_paused() -> bool:
	return bool(_state.paused)


func to_data() -> Dictionary:
	return {"schema_version": SAVE_VERSION, "catalog_fingerprint": _fingerprint, "state": _state.duplicate(true), "commands": _commands.duplicate(true)}


func restore(data: Variant) -> Dictionary:
	if _mutating or _fingerprint.is_empty():
		return _failure("Session is not available for restore")
	if not _json_safe(data, 0, {"visited": 0}):
		return _failure("Story save contains unsupported or excessive data")
	if not data is Dictionary or not _fields(data, ["schema_version", "catalog_fingerprint", "state", "commands"]):
		return _failure("Invalid story save fields")
	if not _whole_number(data.schema_version, SAVE_VERSION, SAVE_VERSION) or data.catalog_fingerprint != _fingerprint:
		return _failure("Story save belongs to an unknown catalog or version")
	if not data.state is Dictionary or not data.commands is Array or data.commands.size() > MAX_COMMANDS:
		return _failure("Invalid story save state or command count")
	var saved: Dictionary = data.state
	if not _fields(saved, _empty_state().keys()) or not saved.paused is bool:
		return _failure("Invalid story state fields")
	if not _fact_list(saved.facts, _known_facts) or _facts_conflict(saved.facts, _groups):
		return _failure("Unknown, duplicated, or conflicting story facts")
	var rebuilt := _empty_state()
	for operation: Variant in data.commands:
		if not operation is Dictionary:
			return _failure("Invalid recorded story command")
		var result := _apply_operation(rebuilt, operation)
		if not result.ok:
			return _failure("Invalid recorded story command: " + String(result.error))
	rebuilt.paused = saved.paused
	if JSON.stringify(rebuilt, "", true) != JSON.stringify(saved, "", true):
		return _failure("Story state does not match its choice and transaction history")
	_state = rebuilt
	_commands = data.commands.duplicate(true)
	_mutating = true
	changed.emit()
	_mutating = false
	return _success()


func _execute(operation: Dictionary) -> Dictionary:
	if _mutating or _fingerprint.is_empty():
		return _failure("Story session is not configured or is busy")
	if _state.paused:
		return _failure("Story session is paused")
	if _commands.size() >= MAX_COMMANDS:
		return _failure("Story command capacity reached")
	var candidate := _state.duplicate(true)
	var result := _apply_operation(candidate, operation)
	if not result.ok:
		return result
	var previous_completed: int = _state.completed.size()
	_state = candidate
	_commands.append(operation.duplicate(true))
	_mutating = true
	changed.emit()
	if _state.completed.size() > previous_completed:
		var finished_id: String = _state.completed.back()
		story_completed.emit(finished_id, String(_stories[finished_id].completion_event))
	if not String(_state.story_id).is_empty() and not _state.replaying:
		var current: Dictionary = _stories[_state.story_id].nodes[_state.node_id]
		if current.type == "action":
			action_requested.emit(String(_state.story_id), String(_state.node_id), String(current.action_id))
	_mutating = false
	return _success()


func _apply_operation(state: Dictionary, operation: Dictionary) -> Dictionary:
	if not operation.get("op") is String:
		return _failure("Missing story operation")
	var op: String = operation.op
	if op == "start":
		if not _fields(operation, ["op", "story_id"]) or not operation.story_id is String or not _stories.has(operation.story_id):
			return _failure("Unknown story ID")
		if not String(state.story_id).is_empty():
			return _failure("Another story is active")
		state.story_id = operation.story_id
		state.node_id = _stories[state.story_id].entry
		state.replaying = state.story_id in state.completed
		if state.replaying:
			if not state.entry_facts.has(state.story_id):
				return _failure("Replay entry facts are missing")
			state.replay_facts = state.entry_facts[state.story_id].duplicate()
		else:
			state.entry_facts[state.story_id] = state.facts.duplicate()
			state.choices[state.story_id] = {}
		return _resolve_internal(state)
	if String(state.story_id).is_empty():
		return _failure("No story is active")
	var node: Dictionary = _stories[state.story_id].nodes[state.node_id]
	match op:
		"advance":
			if not _fields(operation, ["op"]) or node.type != "line":
				return _failure("Only a line can advance")
			state.node_id = node.next
		"choose":
			if not _fields(operation, ["op", "choice_id"]) or not operation.choice_id is String or node.type != "choice":
				return _failure("Only a choice node accepts a choice")
			var selected: Dictionary = {}
			for option: Dictionary in node.choices:
				if option.id == operation.choice_id:
					selected = option
			if selected.is_empty():
				return _failure("Unknown choice ID")
			var recorded: Dictionary = state.choices[state.story_id]
			if state.replaying and recorded.get(state.node_id, "") != operation.choice_id:
				return _failure("A replay cannot change an earlier choice")
			var selected_facts: Array = state.replay_facts if state.replaying else state.facts
			var combined := selected_facts.duplicate()
			for fact: String in selected.facts:
				if fact not in combined:
					combined.append(fact)
			if _facts_conflict(combined, _groups):
				return _failure("Choice contradicts existing exclusive facts")
			combined.sort()
			if state.replaying:
				state.replay_facts = combined
			else:
				state.facts = combined
				recorded[state.node_id] = operation.choice_id
			state.node_id = selected.next
		"action":
			if not _fields(operation, ["op", "action_id", "transaction_id"]) or node.type != "action" or state.replaying:
				return _failure("No original action is waiting")
			if not operation.action_id is String or operation.action_id != node.action_id:
				return _failure("Action ID does not match the pending node")
			if not operation.transaction_id is String or not _transaction_id_valid(operation.transaction_id):
				return _failure("Invalid action transaction ID")
			if state.transactions.has(operation.transaction_id):
				return _failure("Action transaction has already been consumed")
			state.transactions[operation.transaction_id] = {"story_id": state.story_id, "node_id": state.node_id, "action_id": node.action_id}
			state.node_id = node.next
		_:
			return _failure("Unknown story operation")
	return _resolve_internal(state)


func _resolve_internal(state: Dictionary) -> Dictionary:
	for _iteration in MAX_NODES_PER_STORY + 1:
		if String(state.node_id).is_empty():
			if not state.replaying:
				var event_id: String = _stories[state.story_id].completion_event
				if state.story_id in state.completed or event_id in state.events:
					return _failure("Story completion is already settled")
				state.completed.append(state.story_id)
				state.events.append(event_id)
			state.story_id = ""
			state.replaying = false
			state.replay_facts = []
			return _success()
		var node: Dictionary = _stories[state.story_id].nodes[state.node_id]
		if node.type == "condition":
			var match_targets: Array[String] = []
			var active_facts: Array = state.replay_facts if state.replaying else state.facts
			for clause: Dictionary in node.cases:
				var matches := true
				for fact: String in clause.all:
					matches = matches and fact in active_facts
				for fact: String in clause.none:
					matches = matches and fact not in active_facts
				if matches:
					match_targets.append(clause.next)
			if match_targets.size() > 1:
				return _failure("More than one condition matches")
			state.node_id = node.fallback if match_targets.is_empty() else match_targets[0]
			continue
		if node.type == "action" and state.replaying:
			var receipt_found := false
			for receipt: Dictionary in state.transactions.values():
				if receipt.story_id == state.story_id and receipt.node_id == state.node_id and receipt.action_id == node.action_id:
					receipt_found = true
					break
			if not receipt_found:
				return _failure("Replay action has no original transaction receipt")
			state.node_id = node.next
			continue
		return _success()
	return _failure("Internal story dispatch exceeded its limit")


static func _empty_state() -> Dictionary:
	return {"story_id": "", "node_id": "", "paused": false, "replaying": false, "facts": [], "completed": [], "events": [], "choices": {}, "transactions": {}, "entry_facts": {}, "replay_facts": []}


static func _validate_catalog(stories: Dictionary, groups: Array) -> Dictionary:
	if stories.is_empty() or stories.size() > MAX_STORIES:
		return _failure("Invalid story catalog size")
	var known := {}
	var completion_ids := {}
	for story_id: Variant in stories:
		if not _stable_id(story_id, "story.") or not stories[story_id] is Dictionary:
			return _failure("Invalid story definition ID")
		var story: Dictionary = stories[story_id]
		if not _fields(story, ["id", "stage", "entry", "nodes", "completion_event"]) or story.id != story_id:
			return _failure("Invalid story definition fields")
		if not _whole_number(story.stage, 1, 1000) or not _stable_id(story.completion_event, "event.") or completion_ids.has(story.completion_event):
			return _failure("Invalid or duplicated story completion event")
		completion_ids[story.completion_event] = true
		if not story.nodes is Dictionary or story.nodes.is_empty() or story.nodes.size() > MAX_NODES_PER_STORY or not story.entry is String or not story.nodes.has(story.entry):
			return _failure("Invalid story graph or entry")
		var choice_ids := {}
		for node_id: Variant in story.nodes:
			if not _local_id(node_id) or not story.nodes[node_id] is Dictionary:
				return _failure("Invalid story node identity")
			var node: Dictionary = story.nodes[node_id]
			if not node.get("type") is String:
				return _failure("Missing story node type")
			match node.type:
				"line":
					if not _fields(node, ["type", "speaker", "text_key", "next"]) or not _text_key(node.text_key) or not _speaker_id(node.speaker):
						return _failure("Invalid dialogue line")
				"choice":
					if not _fields(node, ["type", "choices"]) or not node.choices is Array or node.choices.size() < 2 or node.choices.size() > 8:
						return _failure("Invalid choice node")
					for option: Variant in node.choices:
						if not option is Dictionary or not _fields(option, ["id", "text_key", "next", "facts"]):
							return _failure("Invalid choice fields")
						if not _local_id(option.id) or choice_ids.has(option.id) or not _text_key(option.text_key) or not _fact_list(option.facts):
							return _failure("Invalid or duplicated choice identity or facts")
						choice_ids[option.id] = true
						for fact: String in option.facts:
							known[fact] = true
				"condition":
					if not _fields(node, ["type", "cases", "fallback"]) or not node.cases is Array or node.cases.is_empty() or node.cases.size() > 64:
						return _failure("Invalid condition node")
					for clause: Variant in node.cases:
						if not clause is Dictionary or not _fields(clause, ["all", "none", "next"]) or not _fact_list(clause.all) or not _fact_list(clause.none):
							return _failure("Invalid condition clause")
						if clause.all.is_empty() and clause.none.is_empty():
							return _failure("Unconditional cases are not allowed")
						for fact: String in clause.all:
							if fact in clause.none:
								return _failure("Condition requires and excludes the same fact")
				"action":
					if not _fields(node, ["type", "action_id", "next"]) or not _stable_id(node.action_id, "action."):
						return _failure("Invalid action node")
				_:
					return _failure("Unknown story node type")
			for target: Variant in _targets(node):
				if not target is String or (not target.is_empty() and not story.nodes.has(target)):
					return _failure("Story node references an unknown target")
	for group: Variant in groups:
		if not _fact_list(group, known) or group.size() < 2:
			return _failure("Invalid exclusive fact group")
	for story: Dictionary in stories.values():
		for node: Dictionary in story.nodes.values():
			if node.type == "choice":
				for option: Dictionary in node.choices:
					if _facts_conflict(option.facts, groups):
						return _failure("Choice grants mutually exclusive facts")
			if node.type == "condition":
				for index in node.cases.size():
					var clause: Dictionary = node.cases[index]
					if not _fact_list(clause.all, known) or not _fact_list(clause.none, known) or _facts_conflict(clause.all, groups):
						return _failure("Condition contains unknown or impossible facts")
					for previous in index:
						if _conditions_overlap(clause, node.cases[previous], groups):
							return _failure("Condition clauses can match simultaneously")
		var visited := {}
		if not _visit_graph(story.entry, story.nodes, {}, visited):
			return _failure("Story graph contains a cycle")
		if visited.size() != story.nodes.size():
			return _failure("Story graph contains unreachable nodes")
	return {"ok": true, "facts": known}


static func _visit_graph(id: String, nodes: Dictionary, active: Dictionary, visited: Dictionary) -> bool:
	if id.is_empty() or visited.has(id):
		return true
	if active.has(id):
		return false
	active[id] = true
	for target: String in _targets(nodes[id]):
		if not _visit_graph(target, nodes, active, visited):
			return false
	active.erase(id)
	visited[id] = true
	return true


static func _targets(node: Dictionary) -> Array:
	if node.type == "choice":
		var targets: Array = []
		for choice: Dictionary in node.choices:
			targets.append(choice.next)
		return targets
	if node.type == "condition":
		var targets: Array = [node.fallback]
		for clause: Dictionary in node.cases:
			targets.append(clause.next)
		return targets
	return [node.next]


static func _conditions_overlap(first: Dictionary, second: Dictionary, groups: Array) -> bool:
	var positive: Array = first.all.duplicate()
	for fact: String in second.all:
		if fact not in positive:
			positive.append(fact)
	for fact: String in positive:
		if fact in first.none or fact in second.none:
			return false
	return not _facts_conflict(positive, groups)


static func _facts_conflict(facts: Array, groups: Array) -> bool:
	for group: Array in groups:
		var found := 0
		for fact: String in group:
			found += int(fact in facts)
		if found > 1:
			return true
	return false


static func _fact_list(value: Variant, known: Variant = null) -> bool:
	if not value is Array:
		return false
	var seen := {}
	for fact: Variant in value:
		if not _stable_id(fact, "fact.") or seen.has(fact) or (known is Dictionary and not known.has(fact)):
			return false
		seen[fact] = true
	return true


static func _fields(value: Dictionary, required: Array) -> bool:
	if value.size() != required.size():
		return false
	for field: Variant in required:
		if not value.has(field):
			return false
	return true


static func _stable_id(value: Variant, prefix: String) -> bool:
	return value is String and value.begins_with(prefix) and _local_id(value.substr(prefix.length()))


static func _local_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 160:
		return false
	for character: String in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["_", "."]):
			return false
	return true


static func _text_key(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 240:
		return false
	for character: String in value:
		if not ((character >= "A" and character <= "Z") or (character >= "0" and character <= "9") or character == "_"):
			return false
	return true


static func _speaker_id(value: Variant) -> bool:
	return value in ["hero", "narrator"] or _stable_id(value, "npc.")


static func _transaction_id_valid(value: String) -> bool:
	if value.is_empty() or value.length() > 200 or value != value.strip_edges():
		return false
	for index in value.length():
		if value.unicode_at(index) < 33 or value.unicode_at(index) > 126:
			return false
	return true


static func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and value >= minimum and value <= maximum


static func _json_safe(value: Variant, depth: int, budget: Dictionary) -> bool:
	budget.visited += 1
	if depth > 32 or int(budget.visited) > MAX_COMMANDS * 20:
		return false
	if value == null or value is bool:
		return true
	if value is int or value is float:
		return is_finite(float(value))
	if value is String:
		return value.length() <= 4096
	if value is Array:
		for item: Variant in value:
			if not _json_safe(item, depth + 1, budget):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or key.length() > 4096 or not _json_safe(value[key], depth + 1, budget):
				return false
		return true
	return false


static func _success() -> Dictionary:
	return {"ok": true, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
