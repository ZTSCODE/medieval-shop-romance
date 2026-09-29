class_name SettingsPanel
extends Control

signal status_requested(key: String, is_error: bool)
signal back_requested

const WINDOW_MODES := ["windowed", "borderless", "fullscreen"]
const WINDOW_KEYS := ["SETTINGS_WINDOWED", "SETTINGS_BORDERLESS", "SETTINGS_FULLSCREEN"]
const LOCALES := ["zh_CN", "en"]
const LOCALE_KEYS := ["SETTINGS_LANGUAGE_ZH", "SETTINGS_LANGUAGE_EN"]

var window_option: OptionButton
var resolution_option: OptionButton
var ui_scale_option: OptionButton
var _resolutions: Array[Vector2i] = []
var locale_option: OptionButton
var mute_check: HBoxContainer
var hdr_toggle: HBoxContainer
var _hdr_hint: Label
var _layout: Control
const DESIGN_SIZE := Vector2(960, 700)
var volume_sliders: Dictionary = {}
var volume_labels: Dictionary = {}
var settings: GameSettings
var _labels: Dictionary = {}
var _syncing := false
var _pending_volumes: Dictionary = {}
var _volume_dragging := false
var _volume_commit_timer: Timer
var _last_window_pixels := Vector2i(-1, -1)
const CATEGORY_KEYS := {"display": "SETTINGS_DISPLAY", "audio": "SETTINGS_AUDIO", "language": "SETTINGS_LANGUAGE"}
var current_category := "display"
var category_buttons: Dictionary = {}
var category_pages: Dictionary = {}
var _category_host: VBoxContainer
var _category_title: Label
var _return_button: Button
var _status: Label
var _content: VBoxContainer
var _tabs: HBoxContainer
var _page_heading: Label
var _entry_motion: Tween
var _page_motion: Tween
var _entry_offset := 0.0
var _entry_scale := 1.0
var _closing := false
const BookPaper = preload("res://scripts/ui/settings_book_paper.gd")
const BookSkin = preload("res://scripts/ui/settings_book_skin.gd")


func _ready() -> void:
	name = "SettingsPanel"
	_volume_commit_timer = Timer.new()
	_volume_commit_timer.one_shot = true
	_volume_commit_timer.wait_time = 0.25
	_volume_commit_timer.timeout.connect(_flush_volume_changes)
	add_child(_volume_commit_timer)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_flush_volume_changes()
			_reset_motion()
		elif is_instance_valid(_layout):
			_animate_open()
	)
	add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_arrange)
	_build_book_navigation()
	_begin_category("display")
	window_option = _option_row("SETTINGS_WINDOW_MODE", "WindowModeOption")
	window_option.item_selected.connect(_on_window_selected)
	resolution_option = _option_row("SETTINGS_RESOLUTION", "ResolutionOption")
	resolution_option.item_selected.connect(_on_resolution_selected)
	get_viewport().size_changed.connect(_queue_resolution_refresh)
	ui_scale_option = _option_row("SETTINGS_UI_SCALE", "UiScaleOption")
	ui_scale_option.item_selected.connect(_on_ui_scale_selected)
	hdr_toggle = _toggle_row("SETTINGS_HDR", "HdrToggle")
	hdr_toggle.toggled.connect(func(value: bool) -> void:
		if not _syncing:
			_write_setting("hdr_output", value)
	)
	_hdr_hint = Label.new()
	_hdr_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hdr_hint.add_theme_font_size_override("font_size", 16)
	_hdr_hint.add_theme_color_override("font_color", BookSkin.MUTED)
	_category_host.add_child(_hdr_hint)
	_begin_category("audio")
	for entry: Array in [["master_volume", "SETTINGS_MASTER"], ["music_volume", "SETTINGS_MUSIC"], ["sfx_volume", "SETTINGS_SFX"]]:
		_volume_row(str(entry[0]), str(entry[1]))
	mute_check = _toggle_row("SETTINGS_MUTE", "MuteCheck")
	mute_check.toggled.connect(_on_muted)
	_begin_category("language")
	locale_option = _option_row("SETTINGS_LANGUAGE", "LocaleOption")
	locale_option.item_selected.connect(_on_locale_selected)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(spacer)
	_return_button = Button.new()
	_return_button.custom_minimum_size = Vector2(220, 48)
	_return_button.add_theme_font_size_override("font_size", 24)
	_return_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_return_button.pressed.connect(_animate_back)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 18)
	_content.add_child(footer)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	footer.add_child(_status)
	footer.add_child(_return_button)
	BookSkin.apply_button(_return_button)
	for option: OptionButton in [window_option, resolution_option, ui_scale_option, locale_option]:
		BookSkin.apply_option(option)
		option.get_popup().about_to_popup.connect(func() -> void:
			option.get_popup().content_scale_factor = UiScale.factor_for_pixels(get_window().size)
		)
	_refresh_text()
	refresh_values()
	select_category(current_category, false)
	_arrange()


