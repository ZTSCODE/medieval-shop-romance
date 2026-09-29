class_name SessionOverlay
extends CanvasLayer

signal resume_requested
signal quit_requested
signal quit_without_save_requested
signal save_requested(slot: String)
signal load_requested(slot: String)
signal new_journey_requested
signal focus_hero_requested
signal time_cycle_requested

const DAY_WIDTH := 320.0
const DAY_HEIGHT := 48.0
const DAY_TOP := 24.0
const PAGE_KEYS := {"main": "SESSION_PAUSED", "saves": "MENU_SAVE_LOAD", "settings": "MENU_SETTINGS"}
const ThemeKit = preload("res://scripts/ui/game_theme.gd")
const FloatingPanel = preload("res://scripts/ui/floating_window.gd")
const PausePaper = preload("res://scripts/ui/pause_reference_paper.gd")

var resume_button: Button
var quit_button: Button
var new_journey_button: Button
var day_label: Label
var day_progress: ProgressBar
var time_cycle_button: Button
var pause_root: Control
var day_root: Control
var hud_shade: ColorRect
var current_page := "main"
var settings_panel: SettingsPanel
var saves_panel: SaveSlotsPanel
var back_button: Button
var page_root: PanelContainer
var page_scroll: ScrollContainer
var confirmation_dialog: ConfirmationDialog

var _root: Control
var _pause_title: Label
var _pause_center: Control
var _page_title: Label
var _status_label: Label
var _page_body: VBoxContainer
var _menu_buttons: Dictionary = {}
var _pages: Dictionary = {}
var _day := 1
var _progress := 0.0
var _paused := false
var _menu_tween: Tween
var _settings_exit: Tween
var _settings: GameSettings
var _store: SaveStore
var _manual_slots_enabled := true
var _status_key := ""
var _status_is_error := false
var _pending_action := ""
var _pending_slot := ""
var _dialog_previous_focus: Control
var _window: PanelContainer
var _page_column: VBoxContainer
var _window_placed := false
var _main_menu_context := false
var _identity := ""
var player_hud: PlayerHud
var _pause_tab: PanelContainer
var _pause_tab_text: Label
var _hud_target_visible := true
var _hud_fade: Tween
var _pause_entries: VBoxContainer
var _pause_scale := 1.0
var _time_speed := 1.0
var _time_paused := false
var _time_controls_available := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20


func _ready() -> void:
	_root = Control.new()
	_root.name = "SessionOverlayRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = ThemeKit.make_theme()
	_build_day_indicator()
	_build_pause_menu()
	_build_pages()
	_build_confirmation()
	_bind_models()
	_style_content()
	_root.resized.connect(_layout)
	UiScale.bind(_root, _layout)
	_layout()
	_update_text()
	day_progress.value = _progress
	_apply_paused(false)


func configure(settings: GameSettings, store: SaveStore) -> void:
	_settings = settings
	_store = store
	if is_node_ready():
		_bind_models()


func _bind_models() -> void:
	settings_panel.configure(_settings)
	saves_panel.configure(_store)
	saves_panel.set_slots_enabled(_manual_slots_enabled)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_text()


func set_day(day: int, progress: float) -> void:
	_day = maxi(day, 1)
	_progress = clampf(progress, 0.0, 1.0)
	if not is_instance_valid(day_label):
		return
	player_hud.set_day(_day, _progress)


func set_identity(value: String) -> void:
	_identity = value
	if is_instance_valid(player_hud):
		player_hud.set_identity(value)


func set_time_controls(speed: float, paused: bool, available: bool) -> void:
	_time_speed = speed
	_time_paused = paused
	_time_controls_available = available
	if is_instance_valid(time_cycle_button):
		time_cycle_button.disabled = not available
		_refresh_time_controls()


func blocks_time_control(point: Vector2) -> bool:
	for button: Button in [time_cycle_button]:
		if is_instance_valid(button) and button.is_visible_in_tree() and button.get_global_rect().has_point(point):
			return true
	return false


func _refresh_time_controls() -> void:
	if not is_instance_valid(time_cycle_button):
		return
	time_cycle_button.text = tr("HUD_TIME_STATE_PAUSED" if _time_paused else "HUD_TIME_SPEED_THREE" if _time_speed > 1.0 else "HUD_TIME_SPEED_ONE")
	time_cycle_button.set_time_state(_time_speed, _time_paused)


