class_name DialogueFlow
extends RefCounted

signal changed
signal finished
signal story_completed(completed_story_id: String, npc_id: String)
signal consequence_source_ready(event_id: String, npc_id: String, card_id: String, world_center: Vector2)

var story_id := ""
var line_index := 0
var active_npc_id := ""
var completed: Array[String] = []
var settled_consequences: Array[String] = []
# 选项分支：玩家在带 choices 的行上选择后，先播放该选项自己的回应行，再回到主线下一行。
# 选项只改变措辞，不改变剧情后果；分支位置随存档保存。
var branch_choice := ""
var branch_index := 0
var _settling := false

const SCENE_SPEAKERS := ["hero", "npc", "narrator"]
const SOLO_SPEAKERS := ["hero", "narrator"]


func start_for_npc(npc_id: String) -> bool:
	if is_active() or has_departed(npc_id):
		return false
	var next_story := _story_for_npc(npc_id, completed)
	var definition := _dialogue_definition(next_story)
	if next_story.is_empty() or definition.is_empty():
		return false
	if definition.npc_id != "npc" and definition.npc_id != npc_id:
		return false
	story_id = next_story
	line_index = 0
	active_npc_id = npc_id
	branch_choice = ""
	branch_index = 0
	changed.emit()
	return true


# 独白：只有主角（和旁白）说话，不属于任何人物，也不需要牌桌上有谁。每段只播一次。
func start_solo(id: String) -> bool:
	var definition := _dialogue_definition(id)
	if is_active() or definition.is_empty() or not definition.get("solo", false):
		return false
	if id in completed or not _prerequisites_met(definition, completed):
		return false
	story_id = id
	line_index = 0
	active_npc_id = ""
	branch_choice = ""
	branch_index = 0
	changed.emit()
	return true


func advance() -> void:
	if not is_active():
		return
	var definition := _dialogue_definition(story_id)
	if definition.is_empty():
		cancel()
		return
	if branch_choice.is_empty():
		if _line_choices(definition.lines[line_index]).size() > 0:
			return
	else:
		var replies := _choice_lines(definition.lines[line_index], branch_choice)
		if branch_index < replies.size() - 1:
			branch_index += 1
			changed.emit()
			return
		branch_choice = ""
		branch_index = 0
	_step_main_line(definition)


func _step_main_line(definition: Dictionary) -> void:
	if line_index < definition.lines.size() - 1:
		line_index += 1
		changed.emit()
		return
	if story_id not in completed:
		completed.append(story_id)
	var finished_story := story_id
	var finished_npc := active_npc_id
	_clear_active()
	story_completed.emit(finished_story, finished_npc)
	changed.emit()
	finished.emit()


func choose(choice_id: String) -> Dictionary:
	if not awaiting_choice():
		return {"ok": false, "error": "No choice is waiting"}
	var line: Dictionary = _dialogue_definition(story_id).lines[line_index]
	var known := false
	for option: Dictionary in _line_choices(line):
		known = known or option.id == choice_id
	if not known:
		return {"ok": false, "error": "Choice is not offered"}
	if _choice_lines(line, choice_id).is_empty():
		_step_main_line(_dialogue_definition(story_id))
		return {"ok": true, "error": ""}
	branch_choice = choice_id
	branch_index = 0
	changed.emit()
	return {"ok": true, "error": ""}


func awaiting_choice() -> bool:
	if not is_active() or not branch_choice.is_empty():
		return false
	var definition := _dialogue_definition(story_id)
	return not definition.is_empty() and _line_choices(definition.lines[line_index]).size() > 0


func is_active() -> bool:
	return not story_id.is_empty()


func current_line() -> Dictionary:
	if not is_active():
		return {}
	var definition := _dialogue_definition(story_id)
	if definition.is_empty() or line_index < 0 or line_index >= definition.lines.size():
		return {}
	var line: Dictionary = definition.lines[line_index]
	if not branch_choice.is_empty():
		var replies := _choice_lines(line, branch_choice)
		if branch_index < replies.size():
			return replies[branch_index].duplicate(true)
	return line.duplicate(true)


