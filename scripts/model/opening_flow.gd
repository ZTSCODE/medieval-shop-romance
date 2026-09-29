class_name OpeningFlow
extends RefCounted

signal changed
signal outputs_created(card_ids: Array[String], source_id: StringName)
signal revealed

const STAGES := ["inactive", "intro", "explore", "complete"]

var stage: StringName = &"inactive"
var intro_index := 0
var elapsed := 0.0
var state: TableState
var output_bounds := TableState.WORLD_BOUNDS
var _last_work_stack := ""


func start(table: TableState) -> void:
	deactivate(table)
	var definition := ContentCatalog.opening_definition()
	if table == null or definition.is_empty() or not _definition_valid(definition):
		return
	state = table
	var preview := state.fork_empty()
	var center := _placement_bounds().get_center()
	for entry: Dictionary in definition.get("initial_cards", []):
		var offset: Array = entry.get("offset", [0.0, 0.0])
		var stack := preview.create_typed(StringName(entry.kind), center + Vector2(float(offset[0]), float(offset[1])))
		if stack.is_empty():
			return
		var id := String(preview.stacks[stack].cards[0])
		preview.cards[id].metadata.merge(entry.get("metadata", {}), false)
	if not preview.validate().is_empty():
		return
	state.restore(preview.snapshot())
	stage = &"intro" if intro_page_count() > 0 else (&"explore" if _has_exploration() else &"complete")
	intro_index = 0
	elapsed = 0.0
	_last_work_stack = ""
	changed.emit()
	if stage == &"complete":
		revealed.emit()


func deactivate(table: TableState) -> void:
	state = table
	stage = &"inactive"
	intro_index = 0
	elapsed = 0.0
	_last_work_stack = ""
	changed.emit()


func advance_intro() -> void:
	if stage != &"intro":
		return
	if intro_index < intro_page_count() - 1:
		intro_index += 1
	else:
		stage = &"explore" if _has_exploration() else &"complete"
		if stage == &"complete":
			revealed.emit()
	changed.emit()


func advance(delta: float, suspended: bool = false) -> void:
	if stage != &"explore" or state == null:
		return
	var stack := work_stack_id()
	if stack.is_empty():
		if elapsed != 0.0 or not _last_work_stack.is_empty():
			elapsed = 0.0
			_last_work_stack = ""
			changed.emit()
		return
	var work_key := _work_key(stack)
	if _last_work_stack != work_key:
		elapsed = 0.0
		_last_work_stack = work_key
		changed.emit()
	if suspended:
		return
	if delta <= 0.0 or not is_finite(delta):
		return
	elapsed = minf(elapsed + delta, explore_seconds())
	if elapsed >= explore_seconds():
		_finish_exploration(stack)


func progress() -> float:
	return clampf(elapsed / explore_seconds(), 0.0, 1.0)


func work_stack_id() -> String:
	return _find_work_stack(state)


func to_data() -> Dictionary:
	var saved_elapsed := elapsed
	if stage == &"explore" and (_work_key(work_stack_id()).is_empty() or _work_key(work_stack_id()) != _last_work_stack):
		saved_elapsed = 0.0
	return {"stage": String(stage), "intro_index": intro_index, "elapsed": saved_elapsed}


func restore(data: Variant, table: TableState) -> bool:
	if not validate_data(data, table).is_empty():
		return false
	state = table
	stage = StringName(data.stage)
	intro_index = int(data.intro_index)
	elapsed = float(data.elapsed)
	_last_work_stack = _work_key(work_stack_id()) if stage == &"explore" else ""
	return true


func _work_key(stack: String) -> String:
	if stack.is_empty() or state == null or not state.stacks.has(stack):
		return ""
	var parts: PackedStringArray = [stack]
	for id: String in state.stacks[stack].cards:
		parts.append("%s:%d" % [id, state.membership_revision_for_card(id)])
	return "|".join(parts)


