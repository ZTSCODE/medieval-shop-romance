class_name SaveSlotsPanel
extends Control

signal save_clicked(slot: String, occupied: bool)
signal load_clicked(slot: String)
signal back_requested

const BookPaper = preload("res://scripts/ui/settings_book_paper.gd")
const BookSkin = preload("res://scripts/ui/settings_book_skin.gd")
const DESIGN_SIZE := Vector2(960, 700)
var _layout: Control
var _rows: VBoxContainer
var _heading: Label
var _status: Label
var _back: Button
var _entry_motion: Tween
var _entry_scale := 1.0
var _entry_offset := 0.0

var store: SaveStore
var slot_controls: Dictionary = {}
var manual_slots_enabled := true
var _slot_rows: Dictionary = {}
var read_only := false


func set_read_only(value: bool) -> void:
	if read_only == value:
		return
	read_only = value
	if is_node_ready():
		for controls: Dictionary in slot_controls.values():
			if controls.has("save_button"):
				controls.save_button.visible = not value


func _ready() -> void:
	name = "SaveSlotsPanel"
	custom_minimum_size = Vector2(480, 350)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	_layout = Control.new()
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout.size = DESIGN_SIZE
	add_child(_layout)
	_heading = Label.new()
	_heading.position = Vector2(250, 78)
	_heading.size = Vector2(460, 48)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", 32)
	_heading.add_theme_color_override("font_color", BookSkin.INK)
	_layout.add_child(_heading)
	_rows = VBoxContainer.new()
	_rows.position = Vector2(112, 151)
	_rows.size = Vector2(736, 400)
	_rows.add_theme_constant_override("separation", 12)
	_layout.add_child(_rows)
	for slot: String in ["auto", "slot_1", "slot_2", "slot_3"]:
		_build_slot(slot)
	_status = Label.new()
	_status.position = Vector2(120, 592)
	_status.size = Vector2(464, 44)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	_layout.add_child(_status)
	_back = Button.new()
	_back.name = "SavePageBack"
	_back.position = Vector2(620, 588)
	_back.size = Vector2(220, 48)
	_back.add_theme_font_size_override("font_size", 24)
	_layout.add_child(_back)
	BookSkin.apply_button(_back)
	_back.pressed.connect(func(): back_requested.emit())
	resized.connect(_arrange)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_animate_open()
		else:
			_reset_motion()
	)
	refresh_slots()
	_arrange()


func _arrange() -> void:
	if not is_instance_valid(_layout):
		return
	var ratio := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_layout.scale = Vector2.ONE * ratio * _entry_scale
	_layout.position = (size - DESIGN_SIZE * ratio * _entry_scale) * 0.5 + Vector2(0, _entry_offset * ratio)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_layout):
		return
	draw_set_transform(_layout.position, 0, _layout.scale)
	BookPaper.draw_page(get_canvas_item(), Rect2(Vector2(0, 58), Vector2(960, 617)))


func _animate_open() -> void:
	_reset_motion()
	modulate.a = 0.0
	_set_entry_spring(0.0)
	_entry_motion = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_entry_motion.tween_property(self, "modulate:a", 1.0, 0.15)
	_entry_motion.tween_method(_set_entry_spring, 0.0, 0.72, 0.72)
	_entry_motion.chain().tween_callback(_reset_motion)


func _set_entry_spring(time: float) -> void:
	var progress := 1.0 - exp(-8.0 * time) * (cos(16.0 * time) + 0.5 * sin(16.0 * time))
	_entry_scale = lerpf(0.94, 1.0, progress)
	_entry_offset = lerpf(20.0, 0.0, progress)
	_arrange()


func _reset_motion() -> void:
	if is_instance_valid(_entry_motion):
		_entry_motion.kill()
	_entry_scale = 1.0
	_entry_offset = 0.0
	modulate.a = 1.0
	_arrange()


func set_status(value: String, is_error: bool) -> void:
	_status.text = value
	_status.add_theme_color_override("font_color", GameTheme.RED if is_error else BookSkin.MUTED)


func focus_current() -> void:
	_back.grab_focus()


func configure(value: SaveStore) -> void:
	store = value
	if is_node_ready():
		refresh_slots()


func set_slots_enabled(value: bool) -> void:
	manual_slots_enabled = value
	if is_node_ready():
		refresh_slots()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh_slots()