# 供对话界面读取：旁白、待选选项、逐句标记与是否最后一句。
func presentation_info() -> Dictionary:
	if not is_active():
		return {}
	var definition := _dialogue_definition(story_id)
	if definition.is_empty():
		return {}
	var line := current_line()
	var total: int = definition.lines.size()
	var choices: Array = []
	if awaiting_choice():
		for option: Dictionary in _line_choices(definition.lines[line_index]):
			choices.append({"id": option.id, "text_key": option.text_key})
	var last_line := line_index == total - 1 and choices.is_empty()
	if last_line and not branch_choice.is_empty():
		last_line = branch_index >= _choice_lines(definition.lines[line_index], branch_choice).size() - 1
	return {
		"narrator": String(line.get("speaker", "")) == "narrator",
		# 人物登场前（主线行号小于 npc_hidden_until）不显示其立绘，用于先闻其声、后见其人。
		"npc_hidden": definition.get("solo", false) or line_index < int(definition.get("npc_hidden_until", 0)),
		"choices": choices,
		"marker": "%s:%d:%s:%d" % [story_id, line_index, branch_choice, branch_index],
		"total": total,
		"last_line": last_line,
	}


func to_data() -> Dictionary:
	return {"story_id": story_id, "line_index": line_index, "active_npc_id": active_npc_id, "completed": completed.duplicate(), "settled_consequences": settled_consequences.duplicate(), "branch": [branch_choice, branch_index]}


func restore(data: Dictionary) -> void:
	if not validate_data(data).is_empty():
		return
	story_id = String(data.story_id)
	line_index = int(data.line_index)
	active_npc_id = String(data.active_npc_id)
	completed.assign(data.completed)
	settled_consequences.assign(data.settled_consequences)
	var branch: Array = data.get("branch", ["", 0])
	branch_choice = String(branch[0])
	branch_index = int(branch[1])


func cancel() -> void:
	if not is_active():
		return
	_clear_active()
	changed.emit()


func reset() -> void:
	_clear_active()
	completed.clear()
	settled_consequences.clear()
	changed.emit()


func has_departed(npc_id: String) -> bool:
	return npc_has_departed(to_data(), npc_id)


# 该人物下一段会播放的剧情（已读完且不可重读时为空）。
func next_story(npc_id: String) -> String:
	var story := _story_for_npc(npc_id, completed)
	return "" if story in completed and not ContentCatalog.story_definition(story).get("repeatable", false) else story