func set_hud_visible(value: bool) -> void:
	if not is_instance_valid(day_root):
		return
	player_hud.focus_enabled = value and not _paused
	player_hud.portrait.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if value == _hud_target_visible:
		return
	_hud_target_visible = value
	if _hud_fade != null:
		_hud_fade.kill()
	var controls: Array[Control] = [day_root, day_progress, day_label, time_cycle_button, hud_shade]
	for control: Control in controls:
		control.show()
	_hud_fade = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_hud_fade.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for control: Control in controls:
		_hud_fade.tween_property(control, "modulate:a", 1.0 if value else 0.0, 0.2)
	_hud_fade.chain().tween_callback(func() -> void:
		if not _hud_target_visible:
			for control: Control in controls:
				control.hide()
	)


func set_main_menu_context(value: bool) -> void:
	if _main_menu_context == value:
		return
	_main_menu_context = value
	if is_instance_valid(saves_panel):
		saves_panel.set_read_only(value)


func set_paused(value: bool) -> void:
	if is_instance_valid(_settings_exit):
		_settings_exit.kill()
	var changed := value != _paused
	_paused = value
	if is_instance_valid(player_hud):
		player_hud.focus_enabled = not value and _hud_target_visible
	if not value:
		current_page = "main"
		_close_confirmation(false)
		_status_key = ""
	elif changed:
		current_page = "main"
		_status_key = ""
	if is_instance_valid(pause_root):
		_apply_paused(changed)


func open_page(page: String) -> void:
	if not PAGE_KEYS.has(page):
		return
	var probe_started := HitchProbe.stamp()
	_close_confirmation(false)
	current_page = page
	_status_key = ""
	if not is_node_ready():
		return
	if page == "saves":
		refresh_slots()
	_apply_page_visibility()
	_layout()
	_update_text()
	page_scroll.scroll_vertical = 0
	_focus_page.call_deferred(page)
	HitchProbe.record("session_open_page_" + page, probe_started)


