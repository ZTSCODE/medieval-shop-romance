class_name NameEntry
extends CanvasLayer

const BookSkin = preload("res://scripts/ui/settings_book_skin.gd")
const ControlPaper = preload("res://scripts/ui/settings_control_paper.gd")

signal confirmed(player_name: String)
signal canceled

var name_input: LineEdit
var confirm_button: Button
var cancel_button: Button
var panel: PanelContainer
var _root: Control
var _title: Label
var _prompt: Label
var _count: Label
var _error: Label
var _restoring := false
var _error_key := ""
var _entry_tween: Tween
var _entry_amount := 1.0


func _init() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.name = "NameEntryRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameTheme.make_theme()
	var shade := ColorRect.new()
	shade.color = Color(0.04,0.03,0.03,0.28)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.name = "NameEntryPaper"
	panel.add_theme_stylebox_override("panel", preload("res://scripts/ui/name_entry_paper.gd").new())
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	column.minimum_size_changed.connect(_layout.call_deferred)
	_title = Label.new()
	_title.add_theme_font_override("font", GameTheme.title_font())
	_title.add_theme_font_size_override("font_size", 32)
	_title.add_theme_color_override("font_color", BookSkin.INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_prompt = Label.new()
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", BookSkin.MUTED)
	column.add_child(_prompt)
	name_input = LineEdit.new()
	name_input.name = "PlayerNameInput"
	name_input.custom_minimum_size = Vector2(320.0, 62.0)
	# 不截断输入法的组合文本，额度在完整提交时统一校验。
	name_input.max_length = 0
	name_input.context_menu_enabled = false
	name_input.add_theme_stylebox_override("normal", ControlPaper.make())
	name_input.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	name_input.add_theme_font_override("font", BookSkin.Typography.regular())
	name_input.add_theme_font_size_override("font_size", 24)
	name_input.add_theme_color_override("font_color", BookSkin.INK)
	name_input.add_theme_color_override("font_placeholder_color", BookSkin.MUTED)
	name_input.add_theme_color_override("caret_color", BookSkin.INK)
	name_input.add_theme_color_override("selection_color", Color(0.60, 0.57, 0.49, 0.48))
	name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_input.text_changed.connect(_on_text_changed)
	name_input.text_submitted.connect(func(_text: String) -> void: submit())
	column.add_child(name_input)
	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.add_theme_font_size_override("font_size", 14)
	_count.add_theme_color_override("font_color", BookSkin.MUTED)
	column.add_child(_count)
	_error = Label.new()
	_error.name = "NameEntryError"
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size.y = 32.0
	_error.add_theme_font_size_override("font_size", 15)
	_error.add_theme_color_override("font_color", GameTheme.RED)
	column.add_child(_error)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	cancel_button = Button.new()
	cancel_button.name = "NameEntryCancel"
	cancel_button.custom_minimum_size.y = 58.0
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BookSkin.apply_button(cancel_button)
	cancel_button.pressed.connect(func() -> void: canceled.emit())
	actions.add_child(cancel_button)
	confirm_button = Button.new()
	confirm_button.name = "NameEntryConfirm"
	confirm_button.custom_minimum_size.y = 58.0
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	BookSkin.apply_button(confirm_button)
	confirm_button.pressed.connect(submit)
	actions.add_child(confirm_button)
	_root.resized.connect(_layout)
	UiScale.bind(_root, _layout)
	_update_text()
	_layout()
	close()


func open(initial_name: String = "", restoring: bool = false) -> void:
	_restoring = restoring
	_error_key = ""
	name_input.text = initial_name
	visible = true
	_update_text()
	_layout()
	_focus_input.call_deferred()
	if is_instance_valid(_entry_tween):
		_entry_tween.kill()
	_paint_entry(0.0)
	_entry_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_entry_tween.tween_method(_paint_entry, 0.0, 1.0, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if is_instance_valid(_entry_tween):
		_entry_tween.kill()
	visible = false
	if is_node_ready():
		name_input.release_focus()


func show_status(key: String) -> void:
	_error_key = key
	_update_text()


func submit() -> void:
	var key := PlayerIdentity.name_error(name_input.text)
	if not key.is_empty():
		show_status(key)
		name_input.grab_focus()
		return
	confirmed.emit(PlayerIdentity.normalize(name_input.text))


func _on_text_changed(_value: String) -> void:
	_error_key = ""
	_update_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_text()
		_layout.call_deferred()


func _update_text() -> void:
	_title.text = tr("NAME_ENTRY_TITLE")
	_prompt.text = tr("NAME_ENTRY_RESUME_PROMPT" if _restoring else "NAME_ENTRY_PROMPT")
	name_input.placeholder_text = ""
	cancel_button.text = tr("NAME_ENTRY_CANCEL")
	confirm_button.text = tr("NAME_ENTRY_CONFIRM")
	var units := PlayerIdentity.name_units(name_input.text)
	_count.text = tr("NAME_ENTRY_COUNT_FORMAT") % [units, PlayerIdentity.MAX_NAME_UNITS]
	_count.add_theme_color_override("font_color", GameTheme.RED if units > PlayerIdentity.MAX_NAME_UNITS else BookSkin.MUTED)
	_error.text = tr(_error_key) if not _error_key.is_empty() else ""


func _layout() -> void:
	if not is_instance_valid(panel):
		return
	panel.size = Vector2(720, 463)
	_paint_entry(_entry_amount)


func _paint_entry(amount: float) -> void:
	_entry_amount = amount
	var fit := minf(1.0, minf((_root.size.x - 40.0) / panel.size.x, (_root.size.y - 40.0) / panel.size.y))
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * fit * lerpf(0.95, 1.0, amount)
	panel.position = ((_root.size - panel.size) * 0.5).round() + Vector2(0, (1.0 - amount) * 14.0)
	panel.modulate.a = clampf(amount * 1.8, 0.0, 1.0)


func _focus_input() -> void:
	if visible:
		name_input.grab_focus()
		name_input.caret_column = name_input.text.length()