func _build_book_navigation() -> void:
	custom_minimum_size = Vector2(480, 350)
	_layout = Control.new()
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout.size = DESIGN_SIZE
	add_child(_layout)
	_tabs = HBoxContainer.new()
	_tabs.position = Vector2(42, 4)
	_tabs.add_theme_constant_override("separation", 5)
	_layout.add_child(_tabs)
	for id: String in CATEGORY_KEYS:
		var tab := preload("res://scripts/ui/settings_book_tab.gd").new()
		tab.name = id.capitalize() + "SettingsTab"
		tab.custom_minimum_size = Vector2(88, 76)
		tab.toggle_mode = true
		tab.icon = BookSkin.icon(id)
		tab.pressed.connect(select_category.bind(id))
		tab.focus_entered.connect(queue_redraw)
		tab.focus_exited.connect(queue_redraw)
		_tabs.add_child(tab)
		tab.visual_changed.connect(queue_redraw)
		category_buttons[id] = tab
	_category_title = Label.new()
	_category_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_category_title.add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	_category_title.add_theme_font_size_override("font_size", 32)
	_category_title.position = Vector2(250, 78)
	_category_title.size = Vector2(460, 48)
	_layout.add_child(_category_title)
	_content = VBoxContainer.new()
	_content.position = Vector2(120, 185)
	_content.size = Vector2(720, 436)
	_content.add_theme_constant_override("separation", 12)
	_layout.add_child(_content)
	_page_heading = Label.new()
	_page_heading.visible = false
	_content.add_child(_page_heading)


func _arrange() -> void:
	if not is_instance_valid(_layout):
		return
	var ratio := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_layout.scale = Vector2.ONE * ratio * _entry_scale
	_layout.position = (size - DESIGN_SIZE * ratio * _entry_scale) * 0.5 + Vector2(0, _entry_offset * ratio)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_tabs):
		return
	draw_set_transform(_layout.position, 0, _layout.scale)
	for id: String in category_buttons:
		var tab: Button = category_buttons[id]
		var at := _tabs.position + tab.position
		var paper_rect: Rect2 = tab.visual_rect(Rect2(Vector2.ZERO, Vector2(tab.size.x, 96)))
		paper_rect.position += at
		BookPaper.draw_bookmark(get_canvas_item(), paper_rect, tab.selection)
	BookPaper.draw_page(get_canvas_item(), Rect2(Vector2(0, 58), Vector2(960, 617)))


func _rule() -> HSeparator:
	var line := HSeparator.new()
	var ink := StyleBoxLine.new()
	ink.color = Color(0.69, 0.64, 0.52, 0.38)
	ink.thickness = 1
	line.add_theme_stylebox_override("separator", ink)
	line.custom_minimum_size.y = 2
	return line


func _begin_category(id: String) -> void:
	_category_host = VBoxContainer.new()
	_category_host.name = id.capitalize() + "SettingsPage"
	_category_host.add_theme_constant_override("separation", 12)
	_category_host.custom_minimum_size.y = 342
	_content.add_child(_category_host)
	category_pages[id] = _category_host


func select_category(id: String, focus: bool = true) -> void:
	if not category_pages.has(id):
		return
	var changed := current_category != id
	_flush_volume_changes()
	current_category = id
	for key: String in category_pages:
		category_pages[key].visible = key == id
		var button: Button = category_buttons[key]
		button.set_pressed_no_signal(key == id)
		button._update_selection()
	_page_heading.text = tr(CATEGORY_KEYS[id])
	_category_title.text = tr(CATEGORY_KEYS[id])
	queue_redraw()
	if focus:
		category_buttons[id].grab_focus()
	if changed and is_visible_in_tree():
		_animate_page()


func _set_entry_offset(value: float) -> void:
	_entry_offset = value
	_arrange()


func _animate_open() -> void:
	_reset_motion()
	modulate.a = 0.0
	_set_entry_spring(0.0)
	_entry_motion = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_entry_motion.tween_property(self, "modulate:a", 1.0, 0.15)
	_entry_motion.tween_method(_set_entry_spring, 0.0, 0.72, 0.72)
	_entry_motion.chain().tween_callback(func():
		_entry_scale = 1.0
		_set_entry_offset(0.0)
	)
	_animate_page()


func _set_entry_spring(time: float) -> void:
	var progress := 1.0 - exp(-8.0 * time) * (cos(16.0 * time) + 0.5 * sin(16.0 * time))
	_entry_scale = lerpf(0.94, 1.0, progress)
	_set_entry_offset(lerpf(20.0, 0.0, progress))