func back() -> bool:
	if is_instance_valid(_settings_exit) and _settings_exit.is_running():
		return true
	if is_instance_valid(confirmation_dialog) and confirmation_dialog.visible:
		_close_confirmation(true)
		return true
	if current_page in ["settings", "saves"]:
		if current_page == "settings":
			settings_panel._flush_volume_changes()
		var target: Control = pause_root if _main_menu_context else _window
		_settings_exit = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_settings_exit.tween_property(target, "modulate:a", 0.0, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_settings_exit.tween_callback(func():
			if _main_menu_context:
				resume_requested.emit()
			else:
				open_page("main")
				_window.modulate.a = 0.0
				var reveal := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
				reveal.tween_property(_window, "modulate:a", 1.0, 0.14)
		)
		return true
	if current_page != "main":
		if _main_menu_context:
			resume_requested.emit()
			return true
		open_page("main")
		return true
	return false


func set_slots_enabled(value: bool) -> void:
	_manual_slots_enabled = value
	if is_instance_valid(saves_panel):
		saves_panel.set_slots_enabled(value)


func refresh_slots() -> void:
	if _paused and current_page == "saves" and is_instance_valid(saves_panel):
		saves_panel.refresh_slots()


func confirm_quit_without_save() -> void:
	_open_confirmation("quit_without_save", "")


func show_status(key: String, is_error: bool = false) -> void:
	_status_key = key
	_status_is_error = is_error
	if is_instance_valid(_status_label):
		_update_status()


func get_day_rect() -> Rect2:
	if not is_instance_valid(day_root) or not day_root.is_visible_in_tree():
		return Rect2()
	return day_root.get_global_rect()


func _build_day_indicator() -> void:
	var shade_layer := CanvasLayer.new()
	shade_layer.layer = 18
	add_child(shade_layer)
	hud_shade = ColorRect.new()
	hud_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade_shader := Shader.new()
	shade_shader.code = "shader_type canvas_item; void fragment(){ float fade=COLOR.a; COLOR=vec4(0.0,0.0,0.0,smoothstep(0.0,1.0,UV.x)*0.18*fade); }"
	var shade_material := ShaderMaterial.new()
	shade_material.shader = shade_shader
	hud_shade.material = shade_material
	shade_layer.add_child(hud_shade)
	var day_layer := CanvasLayer.new()
	day_layer.name = "DayHudLayer"
	day_layer.layer = 19
	add_child(day_layer)
	player_hud = PlayerHud.new()
	day_root = player_hud
	day_root.name = "DayIndicator"
	day_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	day_layer.add_child(day_root)
	day_label = player_hud.day_label
	day_label.add_theme_font_size_override("font_size", 20)
	day_progress = player_hud.day_progress
	var axis_layer := CanvasLayer.new()
	axis_layer.name = "DayAxisLayer"
	axis_layer.layer = 19
	add_child(axis_layer)
	day_progress.reparent(axis_layer)
	day_label.reparent(axis_layer)
	time_cycle_button = preload("res://scripts/ui/time_cycle_button.gd").new()
	time_cycle_button.name = "TimeCycleButton"
	for button: Button in [time_cycle_button]:
		button.process_mode = Node.PROCESS_MODE_ALWAYS
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size = Vector2(72,36)
		button.add_theme_font_size_override("font_size", 20)
		axis_layer.add_child(button)
	time_cycle_button.pressed.connect(func() -> void: time_cycle_requested.emit())
	set_time_controls(_time_speed, _time_paused, _time_controls_available)
	player_hud.focus_hero_requested.connect(func() -> void: focus_hero_requested.emit())
	player_hud.set_identity(_identity)
	player_hud.set_day(_day, _progress)


func _build_pause_menu() -> void:
	pause_root = Control.new()
	pause_root.name = "PauseMenu"
	pause_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(pause_root)
	pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.name = "PauseSceneDim"
	shade.color = Color(0, 0, 0, 0.45)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window = FloatingPanel.new()
	_window.name = "PauseFloatingWindow"
	_window.set_draggable(false)
	pause_root.add_child(_window)
	_window.close_button.get_parent().move_child(_window.close_button, -1)
	_window.close_button.icon = null
	_window.close_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_window.close_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_window.close_button.draw.connect(func() -> void:
		var button: Button = _window.close_button
		var center := button.size * 0.5
		var color := Color("a39e8c")
		var glyph := GameArt.texture("res://assets/art/ui/forest_rebuild/close-mural-v1.png")
		ImagePlacement.draw(button.get_canvas_item(), glyph, Rect2(center - Vector2(15,15), Vector2(30,30)), &"contain", color)
	)
	_pause_tab = PanelContainer.new()
	_pause_tab.name = "PauseTitleTab"
	_window.drag_top_extension = 23.0
	_window.attach_drag_handle(_pause_tab)
	_pause_tab.add_theme_stylebox_override("panel", PausePaper.make("title", 0))
	pause_root.add_child(_pause_tab)
	_pause_tab_text = Label.new()
	_pause_tab_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_tab_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_tab_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pause_tab_text.add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	_pause_tab_text.add_theme_font_size_override("font_size", 29)
	_pause_tab_text.add_theme_color_override("font_color", Color("ecdfc0"))
	_pause_tab.add_child(_pause_tab_text)
	_window.close_requested.connect(func() -> void: resume_requested.emit())
	page_root = _window
	_pause_title = _window.title_label
	_page_title = _window.title_label
	_pause_center = Control.new()
	_pause_center.name = "PauseCenter"
	_pause_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_window.body.add_child(_pause_center)
	var entries := VBoxContainer.new()
	_pause_entries = entries
	entries.name = "PauseEntries"
	entries.custom_minimum_size = Vector2(310.0, 0.0)
	entries.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entries.add_theme_constant_override("separation", 18)
	_pause_center.add_child(entries)
	_pause_center.resized.connect(_place_pause_entries.call_deferred)
	entries.resized.connect(_place_pause_entries.call_deferred)
	resume_button = _menu_button("ResumeButton")
	entries.add_child(resume_button)
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	new_journey_button = _menu_button("NewJourneyButton")
	entries.add_child(new_journey_button)
	new_journey_button.pressed.connect(_open_confirmation.bind("new_journey", ""))
	for page: String in ["saves", "settings"]:
		var button := _menu_button(page.capitalize() + "Button")
		button.pressed.connect(open_page.bind(page))
		entries.add_child(button)
		_menu_buttons[page] = button
	quit_button = _menu_button("QuitButton")
	entries.add_child(quit_button)
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	var ordered: Array[Button] = [resume_button, new_journey_button, _menu_buttons.saves, _menu_buttons.settings, quit_button]
	for index: int in ordered.size():
		_style_pause_button(ordered[index])
		var previous := ordered[posmod(index - 1, ordered.size())].get_path()
		var next := ordered[(index + 1) % ordered.size()].get_path()
		ordered[index].focus_neighbor_top = previous
		ordered[index].focus_neighbor_bottom = next
		ordered[index].focus_previous = previous
		ordered[index].focus_next = next


func _build_pages() -> void:
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	_page_column = column
	_window.body.add_child(column)
	back_button = Button.new()
	back_button.name = "BackButton"
	ThemeKit.apply_button(back_button)
	back_button.custom_minimum_size = Vector2(80.0, 36.0)
	back_button.add_theme_font_size_override("font_size", 16)
	back_button.pressed.connect(back)
	_window.actions.add_child(back_button)
	page_scroll = ScrollContainer.new()
	page_scroll.name = "PageScroll"
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page_scroll.follow_focus = true
	page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(page_scroll)
	_page_body = VBoxContainer.new()
	_page_body.name = "PageBody"
	_page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.add_child(_page_body)
	settings_panel = SettingsPanel.new()
	_page_body.add_child(settings_panel)
	settings_panel.status_requested.connect(show_status)
	settings_panel.back_requested.connect(back)
	saves_panel = SaveSlotsPanel.new()
	_page_body.add_child(saves_panel)
	saves_panel.save_clicked.connect(_on_save_clicked)
	saves_panel.load_clicked.connect(_on_load_clicked)
	saves_panel.back_requested.connect(back)
	_pages = {"settings": settings_panel, "saves": saves_panel}
	_status_label = Label.new()
	_status_label.name = "PageStatus"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 30.0
	_status_label.add_theme_font_size_override("font_size", 16)
	column.add_child(_status_label)


func _build_confirmation() -> void:
	get_viewport().gui_embed_subwindows = true
	confirmation_dialog = ConfirmationDialog.new()
	confirmation_dialog.transparent_bg = true
	confirmation_dialog.transparent = true
	confirmation_dialog.borderless = true
	confirmation_dialog.name = "SaveLoadConfirmation"
	confirmation_dialog.theme = _root.theme.duplicate()
	var confirmation_paper := preload("res://scripts/ui/settings_book_skin.gd").make()
	confirmation_paper.set_content_margin_all(28)
	confirmation_dialog.theme.set_stylebox("panel", "AcceptDialog", confirmation_paper)
	confirmation_dialog.exclusive = true
	confirmation_dialog.transient = true
	confirmation_dialog.unresizable = true
	confirmation_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	confirmation_dialog.min_size = Vector2i(500, 180)
	confirmation_dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmation_dialog.confirmed.connect(_on_confirmation_accepted)
	confirmation_dialog.canceled.connect(_close_confirmation.bind(true))
	pause_root.add_child(confirmation_dialog)
	preload("res://scripts/ui/settings_book_skin.gd").apply_button(confirmation_dialog.get_ok_button())
	preload("res://scripts/ui/settings_book_skin.gd").apply_button(confirmation_dialog.get_cancel_button())


func _menu_button(node_name: String) -> Button:
	var button := preload("res://scripts/ui/pause_reference_button.gd").new()
	button.name = node_name
	button.custom_minimum_size = Vector2(260.0, 44.0)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 20)
	return button


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _layout() -> void:
	if not is_instance_valid(day_root):
		return
	day_root.size = Vector2(104.0, 157.0)
	# HUD各自位于CanvasLayer，不能使用暂停根节点放大后的坐标而漏乘比例。
	var hud_ratio := UiScale.factor_for_pixels(get_window().size)
	var viewport_size := UiScale.reference_size(_root)
	var column := preload("res://scripts/ui/hud_column_layout.gd").metrics(viewport_size/hud_ratio,viewport_size)
	var reference_factor: float = column.reference_factor
	for item: Control in [day_root,day_progress,day_label,time_cycle_button]:
		item.scale = Vector2.ONE*hud_ratio*reference_factor
	hud_shade.position = Vector2(viewport_size.x-210.0*hud_ratio,0.0)
	hud_shade.size = Vector2(210.0*hud_ratio,viewport_size.y)
	day_root.position = column.portrait.position*hud_ratio
	day_root.size = Vector2(104,157)
	day_progress.position = column.axis.position*hud_ratio
	day_progress.size = Vector2(114,350)
	day_label.position = column.day.position*hud_ratio
	day_label.size = Vector2(102,22)
	time_cycle_button.position = column.time_controls.position*hud_ratio
	time_cycle_button.size = Vector2(72,36)
	if is_instance_valid(_window):
		_window.drag_top_extension = 24.0 if current_page == "main" else 0.0
		_window.set_viewport_bounds(Rect2(Vector2.ZERO, _root.size))
		var reference := UiScale.reference_size(_root)
		_pause_scale = minf(reference.x / 1672.0, reference.y / 941.0)
		if current_page == "main":
			_pause_entries.custom_minimum_size.x = 334 * _pause_scale
			_pause_entries.add_theme_constant_override("separation", roundi(22 * _pause_scale))
			for entry: Button in _pause_entries.get_children():
				entry.custom_minimum_size = Vector2(334, 76) * _pause_scale
				entry.add_theme_font_size_override("font_size", roundi(28 * _pause_scale))
		var desired := Vector2(460.0, 646.0) * _pause_scale if current_page == "main" else Vector2(minf(820.0, reference.x - 80.0), minf(790.0, reference.y - 80.0))
		if current_page in ["settings", "saves"]:
			desired = Vector2(minf(1000.0, reference.x - 48.0), minf(738.0, reference.y - 48.0))
		var at: Vector2 = (_root.size - desired) * 0.5
		_window.present(desired, at)
		_window_placed = true
		_place_pause_tab()
		_place_pause_entries.call_deferred()
		if is_instance_valid(confirmation_dialog):
			var ratio := UiScale.factor_for_pixels(get_window().size)
			confirmation_dialog.content_scale_factor = ratio
			confirmation_dialog.min_size = Vector2i(Vector2(500, 180) * ratio)