func refresh_slots() -> void:
	if not is_node_ready():
		return
	var probe_started := HitchProbe.stamp()
	_heading.text = tr("MENU_SAVE_LOAD")
	_back.text = tr("MENU_BACK")
	var records: Dictionary = {}
	if store != null:
		for entry: Dictionary in store.list_slots_quick():
			records[str(entry.get("slot", ""))] = entry
	for slot: String in slot_controls:
		var controls: Dictionary = slot_controls[slot]
		var entry: Dictionary = records.get(slot, {})
		_slot_rows[slot] = entry
		var exists := bool(entry.get("exists", false))
		var valid := bool(entry.get("valid", false))
		controls.root.visible = slot == "auto" or manual_slots_enabled
		controls.title.text = slot_title(slot)
		var details := ""
		if exists and valid:
			details = tr("SAVE_SLOT_SUMMARY") % [int(entry.get("day", 1)), int(entry.get("card_count", 0))]
			var saved_at := str(entry.get("saved_at", ""))
			if not saved_at.is_empty():
				details += "\n" + _local_time(saved_at)
			if bool(entry.get("recovered", false)):
				details += "\n" + tr("SAVE_SLOT_RECOVERED")
		elif exists:
			details = tr("SAVE_SLOT_INVALID")
			var error_key := str(entry.get("error_key", ""))
			if not error_key.is_empty():
				details += "\n" + tr(error_key)
		else:
			details = tr("SAVE_SLOT_EMPTY")
		controls.detail.text = details
		controls.detail.add_theme_color_override("font_color", BookSkin.MUTED if not exists or valid else GameTheme.RED)
		controls.load_button.text = tr("LOAD_ACTION")
		controls.load_button.disabled = not valid
		if controls.has("save_button"):
			controls.save_button.text = tr("SAVE_ACTION")
			controls.save_button.visible = not read_only
	HitchProbe.record("save_slots_refresh", probe_started)


func slot_title(slot: String) -> String:
	if slot == "auto":
		return tr("SAVE_SLOT_AUTO")
	return tr("SAVE_SLOT_MANUAL") % slot.trim_prefix("slot_").to_int()


func _local_time(utc_time: String) -> String:
	var unix_time := Time.get_unix_time_from_datetime_string(utc_time.trim_suffix("Z"))
	unix_time += int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var parts := Time.get_datetime_dict_from_unix_time(unix_time)
	return tr("SAVE_TIMESTAMP_FORMAT") % [int(parts.year), int(parts.month), int(parts.day), int(parts.hour), int(parts.minute)]


func _build_slot(slot: String) -> void:
	var panel := PanelContainer.new()
	panel.name = "SaveSlot_" + slot
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 88
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(0.69, 0.64, 0.52, 0.25)
	style.border_width_bottom = 1
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	_rows.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 5)
	row.add_child(text_column)
	var title := Label.new()
	title.name = "SlotTitle"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", BookSkin.INK)
	text_column.add_child(title)
	var detail := Label.new()
	detail.name = "SlotDetail"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_font_size_override("font_size", 16)
	text_column.add_child(detail)
	var actions := HBoxContainer.new()
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", 14)
	row.add_child(actions)
	var controls: Dictionary = {"root": panel, "title": title, "detail": detail}
	if slot != "auto":
		var save_button := Button.new()
		save_button.name = "SaveButton"
		save_button.custom_minimum_size = Vector2(112.0, 48.0)
		save_button.add_theme_font_size_override("font_size", 22)
		save_button.pressed.connect(_on_save.bind(slot))
		actions.add_child(save_button)
		BookSkin.apply_button(save_button)
		controls["save_button"] = save_button
	var load_button := Button.new()
	load_button.name = "LoadButton"
	load_button.custom_minimum_size = Vector2(112.0, 48.0)
	load_button.add_theme_font_size_override("font_size", 22)
	load_button.pressed.connect(func() -> void: load_clicked.emit(slot))
	actions.add_child(load_button)
	BookSkin.apply_button(load_button)
	controls["load_button"] = load_button
	slot_controls[slot] = controls


func _on_save(slot: String) -> void:
	if read_only:
		return
	var entry: Dictionary = _slot_rows.get(slot, {})
	save_clicked.emit(slot, bool(entry.get("exists", false)))
