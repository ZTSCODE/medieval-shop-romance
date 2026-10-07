class_name OnboardingGoals
extends RefCounted

# 新手目标的唯一权威：所有完成都经由 report()，界面只读取状态并补播动画。
# 进度随每个存档保存（存档可选字段 onboarding）；新旅程从头开始，旧存档缺字段时同样从头开始。

signal changed

const DEFINITION_PATH := "res://data/onboarding_goals.json"
const SAVE_VERSION := 1
const HISTORY_LIMIT := 64

var stages: Array[Dictionary] = []
var stage_index := 0
var completed: Dictionary = {}
var seen_events: Dictionary = {}
var history: PackedStringArray = []
var _sequence := 0


func _init(definition_path: String = DEFINITION_PATH) -> void:
	stages = load_definition(definition_path)


static func load_definition(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not parsed is Dictionary or not parsed.get("stages") is Array:
		push_error("Onboarding definition is invalid: " + path)
		return result
	var goal_ids := {}
	for raw: Variant in parsed.stages:
		if not raw is Dictionary or not raw.get("id") is String or not raw.get("title_key") is String or not raw.get("goals") is Array:
			push_error("Onboarding stage is invalid")
			return [] as Array[Dictionary]
		var goals: Array[Dictionary] = []
		for goal: Variant in raw.goals:
			if not goal is Dictionary or not goal.get("id") is String or not goal.get("text_key") is String or not goal.get("event") is String or goal_ids.has(goal.id):
				push_error("Onboarding goal is invalid")
				return [] as Array[Dictionary]
			goal_ids[goal.id] = true
			goals.append({"id": String(goal.id), "text_key": String(goal.text_key), "event": StringName(goal.event)})
		if goals.is_empty():
			continue
		result.append({"id": String(raw.id), "title_key": String(raw.title_key), "goals": goals})
	return result


func is_finished() -> bool:
	return stage_index >= stages.size()


func current_stage() -> Dictionary:
	return {} if is_finished() else stages[stage_index]


func is_goal_complete(goal_id: String) -> bool:
	return completed.has(goal_id)


func stage_done_count(index: int) -> int:
	if index < 0 or index >= stages.size():
		return 0
	var count := 0
	for goal: Dictionary in stages[index].goals:
		if completed.has(goal.id):
			count += 1
	return count


# 唯一结果入口：只完成当前阶段的目标；提前发生的事件记为已见，进入对应阶段时补记。
func report(event: StringName, detail: String = "") -> bool:
	if event.is_empty() or is_finished():
		return false
	var first_seen := not seen_events.has(event)
	seen_events[event] = true
	var progressed := _complete_matching(event, "report" + ("" if detail.is_empty() else "(" + detail + ")"))
	if not progressed and first_seen:
		_record("seen %s (later stage)" % event)
		changed.emit()
	return progressed


func reset() -> void:
	stage_index = 0
	completed.clear()
	seen_events.clear()
	_record("reset")
	changed.emit()


func to_data() -> Dictionary:
	var done: Array[String] = []
	for id: String in completed:
		done.append(id)
	var seen: Array[String] = []
	for event: StringName in seen_events:
		seen.append(String(event))
	return {"version": SAVE_VERSION, "completed": done, "seen": seen}


# 存档内容不可信：未知 ID 丢弃，阶段由已完成目标重新推导。
func restore(data: Variant) -> bool:
	stage_index = 0
	completed.clear()
	seen_events.clear()
	if not data is Dictionary or int(data.get("version", 0)) != SAVE_VERSION or not data.get("completed") is Array or not data.get("seen") is Array:
		return false
	var known := {}
	for stage: Dictionary in stages:
		for goal: Dictionary in stage.goals:
			known[goal.id] = true
	for id: Variant in data.completed:
		if id is String and known.has(id):
			completed[id] = true
	for event: Variant in data.seen:
		if event is String and not event.is_empty():
			seen_events[StringName(event)] = true
	_settle_stage("restore")
	return true


# 存档编解码使用：形状不对时返回空字典，读档时按“从头开始”处理，不因教学数据拒绝整个存档。
static func sanitize(value: Variant) -> Dictionary:
	if not value is Dictionary or int(value.get("version", 0)) != SAVE_VERSION or not value.get("completed") is Array or not value.get("seen") is Array:
		return {}
	var result := {"version": SAVE_VERSION, "completed": [], "seen": []}
	for id: Variant in value.completed:
		if id is String and result.completed.size() < 256:
			result.completed.append(id)
	for event: Variant in value.seen:
		if event is String and result.seen.size() < 256:
			result.seen.append(event)
	return result


static func fresh_data() -> Dictionary:
	return {"version": SAVE_VERSION, "completed": [], "seen": []}


func debug_text() -> String:
	return "\n".join(history)


func _complete_matching(event: StringName, cause: String) -> bool:
	var stage := current_stage()
	if stage.is_empty():
		return false
	var progressed := false
	for goal: Dictionary in stage.goals:
		if goal.event == event and not completed.has(goal.id):
			completed[goal.id] = true
			progressed = true
			_record("%s %s -> goal %s" % [cause, event, goal.id])
	if progressed:
		_settle_stage("advance")
		changed.emit()
	return progressed


func _settle_stage(cause: String) -> void:
	while not is_finished():
		var stage := current_stage()
		for goal: Dictionary in stage.goals:
			if not completed.has(goal.id) and seen_events.has(goal.event):
				completed[goal.id] = true
				_record("%s carried %s -> goal %s" % [cause, goal.event, goal.id])
		if stage_done_count(stage_index) < stage.goals.size():
			return
		_record("%s stage %s complete" % [cause, stage.id])
		stage_index += 1


func _record(text: String) -> void:
	_sequence += 1
	history.append("#%d %s" % [_sequence, text])
	if history.size() > HISTORY_LIMIT:
		history = history.slice(history.size() - HISTORY_LIMIT)