func _update_text() -> void:
	player_hud.refresh()
	_refresh_time_controls()
	resume_button.text = tr("PAUSE_RESUME")
	new_journey_button.text = tr("PAUSE_NEW_JOURNEY")
	quit_button.text = tr("MENU_RETURN_MAIN")
	for page: String in _menu_buttons:
		_menu_buttons[page].text = tr(str(PAGE_KEYS[page]))
	_window.set_title_key(str(PAGE_KEYS.get(current_page, "SESSION_PAUSED")))
	_window.set_paper_asset({"main": "pause_panel", "settings": "settings_panel", "saves": "save_panel"}.get(current_page, "pause_panel"))
	if current_page == "main":
		var pause_paper := PausePaper.make("panel", 24 * _pause_scale)
		pause_paper.content_margin_top = 16 * _pause_scale
		pause_paper.content_margin_right = 16 * _pause_scale
		_window.add_theme_stylebox_override("panel", pause_paper)
	elif current_page in ["settings", "saves"]:
		_window.add_theme_stylebox_override("panel", preload("res://scripts/ui/settings_book_paper.gd").make())
	_window.title_bar.visible = current_page == "main"
	_pause_tab_text.text = tr("SESSION_PAUSED")
	_window.title_label.modulate.a = 0.0 if current_page == "main" else 1.0
	_pause_tab.visible = current_page == "main"
	_window.close_button.visible = current_page != "main"
	_window.queue_redraw()
	back_button.text = tr("MENU_BACK")
	_update_status()
	_update_confirmation_text()


