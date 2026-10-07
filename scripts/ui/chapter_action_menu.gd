class_name ChapterActionMenu
extends CanvasLayer

signal option_selected(option: Dictionary)

const Choice = preload("res://scripts/ui/dialogue_choice_button.gd")
const PaperSkinStyle = preload("res://scripts/ui/paper_skin.gd")
var panel: PanelContainer
var list: VBoxContainer
var _options: Array[Dictionary] = []


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PaperSkinStyle.make(&"panel", 24.0))
	add_child(panel)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	panel.add_child(list)
	close()
	get_viewport().size_changed.connect(close)


func open(options: Array[Dictionary], screen_position: Vector2) -> void:
	close()
	_options = options.duplicate(true)
	var area := get_viewport().get_visible_rect()
	var width := minf(440.0 * UiScale.factor_for_pixels(get_window().size), area.size.x - 48.0)
	for option: Dictionary in _options:
		var button := Choice.new()
		list.add_child(button)
		button.fit_caption(tr(option.text_key), width - 48.0, 20, 1.0)
		button.pressed.connect(_choose.bind(option))
	panel.reset_size()
	panel.size = Vector2(width, 0)
	panel.position = screen_position.clamp(area.position + Vector2(24, 24), area.end - panel.get_combined_minimum_size() - Vector2(24, 24))
	panel.show()
	AudioEvents.play_event("ui.popup_open")


func close() -> void:
	if panel == null:
		return
	if panel.visible and not _options.is_empty():
		AudioEvents.play_event("ui.popup_close")
	panel.hide()
	_options.clear()
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()


func blocks_pointer(point: Vector2) -> bool:
	return panel != null and panel.visible and panel.get_global_rect().has_point(point)


func _input(event: InputEvent) -> void:
	if panel == null or not panel.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not blocks_pointer(event.position):
		close()


func _choose(option: Dictionary) -> void:
	close()
	option_selected.emit(option)