func resolve_story_consequences(completed_story_id: String, npc_id: String, state: TableState) -> Dictionary:
	var result := {"ok": false, "departed": [] as Array[String], "sources": [], "created": [] as Array[String], "reason": ""}
	if _settling:
		result.reason = "Story consequences are already being resolved"
		return result
	if completed_story_id not in completed:
		result.reason = "Story has not been completed"
		return result
	var definition := _dialogue_definition(completed_story_id)
	if definition.is_empty() or (definition.npc_id != "npc" and definition.npc_id != npc_id):
		result.reason = "Story does not belong to the completing NPC"
		return result
	var pending: Array[Dictionary] = []
	for event_id: String in definition.get("consequences", []):
		if event_id in settled_consequences:
			continue
		var effect := ContentCatalog.event_definition(event_id)
		if effect.npc_id != npc_id:
			result.reason = "Consequence does not belong to the completing NPC"
			return result
		pending.append(effect)
	if pending.is_empty():
		result.ok = true
		return result
	if state == null:
		result.reason = "Story consequence has no table"
		return result
	var participant_error := _validate_participants(npc_id, state)
	if not participant_error.is_empty():
		result.reason = participant_error
		return result
	var card := _npc_card(npc_id, state)
	var card_at := state.card_position(card)
	var source_center := card_at + TableState.CARD_SIZE * 0.5
	var left_behind: Array[Dictionary] = []
	for effect: Dictionary in pending:
		for entry: Dictionary in effect.get("leave_cards", []):
			left_behind.append(entry)
	# 先在副本上验证留下的卡能否创建，避免人物已离开却没有产出。
	if not left_behind.is_empty():
		var preview := state.fork_empty()
		preview.restore(state.snapshot())
		preview.remove_card(card)
		for entry: Dictionary in left_behind:
			if preview.create_typed(StringName(entry.kind), card_at).is_empty():
				result.reason = "Departure cannot leave its cards on the table"
				return result
		if not preview.validate().is_empty():
			result.reason = "Departure would leave an invalid table"
			return result
	var stack := state.stack_for(card)
	var survivor_position := Vector2.ZERO
	var has_survivor := false
	if not stack.is_empty():
		for member: String in state.stacks[stack].cards:
			if member != card:
				survivor_position = state.card_position(member)
				has_survivor = true
				break
	_settling = true
	for effect: Dictionary in pending:
		consequence_source_ready.emit(String(effect.id), npc_id, card, source_center)
		result.sources.append({"event_id": effect.id, "npc_id": npc_id, "card_id": card, "world_center": source_center})
	state.remove_card(card)
	if has_survivor:
		state.move_stack(stack, survivor_position)
	for entry: Dictionary in left_behind:
		var created_stack := state.create_typed(StringName(entry.kind), card_at)
		var created_id := String(state.stacks[created_stack].cards[0])
		state.cards[created_id].metadata.merge(entry.get("metadata", {}), false)
		result.created.append(created_id)
		if has_survivor:
			state.settle_overlaps(stack)
	result.departed.append(card)
	for effect: Dictionary in pending:
		settled_consequences.append(String(effect.id))
	_settling = false
	result.ok = true
	return result


func _clear_active() -> void:
	story_id = ""
	line_index = 0
	active_npc_id = ""
	branch_choice = ""
	branch_index = 0


static func validate_data(data: Variant, state: TableState = null) -> String:
	# 旧存档没有 branch 字段（5 项），视为不在选项分支中。
	if not data is Dictionary or data.size() not in [5, 6] or (data.size() == 6 and not data.has("branch")):
		return "Dialogue fields are invalid"
	var branch: Variant = data.get("branch", ["", 0])
	if not branch is Array or branch.size() != 2 or not branch[0] is String or not _integer(branch[1], 0, 1000000):
		return "Dialogue branch is invalid"
	if not data.get("story_id") is String or not data.get("active_npc_id") is String:
		return "Dialogue identity is invalid"
	if not _integer(data.get("line_index"), 0, 1000000) or not data.get("completed") is Array:
		return "Dialogue progress is invalid"
	if not data.get("settled_consequences") is Array:
		return "Settled story consequences are invalid"
	var seen := {}
	var available_events := {}
	for id: Variant in data.completed:
		if not id is String or _dialogue_definition(id).is_empty():
			return "Completed dialogue ID is unknown"
		if seen.has(id):
			return "Completed dialogue ID is duplicated"
		seen[id] = true
		for event_id: String in _dialogue_definition(id).get("consequences", []):
			available_events[event_id] = true
	var settled_seen := {}
	for event_id: Variant in data.settled_consequences:
		if not event_id is String or not available_events.has(event_id) or settled_seen.has(event_id):
			return "Settled consequence is unknown, duplicated, or lacks its completed story"
		settled_seen[event_id] = true
	for id: String in seen:
		if not _prerequisites_met(_dialogue_definition(id), data.completed):
			return "Completed dialogue is missing a required story"
	if data.story_id.is_empty():
		if not data.active_npc_id.is_empty() or int(data.line_index) != 0 or not String(branch[0]).is_empty() or int(branch[1]) != 0:
			return "Inactive dialogue contains active progress"
		return ""
	var definition := _dialogue_definition(data.story_id)
	if definition.is_empty():
		return "Active dialogue ID is unknown"
	if int(data.line_index) >= definition.lines.size():
		return "Dialogue line is outside the story"
	if String(branch[0]).is_empty():
		if int(branch[1]) != 0:
			return "Dialogue branch position has no choice"
	elif int(branch[1]) >= _choice_lines(definition.lines[int(data.line_index)], String(branch[0])).size():
		return "Dialogue branch is outside its choice"
	if definition.get("solo", false):
		if not data.active_npc_id.is_empty() or data.story_id in data.completed or not _prerequisites_met(definition, data.completed):
			return "Solo dialogue has an NPC, was already read, or lacks a required story"
		return ""
	if _story_for_npc(data.active_npc_id, data.completed) != data.story_id:
		return "Dialogue does not match the NPC or completed stories"
	if definition.npc_id != "npc" and definition.npc_id != data.active_npc_id:
		return "Dialogue belongs to a different NPC"
	if npc_has_departed(data, data.active_npc_id):
		return "Active dialogue belongs to an NPC that has already departed"
	# 场景剧情发生在人物还没上桌时，不要求牌桌上有对话双方。
	if state != null and not definition.get("scene", false):
		return _validate_participants(data.active_npc_id, state)
	return ""