static func validate_data(data: Variant, table: TableState) -> String:
	if not data is Dictionary or data.size() != 3:
		return "Opening fields are invalid"
	if not data.get("stage") is String or data.stage not in STAGES:
		return "Opening stage is invalid"
	if not _integer(data.get("intro_index"), 0, maxi(intro_page_count() - 1, 0)):
		return "Opening page is invalid"
	if not _number(data.get("elapsed"), 0.0, explore_seconds()):
		return "Opening timer is invalid"
	if table == null or not table.validate().is_empty():
		return "Opening table is invalid"
	if data.stage == "inactive":
		if int(data.intro_index) != 0 or float(data.elapsed) != 0.0:
			return "Inactive opening contains progress"
		return ""
	var definition := ContentCatalog.opening_definition()
	if definition.is_empty() or not _definition_valid(definition):
		return "Opening definition is unavailable"
	if data.stage != "complete":
		var expected: Array = []
		for entry: Dictionary in definition.get("initial_cards", []):
			expected.append(String(entry.kind))
		for id: String in table.cards:
			var kind := String(table.card_kind(id))
			if not kind in expected or table.cards[id].zone != &"board":
				return "Opening card set is invalid"
			expected.erase(kind)
		if not expected.is_empty():
			return "Opening card count is invalid"
	match data.stage:
		"intro":
			if intro_page_count() == 0 or float(data.elapsed) != 0.0:
				return "Introduction cannot contain exploration progress"
		"explore":
			if not _has_exploration() or int(data.intro_index) != maxi(intro_page_count() - 1, 0) or float(data.elapsed) >= explore_seconds():
				return "Exploration progress is invalid"
			if float(data.elapsed) > 0.0 and _find_work_stack(table).is_empty():
				return "Exploration progress has no matching stack"
		"complete":
			var duration := explore_seconds() if _has_exploration() else 0.0
			if int(data.intro_index) != maxi(intro_page_count() - 1, 0) or float(data.elapsed) != duration:
				return "Completed opening has invalid progress"
	return ""


static func _find_work_stack(table: TableState) -> String:
	if table == null:
		return ""
	var required: Array = ContentCatalog.opening_definition().get("explore", {}).get("required_kinds", [])
	if required.is_empty():
		return ""
	for id: String in table.stacks:
		var members: Array = table.stacks[id].cards
		if members.size() != required.size():
			continue
		var remaining := required.duplicate()
		for member: String in members:
			remaining.erase(String(table.card_kind(member)))
		if remaining.is_empty():
			return id
	return ""


func _finish_exploration(stack: String) -> void:
	var exploration: Dictionary = ContentCatalog.opening_definition().get("explore", {})
	var consumed: Array = exploration.get("consumed_kinds", []).duplicate()
	var members: Array = state.stacks[stack].cards.duplicate()
	var source_id := String(members[0])
	var source := state.card_position(source_id)
	var outputs: Array = exploration.get("outputs", [])
	# 先在副本上验证创建，避免容量或唯一性限制导致只消耗、不产出。
	var preview := state.fork_empty()
	preview.restore(state.snapshot())
	for id: String in members:
		var kind := String(state.card_kind(id))
		if kind in consumed:
			consumed.erase(kind)
			source_id = id
			source = state.card_position(id)
			preview.remove_card(id)
	for entry: Dictionary in outputs:
		var output_stack := preview.create_typed(StringName(entry.kind), source)
		if output_stack.is_empty():
			elapsed = 0.0
			return
		var output_id := String(preview.stacks[output_stack].cards[0])
		preview.cards[output_id].metadata.merge(entry.get("metadata", {}), false)
	if not preview.validate().is_empty():
		elapsed = 0.0
		return
	consumed = exploration.get("consumed_kinds", []).duplicate()
	for id: String in members:
		var kind := String(state.card_kind(id))
		if kind in consumed:
			consumed.erase(kind)
			state.remove_card(id)
	var created: Array[String] = []
	for index in outputs.size():
		created.append(_create_entry(outputs[index], _output_position(source, index)))
	stage = &"complete"
	elapsed = explore_seconds()
	_last_work_stack = ""
	outputs_created.emit(created, StringName(source_id))
	revealed.emit()
	changed.emit()


static func intro_page_count() -> int:
	return ContentCatalog.opening_definition().get("pages", []).size()


static func explore_seconds() -> float:
	var value: Variant = ContentCatalog.opening_definition().get("explore", {}).get("duration", 1.0)
	return float(value) if _number(value, 0.001, 86400.0) else 1.0