func _update_status() -> void:
	_status_label.text = tr(_status_key) if not _status_key.is_empty() else ""
	_status_label.add_theme_color_override("font_color", ThemeKit.RED if _status_is_error else ThemeKit.INK)
	_status_label.visible = false
	settings_panel.set_status(_status_label.text, _status_is_error)
	saves_panel.set_status(_status_label.text, _status_is_error)


func _place_pause_tab() -> void:
	if not is_instance_valid(_pause_tab):
		return
	_pause_tab.size = Vector2(190, 58) * _pause_scale
	_pause_tab_text.add_theme_font_size_override("font_size", roundi(32 * _pause_scale))
	_pause_tab.position = _window.position + Vector2((_window.size.x - _pause_tab.size.x) * 0.5, -23 * _pause_scale)


func _place_pause_entries() -> void:
	if not is_instance_valid(_pause_entries) or current_page != "main":
		return
	_pause_entries.size = _pause_entries.get_combined_minimum_size()
	var content_origin := _window.get_global_transform().affine_inverse() * _pause_center.global_position
	_pause_entries.position = Vector2(
		(_window.size.x - _pause_entries.size.x) * 0.5 - content_origin.x,
		104 * _pause_scale - content_origin.y
	)


func _style_pause_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(318, 66)
	button.add_theme_font_size_override("font_size", 25)
	button.add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	for state: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, Color("e9ddbd"))