static func migrate_legacy_data(data: Variant) -> Variant:
	if not data is Dictionary or data.size() != 4:
		return null
	for field: String in ["story_id", "line_index", "active_npc_id", "completed"]:
		if not data.has(field):
			return null
	var migrated: Dictionary = data.duplicate(true)
	migrated["settled_consequences"] = []
	return migrated


static func npc_has_departed(data: Dictionary, npc_id: String) -> bool:
	for event_id: String in data.get("settled_consequences", []):
		var effect := ContentCatalog.event_definition(event_id)
		# 带 returns 的离场只是人暂时走开（卡离桌），之后还会回来接着说，不算“已经离开”。
		if effect.get("type") == "depart_npc" and effect.get("npc_id") == npc_id and not effect.get("returns", false):
			return true
	return false


static func _story_for_npc(npc_id: String, read_stories: Array) -> String:
	var npc := ContentCatalog.npc_definition(npc_id)
	var story_ids: Variant = npc.get("story_ids", [])
	if not story_ids is Array:
		return ""
	var repeat_story := ""
	for id: Variant in story_ids:
		if not id is String:
			return ""
		var definition := _dialogue_definition(id)
		if definition.is_empty() or definition.npc_id not in ["npc", npc_id]:
			continue
		if not _prerequisites_met(definition, read_stories):
			continue
		if id not in read_stories:
			return id
		if definition.get("repeatable", false):
			repeat_story = id
	return repeat_story


static func _prerequisites_met(definition: Dictionary, read_stories: Array) -> bool:
	for required: String in definition.get("requires_completed", []):
		if required not in read_stories:
			return false
	return true


static func _valid_story_requirements(definition: Dictionary, id: String) -> bool:
	if definition.has("repeatable") and not definition.repeatable is bool:
		return false
	var required: Variant = definition.get("requires_completed", [])
	if not required is Array:
		return false
	var seen := {}
	for previous: Variant in required:
		if not previous is String or previous == id or seen.has(previous) or ContentCatalog.story_definition(previous).is_empty():
			return false
		seen[previous] = true
	return true


