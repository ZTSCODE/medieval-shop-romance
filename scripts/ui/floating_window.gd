class_name FloatingWindow
extends PanelContainer

signal close_requested
signal moved(at: Vector2)

const ThemeKit = preload("res://scripts/ui/game_theme.gd")
const EDGE_MARGIN := 16.0

var title_label: Label
var title_bar: PanelContainer
var close_button: Button
var actions: HBoxContainer
var body: VBoxContainer
var dragging := false
var drag_top_extension := 0.0
var draggable := true

var _title_key := ""
var _bounds := Rect2()
var _drag_offset := Vector2.ZERO
var _paper_asset := "pause_panel"
var _paper_reveal: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	if draggable:
		gui_input.connect(_on_drag_surface_input.bind(self))
	theme = ThemeKit.make_theme()
	_apply_paper()
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	title_bar = PanelContainer.new()
	title_bar.name = "FloatingTitleBar"
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE if draggable else Control.CURSOR_ARROW
	var header_style := StyleBoxEmpty.new()
	header_style.content_margin_left = 12.0
	header_style.content_margin_right = 8.0
	header_style.content_margin_top = 6.0
	header_style.content_margin_bottom = 8.0
	title_bar.add_theme_stylebox_override("panel", header_style)
	if draggable:
		title_bar.gui_input.connect(_on_title_input)
	column.add_child(title_bar)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(header)
	title_label = Label.new()
	title_label.name = "FloatingTitle"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", ThemeKit.INK)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if name == "GameJournalPanel":
		var title_center := CenterContainer.new()
		title_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(title_center)
		title_center.add_child(title_label)
		title_label.custom_minimum_size = Vector2(260, 26)
	else:
		header.add_child(title_label)
	actions = HBoxContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("separation", 6)
	header.add_child(actions)
	close_button = preload("res://scripts/ui/paper_close_button.gd").new()
	close_button.name = "CloseFloatingWindow"
	close_button.custom_minimum_size = Vector2(36.0, 36.0)
	close_button.add_theme_font_size_override("font_size", 16)
	ThemeKit.apply_button(close_button, true)
	close_button.icon = ThemeKit.small_icon("close", Vector2i(24, 24))
	close_button.pressed.connect(func() -> void: cancel_drag(); close_requested.emit())
	header.add_child(close_button)
	header.move_child(close_button, 0)
	var margins := MarginContainer.new()
	margins.mouse_filter = Control.MOUSE_FILTER_PASS
	margins.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 20 if name == "GameJournalPanel" else 10)
	column.add_child(margins)
	body = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.name = "FloatingBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	margins.add_child(body)
	visibility_changed.connect(_on_visibility_changed)
	_update_text()


func set_title_key(key: String) -> void:
	_title_key = key
	if is_node_ready():
		_update_text()


func set_paper_asset(asset_name: String) -> void:
	_paper_asset = asset_name
	if is_node_ready():
		_apply_paper()


func _apply_paper() -> void:
	if _paper_asset in ["recipes_panel", "people_panel"] or name == "GameJournalPanel":
		add_theme_stylebox_override("panel", preload("res://scripts/ui/journal_window_style.gd").new())
	else:
		add_theme_stylebox_override("panel", ThemeKit.paper_style(_paper_asset, 52.0))


func set_viewport_bounds(value: Rect2) -> void:
	_bounds = value.grow(-EDGE_MARGIN)
	_bounds.size = _bounds.size.max(Vector2.ONE)
	if is_node_ready():
		clamp_to_viewport()


func present(desired_size: Vector2, at: Vector2) -> void:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		set_viewport_bounds(get_viewport_rect())
	size = desired_size.min(_bounds.size)
	position = at
	clamp_to_viewport()


func clamp_to_viewport() -> void:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return
	if size.x > _bounds.size.x or size.y > _bounds.size.y:
		size = size.min(_bounds.size)
	position = Vector2(
		clampf(position.x, _bounds.position.x, maxf(_bounds.position.x, _bounds.end.x - size.x)),
		clampf(position.y, _bounds.position.y + drag_top_extension, maxf(_bounds.position.y + drag_top_extension, _bounds.end.y - size.y))
	).round()


func cancel_drag() -> void:
	dragging = false


func set_draggable(value: bool) -> void:
	draggable = value
	if not draggable:
		cancel_drag()
	if is_instance_valid(title_bar):
		title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE if draggable else Control.CURSOR_ARROW
		_update_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_text()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_drag()


func _input(event: InputEvent) -> void:
	if not draggable:
		cancel_drag()
		return
	if not dragging:
		return
	if not is_visible_in_tree():
		cancel_drag()
		return
	if event is InputEventMouseMotion:
		position = event.position - _drag_offset
		clamp_to_viewport()
		moved.emit(position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		cancel_drag()
		get_viewport().set_input_as_handled()


func _on_title_input(event: InputEvent) -> void:
	_on_drag_surface_input(event, title_bar)


func attach_drag_handle(handle: Control) -> void:
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE if draggable else Control.CURSOR_ARROW
	if draggable:
		handle.gui_input.connect(_on_drag_surface_input.bind(handle))


func _on_drag_surface_input(event: InputEvent, surface: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not draggable:
			cancel_drag()
			return
		if event.pressed:
			dragging = true
			_drag_offset = surface.get_global_transform() * event.position - global_position
		else:
			cancel_drag()
		surface.accept_event()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		cancel_drag()
	elif is_node_ready():
		if _paper_reveal != null:
			_paper_reveal.kill()
		_paper_reveal = ThemeKit.animate_open(self)


func _update_text() -> void:
	title_label.text = tr(_title_key) if not _title_key.is_empty() else ""
	close_button.text = ""
	close_button.accessibility_name = tr("WINDOW_CLOSE")


func _draw_journal_decoration() -> void:
	var leaf := GameArt.texture("res://assets/art/ui/forest_rebuild/type-leaf.png")
	if leaf != null:
		draw_texture_rect(leaf, Rect2(36, size.y - 100, 30, 55), false, Color("7b8166"))
		draw_texture_rect(leaf, Rect2(size.x - 75, 39, 25, 46), false, Color("92917b"))