func _animate_page() -> void:
	if is_instance_valid(_page_motion):
		_page_motion.kill()
	for page: Control in category_pages.values():
		for row: Control in page.get_children():
			row.modulate.a = 1.0
	_page_motion = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_page_motion.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var index := 0
	for row: Control in category_pages[current_category].get_children():
		row.modulate.a = 0.25
		_page_motion.tween_property(row, "modulate:a", 1.0, 0.16).set_delay(index * 0.025)
		index += 1


func _animate_back() -> void:
	if _closing:
		return
	_closing = true
	_flush_volume_changes()
	# 所属窗口统一驱动纸页与遮罩退场，避免各自结束导致闪断。
	back_requested.emit()


func _reset_motion() -> void:
	for motion: Tween in [_entry_motion, _page_motion]:
		if is_instance_valid(motion):
			motion.kill()
	_closing = false
	modulate.a = 1.0
	_entry_scale = 1.0
	_set_entry_offset(0.0)
	for page: Control in category_pages.values():
		for row: Control in page.get_children():
			row.modulate.a = 1.0


func focus_current() -> void:
	category_buttons[current_category].grab_focus()


func set_status(message: String, is_error: bool) -> void:
	if is_instance_valid(_status):
		_status.text = message
		_status.add_theme_color_override("font_color", GameTheme.RED if is_error else GameTheme.MUTED)


func configure(value: GameSettings) -> void:
	_flush_volume_changes()
	if settings != null and settings.changed.is_connected(refresh_values):
		settings.changed.disconnect(refresh_values)
	settings = value
	if settings != null:
		settings.changed.connect(refresh_values)
	if is_node_ready():
		refresh_values()


func _process(_delta: float) -> void:
	if settings != null and get_window().size != _last_window_pixels:
		_last_window_pixels = get_window().size
		_refresh_resolutions()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()
		refresh_values()


func refresh_values() -> void:
	if not is_node_ready() or settings == null:
		return
	_syncing = true
	window_option.select(maxi(0, WINDOW_MODES.find(str(settings.get_value("window_mode")))))
	_refresh_resolutions()
	ui_scale_option.select(maxi(0, UiScale.OPTIONS.find(str(settings.get_value("ui_scale")))))
	locale_option.select(maxi(0, LOCALES.find(str(settings.get_value("locale")))))
	mute_check.button_pressed = bool(settings.get_value("muted"))
	var hdr_reason := settings.get_hdr_unavailable_reason()
	hdr_toggle.disabled = not hdr_reason.is_empty()
	hdr_toggle.button_pressed = settings.is_hdr_active()
	_hdr_hint.text = tr(hdr_reason) if not hdr_reason.is_empty() else ""
	_hdr_hint.visible = not hdr_reason.is_empty()
	for key: String in volume_sliders:
		var slider: HSlider = volume_sliders[key]
		slider.value = float(_pending_volumes.get(key, settings.get_value(key))) * 100.0
		_update_volume_label(key, slider.value)
	_syncing = false


func _option_row(key: String, node_name: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	row.custom_minimum_size.y = 64
	_category_host.add_child(row)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 130.0
	label.add_theme_font_size_override("font_size", 24)
	_labels[label] = key
	row.add_child(label)
	var option := OptionButton.new()
	option.name = node_name
	option.custom_minimum_size = Vector2(330.0, 62.0)
	option.size_flags_horizontal = Control.SIZE_SHRINK_END
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(option)
	return option


func _toggle_row(key: String, node_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 64
	_category_host.add_child(row)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 24)
	_labels[label] = key
	row.add_child(label)
	var slot := HBoxContainer.new()
	slot.custom_minimum_size.x = 330
	row.add_child(slot)
	var toggle := preload("res://scripts/ui/settings_book_toggle.gd").new()
	toggle.name = node_name
	slot.add_child(toggle)
	return toggle


func _volume_row(key: String, label_key: String) -> void:
	var block := VBoxContainer.new()
	block.name = key + "Row"
	block.add_theme_constant_override("separation", 2)
	_category_host.add_child(block)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 64
	row.add_theme_constant_override("separation", 16)
	block.add_child(row)
	var glyph := TextureRect.new()
	glyph.texture = BookSkin.icon("audio" if key == "music_volume" else key)
	glyph.custom_minimum_size = Vector2(34, 34)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.modulate = BookSkin.INK
	row.add_child(glyph)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_labels[label] = label_key
	label.add_theme_font_size_override("font_size", 24)
	row.add_child(label)
	var input_row := HBoxContainer.new()
	input_row.custom_minimum_size = Vector2(420, 54)
	input_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	input_row.add_theme_constant_override("separation", 14)
	row.add_child(input_row)
	var slider := HSlider.new()
	slider.name = key + "Slider"
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.custom_minimum_size = Vector2(216, 32)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_ALL
	BookSkin.apply_slider(slider)
	slider.value_changed.connect(_on_volume_changed.bind(key))
	slider.drag_started.connect(func() -> void:
		_volume_dragging = true
		_volume_commit_timer.stop()
	)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		_volume_dragging = false
		_flush_volume_changes()
	)
	input_row.add_child(slider)
	volume_sliders[key] = slider
	var amount := Label.new()
	amount.name = key + "Value"
	amount.custom_minimum_size.x = 60
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.add_theme_font_size_override("font_size", 22)
	input_row.add_child(amount)
	volume_labels[key] = amount