static func _has_exploration() -> bool:
	return not ContentCatalog.opening_definition().get("explore", {}).get("required_kinds", []).is_empty()


static func _definition_valid(definition: Dictionary) -> bool:
	var pages: Variant = definition.get("pages", [])
	var initial: Variant = definition.get("initial_cards", [])
	var exploration: Variant = definition.get("explore", {})
	if not pages is Array or not initial is Array or not exploration is Dictionary or initial.size() > TableState.MAX_CARDS:
		return false
	for page: Variant in pages:
		if not page is String or page.is_empty():
			return false
	var required: Variant = exploration.get("required_kinds", [])
	var consumed: Variant = exploration.get("consumed_kinds", [])
	var outputs: Variant = exploration.get("outputs", [])
	if not required is Array or not consumed is Array or not outputs is Array:
		return false
	if required.size() > TableState.MAX_STACK or (not exploration.is_empty() and (required.is_empty() or not _number(exploration.get("duration"), 0.001, 86400.0))):
		return false
	var available: Array = []
	for entry: Variant in initial + outputs:
		if not entry is Dictionary or not entry.get("kind") is String or not entry.get("metadata", {}) is Dictionary:
			return false
		if ContentCatalog.card_definition(ContentCatalog.card_id_for_kind(StringName(entry.kind))).is_empty():
			return false
		var offset: Variant = entry.get("offset", [0.0, 0.0])
		if not offset is Array or offset.size() != 2 or not _number(offset[0], -100000.0, 100000.0) or not _number(offset[1], -100000.0, 100000.0):
			return false
	for entry: Dictionary in initial:
		available.append(String(entry.kind))
	for kind: Variant in required:
		if not kind is String or not kind in available:
			return false
		available.erase(kind)
	available = required.duplicate()
	for kind: Variant in consumed:
		if not kind is String or not kind in available:
			return false
		available.erase(kind)
	return initial.size() - consumed.size() + outputs.size() <= TableState.MAX_CARDS


func _create_entry(entry: Dictionary, at: Vector2) -> String:
	var stack := state.create_typed(StringName(entry.kind), at)
	if stack.is_empty():
		return ""
	var id := String(state.stacks[stack].cards[0])
	state.cards[id].metadata.merge(entry.get("metadata", {}), false)
	return id


func _placement_bounds() -> Rect2:
	var bounds := output_bounds.intersection(TableState.WORLD_BOUNDS.grow(-20.0))
	if bounds.size.x < TableState.CARD_SIZE.x or bounds.size.y < TableState.CARD_SIZE.y:
		return TableState.WORLD_BOUNDS.grow(-20.0)
	return bounds


func _output_position(source: Vector2, index: int, whole_board: bool = false) -> Vector2:
	var bounds := TableState.WORLD_BOUNDS.grow(-20.0) if whole_board else _placement_bounds()
	var size := TableState.CARD_SIZE
	var lower := bounds.position
	var upper := bounds.end - size
	var spacing := size + Vector2(28.0, 28.0)
	var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]
	for ring in range(1, 9):
		for offset in directions.size():
			var direction := directions[(index + offset) % directions.size()]
			var at := (source + direction * spacing * ring).clamp(lower, upper)
			if _is_clear(at):
				return at
	var candidates: Array[Vector2] = []
	var columns := ceili((upper.x - lower.x) / 20.0)
	var rows := ceili((upper.y - lower.y) / 20.0)
	for row in range(rows + 1):
		for column in range(columns + 1):
			candidates.append(Vector2(minf(lower.x + column * 20.0, upper.x), minf(lower.y + row * 20.0, upper.y)))
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(source) < b.distance_squared_to(source))
	for at: Vector2 in candidates:
		if _is_clear(at):
			return at
	# 放大后可视区放不下大牌时，在真实棋盘寻找空位，不能重叠生成。
	if not whole_board:
		return _output_position(source, index, true)
	return source.clamp(lower, upper)


func _is_clear(at: Vector2) -> bool:
	var rect := Rect2(at, TableState.CARD_SIZE).grow(8.0)
	for id: String in state.stacks:
		if rect.intersects(state.stack_rect(id).grow(8.0)):
			return false
	return true


static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, float(minimum), float(maximum)) and floorf(float(value)) == float(value)