func _day_text() -> String:
	var format_text := tr("SESSION_DAY_FORMAT")
	return format_text % _day if "%d" in format_text else format_text


func _apply_paused(animate: bool) -> void:
	if _menu_tween != null:
		_menu_tween.kill()
		_menu_tween = null
	pause_root.visible = _paused
	pause_root.modulate = Color.WHITE
	_window.modulate = Color.WHITE
	_apply_page_visibility()
	_update_text()
	_layout()
	if _paused:
		if animate:
			_focus_page.call_deferred(current_page)
			_window.modulate.a = 0.0
			_menu_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			_menu_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_menu_tween.tween_property(_window, "modulate:a", 1.0, 0.14)
	else:
		_window.cancel_drag()
		_window.modulate = Color.WHITE
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and pause_root.is_ancestor_of(focused):
			focused.release_focus()


func _apply_page_visibility() -> void:
	_pause_center.visible = current_page == "main"
	_page_column.visible = current_page != "main"
	back_button.visible = false
	for page: String in _pages:
		_pages[page].visible = current_page == page


func _style_content() -> void:
	for controls: Dictionary in saves_panel.slot_controls.values():
		preload("res://scripts/ui/settings_book_skin.gd").apply_button(controls.load_button)
		if controls.has("save_button"):
			preload("res://scripts/ui/settings_book_skin.gd").apply_button(controls.save_button)


func _focus_page(expected_page: String) -> void:
	if not _paused or current_page != expected_page:
		return
	match current_page:
		"main":
			resume_button.grab_focus()
		"settings":
			settings_panel.focus_current()
		"saves":
			saves_panel.focus_current()
		_:
			back_button.grab_focus()


func _on_save_clicked(slot: String, occupied: bool) -> void:
	if occupied:
		_open_confirmation("save", slot)
	else:
		save_requested.emit(slot)


func _on_load_clicked(slot: String) -> void:
	_open_confirmation("load", slot)


func _open_confirmation(action: String, slot: String) -> void:
	_pending_action = action
	_pending_slot = slot
	_dialog_previous_focus = get_viewport().gui_get_focus_owner()
	_update_confirmation_text()
	confirmation_dialog.popup_centered(Vector2i(Vector2(540, 210) * UiScale.factor_for_pixels(get_window().size)))
	confirmation_dialog.get_cancel_button().grab_focus()


func _update_confirmation_text() -> void:
	if not is_instance_valid(confirmation_dialog):
		return
	confirmation_dialog.ok_button_text = tr("MENU_CONFIRM")
	confirmation_dialog.cancel_button_text = tr("MENU_CANCEL")
	if _pending_action.is_empty():
		return
	if _pending_action == "quit_without_save":
		confirmation_dialog.ok_button_text = tr("QUIT_WITHOUT_SAVE")
		confirmation_dialog.title = tr("QUIT_SAVE_FAILED_TITLE")
		confirmation_dialog.dialog_text = tr("QUIT_SAVE_FAILED_BODY")
		return
	if _pending_action == "new_journey":
		confirmation_dialog.title = tr("NEW_JOURNEY_CONFIRM_TITLE")
		confirmation_dialog.dialog_text = tr("NEW_JOURNEY_CONFIRM_BODY")
		return
	var is_save := _pending_action == "save"
	confirmation_dialog.title = tr("SAVE_OVERWRITE_TITLE" if is_save else "LOAD_CONFIRM_TITLE")
	confirmation_dialog.dialog_text = tr("SAVE_OVERWRITE_BODY" if is_save else "LOAD_CONFIRM_BODY") % saves_panel.slot_title(_pending_slot)


func _close_confirmation(restore_focus: bool = true) -> void:
	if is_instance_valid(confirmation_dialog):
		confirmation_dialog.hide()
	_pending_action = ""
	_pending_slot = ""
	if restore_focus and is_instance_valid(_dialog_previous_focus) and _dialog_previous_focus.is_visible_in_tree():
		_dialog_previous_focus.grab_focus()
	_dialog_previous_focus = null


func _on_confirmation_accepted() -> void:
	var action := _pending_action
	var slot := _pending_slot
	_close_confirmation(true)
	if action == "save":
		save_requested.emit(slot)
	elif action == "load":
		load_requested.emit(slot)
	elif action == "quit_without_save":
		quit_without_save_requested.emit()
	elif action == "new_journey":
		new_journey_requested.emit()
