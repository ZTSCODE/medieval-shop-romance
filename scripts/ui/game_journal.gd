class_name GameJournal
extends CanvasLayer

signal toggle_requested(page: String)
signal open_state_changed(value: bool)
const PAGE_KEYS := {"recipes": "MENU_RECIPES", "npcs": "MENU_NPCS"}
const BUTTON_KEYS := {"recipes": "JOURNAL_RECIPES_BUTTON", "npcs": "JOURNAL_NPCS_BUTTON"}
const ThemeKit = preload("res://scripts/ui/game_theme.gd")
const BookPaper = preload("res://scripts/ui/settings_book_paper.gd")
const BookSkin = preload("res://scripts/ui/settings_book_skin.gd")
const DESIGN_SIZE := Vector2(960, 700)
var current_page := ""
var buttons: Dictionary = {}
var panel: PanelContainer
var page_scroll: ScrollContainer
var _page_canvas: Control
var recipes_panel: JournalPanel
var npcs_panel: JournalPanel
var close_button: Button
var _root: Control
var _entries: VBoxContainer
var _progress: PlayerProgress
var _reveal: Tween
var _paper_heading: PanelContainer
var _paper_heading_label: Label
var _entries_visible_target := true
var _entries_motion: Tween
var tabs: Dictionary = {}
var _entry_scale := 1.0
var _entry_offset := 0.0
var _page_motion: Tween

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 19

func _ready() -> void:
	_root = Control.new()
	_root.name = "GameJournalRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = ThemeKit.make_theme()
	_root.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_entries = VBoxContainer.new()
	_entries.name = "JournalEntries"
	_entries.add_theme_constant_override("separation", 12)
	_entries.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_entries)
	for page: String in PAGE_KEYS:
		var button := preload("res://scripts/ui/ebb_journal_button.gd").new()
		button.name = page.capitalize() + "JournalButton"
		button.custom_minimum_size = Vector2(88,68)
		button.entry_kind = page
		button.toggle_mode = true
		button.pressed.connect(func() -> void: toggle_requested.emit(page))
		for state in ["normal","hover","pressed","disabled","focus","hover_pressed"]:
			button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		_entries.add_child(button)
		buttons[page] = button
	_build_panel()
	_root.resized.connect(_layout)
	UiScale.bind(_root, _layout)
	_update_text()
	_layout()
	close()

func configure(progress: PlayerProgress) -> void:
	_progress = progress
	if is_node_ready():
		recipes_panel.configure(progress,"recipes")
		npcs_panel.configure(progress,"npcs")

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_text()
		_layout.call_deferred()

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "GameJournalPanel"
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.add_child(panel)
	page_scroll = ScrollContainer.new()
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(page_scroll)
	_page_canvas = Control.new()
	_page_canvas.custom_minimum_size = DESIGN_SIZE
	page_scroll.add_child(_page_canvas)
	_page_canvas.draw.connect(_draw_book)
	for id: String in PAGE_KEYS:
		var tab := preload("res://scripts/ui/settings_book_tab.gd").new()
		tab.name = id.capitalize() + "JournalTab"
		tab.position = Vector2(42 + tabs.size() * 93, 4)
		tab.size = Vector2(88, 76)
		tab.toggle_mode = true
		var art := AtlasTexture.new()
		art.atlas = GameArt.texture("res://assets/art/ui/forest_rebuild/recipe-solid.png" if id == "recipes" else "res://assets/art/ui/forest_rebuild/relationship-solid.png")
		art.region = Rect2(272,348,742,642) if id == "recipes" else Rect2(286,404,684,538)
		var icon := preload("res://scripts/ui/ui_icon_texture.gd").new()
		icon.source = art
		icon.logical_size = Vector2i(40, 40)
		tab.icon = icon
		tab.pressed.connect(func():
			if current_page != id:
				toggle(id)
			else:
				tab.set_pressed_no_signal(true)
		)
		_page_canvas.add_child(tab)
		tab.visual_changed.connect(_page_canvas.queue_redraw)
		tabs[id] = tab
	_paper_heading = PanelContainer.new()
	_paper_heading.position = Vector2(250, 78)
	_paper_heading.size = Vector2(460, 48)
	_paper_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper_heading.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_page_canvas.add_child(_paper_heading)
	_paper_heading_label = Label.new()
	_paper_heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paper_heading_label.add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	_paper_heading_label.add_theme_font_size_override("font_size", 32)
	_paper_heading_label.add_theme_color_override("font_color", BookSkin.INK)
	_paper_heading.add_child(_paper_heading_label)
	recipes_panel = JournalPanel.new()
	npcs_panel = JournalPanel.new()
	for body: JournalPanel in [recipes_panel, npcs_panel]:
		body.position = Vector2(68, 150)
		body.size = Vector2(824, 430)
		_page_canvas.add_child(body)
	recipes_panel.configure(_progress, "recipes")
	npcs_panel.configure(_progress, "npcs")
	close_button = Button.new()
	close_button.position = Vector2(620, 594)
	close_button.size = Vector2(220, 48)
	_page_canvas.add_child(close_button)
	BookSkin.apply_button(close_button)
	close_button.pressed.connect(close)

