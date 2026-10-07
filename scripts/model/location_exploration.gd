class_name LocationExploration
extends RefCounted

# 通用地点探索：“你”与一张带 explore 定义的地点卡单独成叠时计时，到时产出卡牌。
# 唯一结果入口是 advance()；进度只在内存里，不入档（读档后从零开始，与交谈准备一致）。
# 卡牌定义："explore": {"duration": 秒, "consumes": 是否用掉地点卡, "outputs": [{"kind", "metadata"}],
#            "blocked_by": [牌桌上还有这些种类的卡时不能探索，比如先得和站在那儿的人说完话]}

signal outputs_created(card_ids: Array[String], source_position: Vector2, source_id: String)
signal explored(card_definition_id: String)

var state: TableState
var _elapsed: Dictionary = {}  # 工作键（叠 + 成员变动号）-> 已探索秒数


func advance(delta: float, suspended: bool = false) -> void:
	if state == null:
		return
	var active := {}
	for stack: String in _work_stacks():
		var key := _work_key(stack)
		active[key] = true
		if suspended or delta <= 0.0 or not is_finite(delta):
			continue
		var location := _location_card(stack)
		var duration := _duration(location)
		_elapsed[key] = minf(float(_elapsed.get(key, 0.0)) + delta, duration)
		if float(_elapsed[key]) >= duration:
			_elapsed.erase(key)
			active.erase(key)
			_finish(stack, location)
	for key: String in _elapsed.keys():
		if not active.has(key):
			_elapsed.erase(key)


func work_progress() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if state == null:
		return rows
	for stack: String in _work_stacks():
		var duration := _duration(_location_card(stack))
		rows.append({"stack_id": stack, "progress": clampf(float(_elapsed.get(_work_key(stack), 0.0)) / duration, 0.0, 1.0)})
	return rows


func reset() -> void:
	_elapsed.clear()


static func definition_for(card_definition_id: String) -> Dictionary:
	var explore: Variant = ContentCatalog.card_definition(card_definition_id).get("explore", {})
	if not explore is Dictionary or explore.is_empty() or not explore.get("outputs", []) is Array:
		return {}
	var duration: Variant = explore.get("duration", 0.0)
	if not (duration is int or duration is float) or float(duration) <= 0.0:
		return {}
	return explore


func _work_stacks() -> Array[String]:
	var result: Array[String] = []
	for stack: String in state.stacks:
		var members: Array = state.stacks[stack].cards
		if members.size() == 2 and not _location_card(stack).is_empty():
			var kinds := [String(state.card_kind(members[0])), String(state.card_kind(members[1]))]
			if "hero" in kinds and not _blocked(_location_card(stack)):
				result.append(stack)
	return result


func _blocked(location: String) -> bool:
	var blockers: Variant = definition_for(state.definition_id_for_card(location)).get("blocked_by", [])
	if not blockers is Array or blockers.is_empty():
		return false
	for id: String in state.cards:
		if String(state.card_kind(id)) in blockers and state.cards[id].zone == &"board":
			return true
	return false


func _location_card(stack: String) -> String:
	for id: String in state.stacks[stack].cards:
		if state.card_kind(id) != &"hero" and not definition_for(state.definition_id_for_card(id)).is_empty():
			return id
	return ""


func _duration(location: String) -> float:
	return float(definition_for(state.definition_id_for_card(location)).get("duration", 1.0))


func _work_key(stack: String) -> String:
	var parts: PackedStringArray = [stack]
	for id: String in state.stacks[stack].cards:
		parts.append("%s:%d" % [id, state.membership_revision_for_card(id)])
	return "|".join(parts)


func _finish(stack: String, location: String) -> void:
	var definition_id := state.definition_id_for_card(location)
	var explore := definition_for(definition_id)
	var at := state.card_position(location)
	var consumes := bool(explore.get("consumes", false))
	# 先在副本上验证产出，避免容量或唯一性限制导致只消耗、不产出。
	var preview := state.fork_empty()
	preview.restore(state.snapshot())
	if consumes:
		preview.remove_card(location)
	for entry: Dictionary in explore.outputs:
		if preview.create_typed(StringName(entry.kind), at).is_empty():
			return
	if not preview.validate().is_empty():
		return
	var hero_stack := stack
	if consumes:
		state.remove_card(location)
	var created: Array[String] = []
	for entry: Dictionary in explore.outputs:
		var output_stack := state.create_typed(StringName(entry.kind), at)
		var id := String(state.stacks[output_stack].cards[0])
		state.cards[id].metadata.merge(entry.get("metadata", {}), false)
		created.append(id)
	if state.stacks.has(hero_stack):
		state.settle_overlaps(hero_stack)
	outputs_created.emit(created, at, location)
	explored.emit(definition_id)