func _refresh_text() -> void:
	for id: String in category_buttons:
		category_buttons[id].text = ""
	_category_title.text = tr(CATEGORY_KEYS[current_category])
	_page_heading.text = tr(CATEGORY_KEYS[current_category])
	_return_button.text = tr("MENU_BACK")
	for label: Label in _labels:
		label.text = tr(str(_labels[label]))
	var window_selection := maxi(0, window_option.selected)
	window_option.clear()
	for key: String in WINDOW_KEYS:
		window_option.add_item(tr(key))
	window_option.select(window_selection)
	var locale_selection := maxi(0, locale_option.selected)
	locale_option.clear()
	for key: String in LOCALE_KEYS:
		locale_option.add_item(tr(key))
	locale_option.select(locale_selection)
	ui_scale_option.clear()
	ui_scale_option.add_item(tr("SETTINGS_UI_SCALE_AUTO"))
	for value: String in UiScale.OPTIONS.slice(1):
		ui_scale_option.add_item(tr("SETTINGS_UI_SCALE_PERCENT") % int(value))


func _on_ui_scale_selected(index: int) -> void:
	if not _syncing and index >= 0 and index < UiScale.OPTIONS.size():
		_write_setting("ui_scale", UiScale.OPTIONS[index])


func _on_volume_changed(value: float, key: String) -> void:
	_update_volume_label(key, value)
	if not _syncing and settings != null:
		_pending_volumes[key] = value / 100.0
		settings.preview_volume(key, value / 100.0)
		if not _volume_dragging:
			_volume_commit_timer.start()


func _flush_volume_changes() -> void:
	_volume_dragging = false
	if is_instance_valid(_volume_commit_timer):
		_volume_commit_timer.stop()
	if settings == null or _pending_volumes.is_empty():
		return
	var updates := _pending_volumes.duplicate()
	_pending_volumes.clear()
	var success := settings.set_volumes(updates)
	if not success:
		refresh_values()
	status_requested.emit("SETTINGS_SAVED" if success else settings.error_key, not success)


func _exit_tree() -> void:
	_flush_volume_changes()


func _update_volume_label(key: String, value: float) -> void:
	if volume_labels.has(key):
		volume_labels[key].text = tr("SETTINGS_VOLUME_FORMAT") % roundi(value)


func _on_window_selected(index: int) -> void:
	if not _syncing and index >= 0 and index < WINDOW_MODES.size():
		_write_setting("window_mode", WINDOW_MODES[index])


func _queue_resolution_refresh() -> void:
	_refresh_resolutions.call_deferred()


func _refresh_resolutions() -> void:
	if settings == null or resolution_option == null:
		return
	resolution_option.clear()
	var windowed := str(settings.get_value("window_mode")) == "windowed"
	resolution_option.disabled = not windowed
	if not windowed:
		var native := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
		resolution_option.add_item(tr("SETTINGS_RESOLUTION_NATIVE") % [native.x, native.y])
		resolution_option.set_item_metadata(0, native)
		return
	_resolutions = settings.get_resolution_options()
	var current := get_window().size
	if not _resolutions.has(current):
		_resolutions.append(current)
	for dimensions: Vector2i in _resolutions:
		resolution_option.add_item(tr("SETTINGS_RESOLUTION_FORMAT") % [dimensions.x, dimensions.y])
		resolution_option.set_item_metadata(resolution_option.item_count - 1, dimensions)
	resolution_option.select(_resolutions.find(current))


func _on_resolution_selected(index: int) -> void:
	if not _syncing and index >= 0 and index < _resolutions.size():
		_write_setting("window_resolution", _resolutions[index])


func _on_locale_selected(index: int) -> void:
	if not _syncing and index >= 0 and index < LOCALES.size():
		_write_setting("locale", LOCALES[index])


func _on_muted(value: bool) -> void:
	if not _syncing:
		_write_setting("muted", value)


func _write_setting(key: String, value: Variant) -> void:
	if settings == null:
		return
	_flush_volume_changes()
	var success := settings.set_value(key, value)
	if not success:
		refresh_values()
		status_requested.emit(settings.error_key, true)
	else:
		status_requested.emit("SETTINGS_SAVED", false)