static func _dialogue_definition(id: String) -> Dictionary:
	var definition := ContentCatalog.story_definition(id)
	if not definition.get("npc_id") is String or not definition.get("lines") is Array or definition.lines.is_empty():
		return {}
	if not _valid_story_requirements(definition, id):
		return {}
	# 独白没有人物（npc_id 为空），也不能有人物的台词、牌桌后果或重读。
	var solo: Variant = definition.get("solo", false)
	if not solo is bool or (solo and (not definition.npc_id.is_empty() or definition.has("repeatable") or definition.has("consequences"))):
		return {}
	if not solo and definition.npc_id != "npc" and ContentCatalog.npc_definition(definition.npc_id).is_empty():
		return {}
	for line: Variant in definition.lines:
		if not _valid_line(line, definition.npc_id) or (solo and line.speaker not in SOLO_SPEAKERS):
			return {}
		var choices: Variant = line.get("choices", [])
		if not choices is Array or choices.size() == 1 or choices.size() > 6:
			return {}
		var choice_ids := {}
		for option: Variant in choices:
			if not option is Dictionary or not option.get("id") is String or option.id.is_empty() or choice_ids.has(option.id):
				return {}
			if not option.get("text_key") is String or option.text_key.is_empty() or not option.get("lines", []) is Array:
				return {}
			for reply: Variant in option.get("lines", []):
				if not _valid_line(reply, definition.npc_id) or reply.has("choices") or (solo and reply.speaker not in SOLO_SPEAKERS):
					return {}
			choice_ids[option.id] = true
	var consequences: Variant = definition.get("consequences", [])
	if not consequences is Array:
		return {}
	# 场景剧情（人物尚未上桌）不能带离场等牌桌后果。
	if not definition.get("scene", false) is bool or (definition.get("scene", false) and not consequences.is_empty()):
		return {}
	var seen := {}
	for event_id: Variant in consequences:
		if not event_id is String or not event_id.begins_with("event.") or seen.has(event_id):
			return {}
		var effect := ContentCatalog.event_definition(event_id)
		for field: String in effect:
			if field not in ["id", "type", "npc_id", "leave_cards", "returns"]:
				return {}
		if not effect.get("returns", false) is bool:
			return {}
		if effect.get("id") != event_id or effect.get("type") != "depart_npc" or not effect.get("npc_id") is String:
			return {}
		if ContentCatalog.npc_definition(effect.npc_id).is_empty() or (definition.npc_id != "npc" and effect.npc_id != definition.npc_id):
			return {}
		var leave: Variant = effect.get("leave_cards", [])
		if not leave is Array or leave.size() > 4:
			return {}
		for entry: Variant in leave:
			if not entry is Dictionary or not entry.get("kind") is String or not entry.get("metadata", {}) is Dictionary:
				return {}
			if ContentCatalog.card_definition(ContentCatalog.card_id_for_kind(StringName(entry.kind))).is_empty():
				return {}
		seen[event_id] = true
	return definition


static func _valid_line(line: Variant, npc_id: String) -> bool:
	if not line is Dictionary or not line.get("speaker") is String or not line.get("text_key") is String or line.text_key.is_empty():
		return false
	return line.speaker in SCENE_SPEAKERS or line.speaker == npc_id


static func _line_choices(line: Dictionary) -> Array:
	return line.get("choices", [])


static func _choice_lines(line: Dictionary, choice_id: String) -> Array:
	for option: Dictionary in _line_choices(line):
		if option.id == choice_id:
			return option.get("lines", [])
	return []


static func _npc_card(npc_id: String, state: TableState) -> String:
	for id: String in state.cards:
		if state.cards[id].metadata.get("npc_id", "") == npc_id:
			return id
	return ""


static func _validate_participants(npc_id: String, state: TableState) -> String:
	if not state.validate().is_empty():
		return "Dialogue table is invalid"
	var hero := ""
	var npc := ""
	var definition := ContentCatalog.npc_definition(npc_id)
	var card_definition := ContentCatalog.card_definition(definition.get("card_id", ""))
	var expected_kind := StringName(card_definition.get("kind", ""))
	if expected_kind.is_empty():
		return "Dialogue NPC has no supported card"
	for id: String in state.cards:
		if state.card_kind(id) == &"hero":
			if not hero.is_empty() or state.cards[id].zone != &"board":
				return "Dialogue player card is invalid"
			hero = id
		if state.cards[id].metadata.get("npc_id", "") == npc_id:
			if not npc.is_empty() or state.card_kind(id) != expected_kind:
				return "Dialogue NPC card is invalid"
			npc = id
	if hero.is_empty() or npc.is_empty():
		return "Dialogue participant is missing"
	if state.cards[npc].zone == &"queue":
		return "" if expected_kind == &"customer" else "Dialogue NPC cannot wait in the queue"
	var hero_stack := state.stack_for(hero)
	if hero_stack.is_empty() or state.stack_for(npc) != hero_stack:
		return "Dialogue participants no longer share a stack"
	return ""


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum
