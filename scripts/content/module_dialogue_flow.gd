class_name ModuleDialogueFlow
extends DialogueFlow

const StorySession = preload("res://scripts/content/module_story_session.gd")

var session: StorySession
var _scene_npc_id := ""
var _last_npc_id := ""
var _previous_story_id := ""


func configure(value: StorySession, scene_npc_id: String = "") -> void:
	if session != null:
		if session.changed.is_connected(_sync_session):
			session.changed.disconnect(_sync_session)
		if session.story_completed.is_connected(_completed):
			session.story_completed.disconnect(_completed)
	session = value
	_scene_npc_id = scene_npc_id
	_last_npc_id = scene_npc_id
	if session != null:
		session.changed.connect(_sync_session)
		session.story_completed.connect(_completed)
	_sync_session()


# 场次资格由章节调度器检查；适配层不能凭 NPC 身份自动跳到下一场。
func present(next_story_id: String, npc_id: String) -> Dictionary:
	if session == null or ContentCatalog.npc_definition(npc_id).is_empty():
		return {"ok": false, "error": "Unknown dialogue participant"}
	var old_npc := _scene_npc_id
	var old_last := _last_npc_id
	_scene_npc_id = npc_id
	_last_npc_id = npc_id
	var result := session.start(next_story_id)
	if not result.ok:
		_scene_npc_id = old_npc
		_last_npc_id = old_last
	return result


func start_for_npc(_npc_id: String) -> bool:
	return false


func is_active() -> bool:
	if session == null:
		return false
	return session.current_node().get("type", "") in ["line", "choice"]


func current_line() -> Dictionary:
	if not is_active():
		return {}
	var node := session.current_node()
	if node.type == "choice":
		return {"speaker": "hero", "text_key": "DIALOGUE_CHOOSE_REPLY"}
	return {"speaker": node.speaker, "text_key": node.text_key}


func presentation_info() -> Dictionary:
	if not is_active():
		return {}
	var node := session.current_node()
	return {"marker": "%s:%s" % [node.story_id, node.node_id],
		"choices": node.get("choices", []).duplicate(true),
		"locked_choice_id": node.get("locked_choice_id", ""),
		"narrator": node.get("speaker", "") == "narrator",
		"total": 0, "last_line": false}


func choose(choice_id: String) -> Dictionary:
	if session == null:
		return {"ok": false, "error": "Dialogue is not configured"}
	return session.choose(choice_id)


func advance() -> void:
	if session != null and session.current_node().get("type", "") == "line":
		session.advance()


func set_menu_paused(value: bool) -> void:
	if session != null and (not session.current_node().is_empty() or session.is_paused()):
		session.set_paused(value, false)


# 正式存档必须使用联合检查点；不能伪装成旧版的线性对白存档。
func to_data() -> Dictionary:
	return {"module_story_session": session.to_data() if session != null else {}}


func _sync_session() -> void:
	var node := session.current_node() if session != null else {}
	story_id = String(node.get("story_id", ""))
	line_index = 0
	if session != null:
		completed.assign(session.to_data().state.completed)
	var speaker := String(node.get("speaker", ""))
	if speaker.begins_with("npc."):
		_last_npc_id = speaker
	active_npc_id = _last_npc_id if not _last_npc_id.is_empty() else _scene_npc_id
	var ended := story_id.is_empty() and not _previous_story_id.is_empty()
	_previous_story_id = story_id
	changed.emit()
	if ended:
		finished.emit()


func _completed(finished_story: String, _event_id: String) -> void:
	story_completed.emit(finished_story, _scene_npc_id)
