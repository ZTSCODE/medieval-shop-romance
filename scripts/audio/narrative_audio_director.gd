extends Node
## Reads authored beats, not keywords inferred at runtime. Quiet lines are intentional.
## Pending cues expire at a new line; text reveal, pauses, and save restores are respected.
const MAP_PATH := "res://assets/audio/narrative_cues.json"
var service: Node
var entries: Dictionary = {}
var session_contexts: Array = []
var marker := ""
var text_key := ""
var pending: Array[Dictionary] = []
var visible_characters := 0
var elapsed := 0.0
var _last_cue_at := -10.0
var restoring := false
var line_active := false
var _line_text := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	service = get_parent()
	if FileAccess.file_exists(MAP_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
		if parsed is Dictionary:
			entries = parsed.get("lines", {})
			session_contexts = parsed.get("session_contexts", [])

func enter_line(key: String, next_marker: String, text: String) -> void:
	var authored_spec: Dictionary = entries.get(key, {})
	if not authored_spec.is_empty() and (String(authored_spec.get("marker", "")) != next_marker or text not in authored_spec.get("quotes", {}).values()):
		pending.clear()
		line_active = false
		if marker != next_marker or text_key != key or text != _line_text:
			service._record("narrative.incompatible_line", {"text_key": key, "marker": next_marker})
		marker = next_marker
		text_key = key
		_line_text = text
		return
	if next_marker == marker and key == text_key:
		if text != _line_text:
			_line_text = text
			for cue: Dictionary in pending:
				cue["at_character"] = _phrase_offset(cue, text)
				cue.erase("revealed_at")
		return
	_line_text = text
	marker = next_marker
	text_key = key
	pending.clear()
	visible_characters = 0
	elapsed = 0.0
	_last_cue_at = -10.0
	line_active = true
	var spec: Dictionary = entries.get(key, {})
	if spec.is_empty():
		return # Preserve the physical environment; do not guess from dialogue text.
	service.set_narrative_soundscape(String(spec.get("environment", "")), String(spec.get("music", "")))
	service._record("narrative.line", {"text_key": key, "marker": marker, "environment": spec.get("environment", ""), "restoring": restoring})
	if restoring:
		return
	var authored: Array = spec.get("cues", []).duplicate(true)
	for stop: Dictionary in spec.get("stops", []):
		var command := stop.duplicate(true)
		command["stop_events"] = command.events
		authored.append(command)
	for raw: Dictionary in authored:
		var cue := raw.duplicate(true)
		cue["at_character"] = _phrase_offset(cue, text)
		if int(cue.at_character) >= 0:
			pending.append(cue)

func reveal(count: int) -> void:
	visible_characters = count

func end_line() -> void:
	pending.clear()
	line_active = false
	marker = ""
	text_key = ""

func reset() -> void:
	end_line()
	service.cancel_narrative_voices()
	service.clear_narrative_soundscape()

func _process(delta: float) -> void:
	if not line_active or restoring or service._paused or service._menu or service._cinematic:
		return
	elapsed += maxf(delta, 0.0)
	if elapsed - _last_cue_at < 0.20:
		return
	for index in pending.size():
		var cue: Dictionary = pending[index]
		if visible_characters < int(cue.at_character):
			continue
		if not cue.has("revealed_at"):
			cue["revealed_at"] = elapsed
		if elapsed - float(cue.revealed_at) < float(cue.get("delay", cue.get("delay_seconds", 0.0))):
			continue
		pending.remove_at(index)
		var context := {"text_key": text_key, "marker": marker, "phrase": cue.get("phrase", ""), "allow_paused": true, "gain_offset_db": float(cue.get("gain_offset_db", 0.0)), "pan": float(cue.get("pan", 0.0))}
		if cue.has("stop_events"):
			service.stop_events(cue.stop_events, float(cue.get("fade_seconds", 0.06)))
		else:
			service.play_event(String(cue.event), context)
		_last_cue_at = elapsed
		break


func restore_scene(completed: Array, opening_stage: String) -> void:
	for context: Dictionary in session_contexts:
		var matches := true
		for story_id: String in context.get("requires_completed", []):
			if story_id not in completed:
				matches = false
		if context.has("opening_stages") and opening_stage not in context.opening_stages:
			matches = false
		if matches:
			service.set_narrative_soundscape(context.environment, context.music)
			return


func _phrase_offset(cue: Dictionary, text: String) -> int:
	var phrase := String(cue.get("phrase", ""))
	if not phrase.is_empty() and text.find(phrase) < 0:
		for translated: String in cue.get("phrases", {}).values():
			if text.find(translated) >= 0:
				phrase = translated
				break
	var offset := text.find(phrase) if not phrase.is_empty() else 0
	if offset < 0:
		return -1 # Missing phrases must never trigger at an invented offset.
	return offset + (mini(2, phrase.length()) if not phrase.is_empty() else 0)