func _draw_book() -> void:
	for tab: Button in tabs.values():
		var rect: Rect2 = tab.visual_rect(Rect2(Vector2.ZERO, Vector2(tab.size.x, 96)))
		rect.position += tab.position
		BookPaper.draw_bookmark(_page_canvas.get_canvas_item(), rect, tab.selection)
	BookPaper.draw_page(_page_canvas.get_canvas_item(), Rect2(Vector2(0, 58), Vector2(960, 617)))

func toggle(page: String) -> void:
	if not PAGE_KEYS.has(page) or not _root.visible:
		return
	if current_page == page:
		close()
		return
	var opening := current_page.is_empty()
	current_page = page
	if is_instance_valid(_reveal):
		_reveal.kill()
	panel.show()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.modulate.a = 1.0
	recipes_panel.visible = page == "recipes"
	npcs_panel.visible = page == "npcs"
	_update_text()
	_update_buttons()
	if opening:
		open_state_changed.emit(true)
		_entry_scale = 0.94
		_entry_offset = 20.0
		panel.modulate.a = 0.0
		_reveal = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_reveal.tween_property(panel, "modulate:a", 1.0, 0.15)
		_reveal.tween_method(_spring_step, 0.0, 0.72, 0.72)
		_reveal.chain().tween_callback(func():
			_entry_scale = 1.0
			_entry_offset = 0.0
			_place_page()
		)
	else:
		_entry_scale = 1.0
		_entry_offset = 0.0
		var body: Control = recipes_panel if page == "recipes" else npcs_panel
		if is_instance_valid(_page_motion):
			_page_motion.kill()
		body.modulate.a = 0.4
		_page_motion = create_tween()
		_page_motion.tween_property(body, "modulate:a", 1.0, 0.16)
	_place_page()
	close_button.grab_focus()

func _spring_step(time: float) -> void:
	var p := 1.0 - exp(-8.0 * time) * (cos(16.0 * time) + 0.5 * sin(16.0 * time))
	_entry_scale = lerpf(0.94, 1.0, p)
	_entry_offset = lerpf(20.0, 0.0, p)
	_place_page()

func close() -> void:
	var was_open := not current_page.is_empty()
	current_page = ""
	if not is_instance_valid(panel):
		return
	if is_instance_valid(_reveal):
		_reveal.kill()
	_update_buttons()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and _root.is_ancestor_of(focused):
		focused.release_focus()
	if not was_open:
		panel.hide()
		return
	_reveal = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_reveal.tween_property(panel, "modulate:a", 0.0, 0.18)
	_reveal.tween_callback(func(): panel.hide())
	open_state_changed.emit(false)

func is_open() -> bool:
	return not current_page.is_empty()

func set_game_paused(value: bool) -> void:
	if value:
		close()
	for button: Button in buttons.values():
		button.disabled = value

func blocks_pointer(point: Vector2) -> bool:
	if not is_instance_valid(_root) or not _root.is_visible_in_tree():
		return false
	for button: Button in buttons.values():
		if button.is_visible_in_tree() and button.get_global_rect().has_point(point):
			return true
	return panel.visible and (panel.get_global_rect().has_point(point) or _paper_heading.get_global_rect().has_point(point))

func refresh() -> void:
	if is_instance_valid(recipes_panel):
		recipes_panel.refresh()
	if is_instance_valid(npcs_panel):
		npcs_panel.refresh()

func _layout() -> void:
	if not is_instance_valid(panel):
		return
	var entry_size := _entries.get_combined_minimum_size()
	_entries.size = entry_size
	var column := preload("res://scripts/ui/hud_column_layout.gd").metrics(_root.size,UiScale.reference_size(_root))
	var column_scale: float = column.reference_factor
	_entries.scale = Vector2.ONE * column_scale
	_entries.position = column.entries_center-Vector2(entry_size.x*column_scale*0.5,0)
	_place_page()

func _place_page() -> void:
	var factor := minf(1.0, minf((_root.size.x - 56) / DESIGN_SIZE.x, (_root.size.y - 32) / DESIGN_SIZE.y))
	panel.size = DESIGN_SIZE
	panel.scale = Vector2.ONE * factor * _entry_scale
	panel.position = (_root.size - DESIGN_SIZE * panel.scale) * 0.5 + Vector2(0, _entry_offset * factor)

func _update_text() -> void:
	for page: String in buttons:
		buttons[page].text = ""
	close_button.text = tr("WINDOW_CLOSE")
	_paper_heading_label.text = tr("HUD_RECIPES_SHORT" if current_page == "recipes" else "MENU_NPCS")

func _update_buttons() -> void:
	for page: String in tabs:
		tabs[page].set_pressed_no_signal(current_page == page)
		tabs[page]._update_selection()
	_page_canvas.queue_redraw()
	for page: String in buttons:
		buttons[page].set_pressed_no_signal(current_page == page)

func set_entries_visible(value: bool) -> void:
	if not is_instance_valid(_entries) or _entries_visible_target == value:
		return
	_entries_visible_target = value
	if is_instance_valid(_entries_motion):
		_entries_motion.kill()
	_entries.mouse_filter = Control.MOUSE_FILTER_PASS if value else Control.MOUSE_FILTER_IGNORE
	for button: Button in buttons.values():
		button.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if value:
		_entries.visible = true
	_entries_motion = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_entries_motion.tween_property(_entries,"modulate:a",1.0 if value else 0.0,0.2)
	if not value:
		_entries_motion.tween_callback(func(): _entries.visible = false)
