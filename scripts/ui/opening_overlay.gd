class_name OpeningOverlay
extends CanvasLayer

signal advance_requested

const Rail = preload("res://scripts/ui/narrative_rail_style.gd")
const BottomPaper = preload("res://scripts/ui/bottom_dialogue_paper.gd")
const TextLayout = preload("res://scripts/ui/dialogue_text_layout.gd")
const BODY_FONT_SIZE := 28
const NAME_FONT_SIZE := 32
const CONTINUE_FONT_SIZE := 25

var intro_visible := false
var intro_index := 0
var story_label: Label
var continue_button: Button
var tutorial_label: Label
var text_panel: PanelContainer
var _root: Control
var _intro_root: Control
var _content: ScrollContainer
var _title: Label
var _page_label: Label
var _page_total := 0
var _tutorial_key := ""
var _menu_paused := false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 16

func _ready() -> void:
	_root = Control.new()
	_root.name = "OpeningOverlayRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameTheme.make_theme()
	_intro_root = Control.new()
	_intro_root.name = "OpeningIntro"
	_intro_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_intro_root)
	_intro_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_panel = PanelContainer.new()
	text_panel.name = "OpeningTextWindow"
	text_panel.add_theme_stylebox_override("panel", BottomPaper.create())
	text_panel.material = BottomPaper.material()
	text_panel.gui_input.connect(_on_intro_gui_input)
	_intro_root.add_child(text_panel)
	_title = Rail.label("OpeningTitle", NAME_FONT_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_stylebox_override("normal", preload("res://scripts/ui/paper_skin.gd").make(&"heading",6))
	_intro_root.add_child(_title)
	_content = ScrollContainer.new()
	_content.name = "OpeningText"
	_content.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.gui_input.connect(_on_intro_gui_input)
	_intro_root.add_child(_content)
	story_label = Rail.label("OpeningStory", BODY_FONT_SIZE)
	_content.add_child(story_label)
	_page_label = Rail.label("OpeningPageNumber", 14, Rail.MUTED)
	_intro_root.add_child(_page_label)
	continue_button = Button.new()
	continue_button.name = "OpeningContinue"
	Rail.setup_button(continue_button)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		continue_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	preload("res://scripts/ui/paper_button_feedback.gd").bind(continue_button)
	continue_button.add_theme_color_override("font_color", Color("e5d6b4"))
	continue_button.add_theme_color_override("font_hover_color", Color("fff0d1"))
	continue_button.pressed.connect(advance)
	_intro_root.add_child(continue_button)
	tutorial_label = Rail.label("OpeningTutorial", 18)
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(tutorial_label)
	_root.resized.connect(_layout)
	UiScale.bind(_root, _layout)
	_update_text()
	_layout()
	_apply_visibility()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_text()
		_layout.call_deferred()

func show_intro(index: int, total: int = -1) -> void:
	var available := OpeningFlow.intro_page_count()
	if available == 0:
		hide_all()
		return
	var previous_index := intro_index
	_page_total = available if total < 0 else clampi(total, 1, available)
	intro_index = clampi(index, 0, _page_total - 1)
	var changed_page := not intro_visible or previous_index != intro_index
	intro_visible = true
	_tutorial_key = ""
	if not is_node_ready():
		return
	_update_text()
	_apply_visibility()
	_layout()
	if changed_page:
		_content.scroll_vertical = 0

func show_tutorial(key: String) -> void:
	intro_visible = false
	_tutorial_key = key
	if is_node_ready():
		_update_text()
		_apply_visibility()
		_layout()

func hide_all() -> void:
	intro_visible = false
	_tutorial_key = ""
	if is_node_ready():
		_apply_visibility()

func set_menu_paused(value: bool) -> void:
	_menu_paused = value
	if is_node_ready():
		continue_button.disabled = value
		_content.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP

func blocks_pointer(point: Vector2) -> bool:
	return intro_visible and is_instance_valid(_intro_root) and _intro_root.is_visible_in_tree() and _intro_root.get_global_rect().has_point(point)

func advance() -> void:
	if intro_visible and not _menu_paused:
		advance_requested.emit()

func _layout() -> void:
	if not is_instance_valid(_content):
		return
	var reference := UiScale.reference_size(_root)
	var rect := UiScale.bottom_rect(BottomPaper.metrics(reference), reference, _root.size)
	var scale := minf(reference.y / 941.0, reference.x / 1250.0)
	var text_width := rect.size.x - 100 * scale
	var text_height := TextLayout.measure(story_label, text_width, roundi(24 * scale))
	rect = BottomPaper.fit_text(rect, text_height, scale, _root.size)
	text_width = rect.size.x - 100 * scale
	text_height = TextLayout.measure(story_label, text_width, roundi(24 * scale))
	text_panel.position = rect.position
	text_panel.size = rect.size
	_title.add_theme_font_size_override("font_size", roundi(23 * scale))
	_title.position = rect.position + Vector2(26, -22) * scale
	_title.size = Vector2(158, 44) * scale
	_content.position = rect.position + Vector2(50, 34) * scale
	_content.size = Vector2(text_width, rect.size.y - 94 * scale)
	_content.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if text_height > _content.size.y else ScrollContainer.SCROLL_MODE_DISABLED
	continue_button.add_theme_font_size_override("font_size", roundi(22 * scale))
	continue_button.position = rect.position + Vector2(rect.size.x - 150 * scale, rect.size.y - 52 * scale)
	continue_button.size = Vector2(126, 39) * scale
	_page_label.position = rect.position + Vector2(50 * scale, rect.size.y - 46 * scale)
	_page_label.size = Vector2(100, 30) * scale
	var tutorial_width := minf(940.0, maxf(_root.size.x - 96.0, 240.0))
	tutorial_label.position = Vector2((_root.size.x - tutorial_width) * 0.5, 88.0)
	tutorial_label.size = Vector2(tutorial_width, 58.0)

func _update_text() -> void:
	var definition := ContentCatalog.opening_definition()
	var title_key := String(definition.get("title_key", ""))
	_title.text = tr(title_key) if not title_key.is_empty() else ""
	_title.visible = not title_key.is_empty()
	var page_keys: Array = definition.get("pages", [])
	var page_key := String(page_keys[intro_index]) if intro_index < page_keys.size() else ""
	story_label.text = tr(page_key) if not page_key.is_empty() else ""
	continue_button.text = tr("OPENING_ENTER" if intro_index == _page_total - 1 else "OPENING_CONTINUE")
	var page_format := tr("OPENING_PAGE_FORMAT")
	_page_label.text = page_format % [intro_index + 1, _page_total] if page_format.count("%d") == 2 else page_format
	tutorial_label.text = tr(_tutorial_key) if not _tutorial_key.is_empty() else ""

func _apply_visibility() -> void:
	_intro_root.visible = intro_visible
	tutorial_label.visible = not intro_visible and not _tutorial_key.is_empty()
	continue_button.disabled = _menu_paused

func _on_intro_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_intro_root.accept_event()
		advance()
