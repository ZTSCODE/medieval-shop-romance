class_name AudioEvents
extends RefCounted
## Optional presentation facade: isolated component/model tests need no autoload.
## Runtime always routes through the one GameAudio service; there is no fallback player.
static func _service() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("GameAudio") if tree != null and tree.root != null else null

static func play_event(event_id: String, context: Dictionary = {}) -> bool:
	var service := _service()
	return bool(service.play_event(event_id, context)) if service != null else false

static func set_context(at_menu: bool, paused: bool, reading: bool, progress: float = 0.0) -> void:
	var service := _service()
	if service != null:
		service.set_context(at_menu, paused, reading, progress)

static func set_cinematic(active: bool, native_audio: bool = true) -> void:
	var service := _service()
	if service != null:
		service.set_cinematic(active, native_audio)


static func enter_line(text_key: String, marker: String, text: String) -> void:
	var service := _service()
	if service != null:
		service.narrative.enter_line(text_key, marker, text)

static func reveal_line(characters: int) -> void:
	var service := _service()
	if service != null:
		service.narrative.reveal(characters)

static func end_line() -> void:
	var service := _service()
	if service != null:
		service.narrative.end_line()

static func set_restoring(value: bool) -> void:
	var service := _service()
	if service != null:
		service.narrative.restoring = value
		if value:
			service.narrative.reset()


static func set_movement(event_id: String) -> void:
	var service := _service()
	if service != null:
		service.set_movement(event_id)


static func restore_narrative_scene(completed: Array, stage: String) -> void:
	var service := _service()
	if service != null:
		service.narrative.restore_scene(completed, stage)
