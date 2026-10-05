class_name OpeningOverlay
extends CanvasLayer

signal advance_requested
signal finish_requested  # 开场动画播完或被跳过：序幕一次读完

const Rail = preload("res://scripts/ui/narrative_rail_style.gd")
const ChronicleViewScript = preload("res://scripts/ui/chronicle_view.gd")
const FilmViewScript = preload("res://scripts/ui/opening_film_view.gd")
const BottomPaper = preload("res://scripts/ui/bottom_dialogue_paper.gd")
const TextLayout = preload("res://scripts/ui/dialogue_text_layout.gd")
const BODY_FONT_SIZE := 28
const NAME_FONT_SIZE := 32
const CONTINUE_FONT_SIZE := 25

var intro_visible := false
# 关掉后序幕退回逐页显示（与视频缺失时走同一条路）；逐页序幕的走查测试用。
var film_enabled := true
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
var _chronicle: Control  # chronicle_view.gd
var _film: Control  # opening_film_view.gd

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
	# 序幕页（page_layouts 中 style 为 chronicle）用全屏呈现，其余页仍用底部文字框。
	_chronicle = ChronicleViewScript.new()
	_chronicle.advance_requested.connect(advance)
	_intro_root.add_child(_chronicle)
	# 内容里配置了开场动画（opening.film）且视频存在时，整段序幕改为播放动画；否则仍逐页显示。
	_film = FilmViewScript.new()
	_film.finished.connect(func() -> void: finish_requested.emit())
	_intro_root.add_child(_film)
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
	preload("res://scripts/ui/dialogue_hover_paper.gd").bind(continue_button)
	continue_button.add_theme_stylebox_override("hover_pressed", StyleBoxEmpty.new())
	continue_button.add_theme_color_override("font_pressed_color", Color("fff0d1"))
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
	if is_instance_valid(_chronicle):
		_chronicle.set_menu_paused(value)
	if is_instance_valid(_film):
		_film.set_menu_paused(value)
	if is_node_ready():
		continue_button.disabled = value
		_content.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP

func blocks_pointer(point: Vector2) -> bool:
	return intro_visible and is_instance_valid(_intro_root) and _intro_root.is_visible_in_tree() and _intro_root.get_global_rect().has_point(point)

func advance() -> void:
	# 动画播放期间不逐页前进，只能看完或点“跳过”。
	if intro_visible and not _menu_paused and not is_film_showing():
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
	continue_button.position = rect.position + Vector2(rect.size.x - 184 * scale, rect.size.y - 76 * scale)
	continue_button.size = Vector2(160, 54) * scale
	_page_label.position = rect.position + Vector2(50 * scale, rect.size.y - 46 * scale)
	_page_label.size = Vector2(100, 30) * scale
	var tutorial_width := minf(940.0, maxf(_root.size.x - 96.0, 240.0))
	tutorial_label.position = Vector2((_root.size.x - tutorial_width) * 0.5, 88.0)
	tutorial_label.size = Vector2(tutorial_width, 58.0)

func _update_text() -> void:
	var definition := ContentCatalog.opening_definition()
	var title_key := String(definition.get("title_key", ""))
	# 可选的逐页标题（如序幕与逃亡各用一个标题）；没填的页沿用 title_key。
	var page_titles: Variant = definition.get("page_titles", [])
	if page_titles is Array and intro_index < page_titles.size() and page_titles[intro_index] is String and not String(page_titles[intro_index]).is_empty():
		title_key = String(page_titles[intro_index])
	_title.text = tr(title_key) if not title_key.is_empty() else ""
	_title.visible = not title_key.is_empty()
	var page_keys: Array = definition.get("pages", [])
	var page_key := String(page_keys[intro_index]) if intro_index < page_keys.size() else ""
	story_label.text = tr(page_key) if not page_key.is_empty() else ""
	_sync_chronicle(definition, page_key, title_key)
	continue_button.text = tr("OPENING_ENTER" if intro_index == _page_total - 1 else "OPENING_CONTINUE")
	var page_format := tr("OPENING_PAGE_FORMAT")
	_page_label.text = page_format % [intro_index + 1, _page_total] if page_format.count("%d") == 2 else page_format
	tutorial_label.text = tr(_tutorial_key) if not _tutorial_key.is_empty() else ""

# 当前页是否用全屏序幕呈现；是则隐藏底部文字框的各个部件。
func _sync_chronicle(definition: Dictionary, page_key: String, title_key: String) -> void:
	if not is_instance_valid(_chronicle):
		return
	if intro_visible and film_enabled and is_instance_valid(_film) and FilmViewScript.available(definition):
		_film.show_film(definition)
		_chronicle.hide_view()
		for part: Control in [text_panel, _content, _page_label, continue_button, _title]:
			part.visible = false
		return
	if is_instance_valid(_film):
		_film.hide_view()
	var layouts: Variant = definition.get("page_layouts", [])
	var layout: Variant = layouts[intro_index] if layouts is Array and intro_index < layouts.size() else {}
	var chronicle: bool = intro_visible and layout is Dictionary and layout.get("style", "") == "chronicle"
	if chronicle:
		_chronicle.show_page(page_key, String(layout.get("art", "")))
	else:
		_chronicle.hide_view()
	for part: Control in [text_panel, _content, _page_label, continue_button]:
		part.visible = not chronicle
	_title.visible = not chronicle and not title_key.is_empty()


func is_chronicle_showing() -> bool:
	return (is_instance_valid(_chronicle) and _chronicle.is_showing()) or is_film_showing()


func is_film_showing() -> bool:
	return is_instance_valid(_film) and _film.is_showing()


func _apply_visibility() -> void:
	_intro_root.visible = intro_visible
	if not intro_visible and is_instance_valid(_chronicle):
		_chronicle.hide_view()
	if not intro_visible and is_instance_valid(_film):
		_film.hide_view()
	tutorial_label.visible = not intro_visible and not _tutorial_key.is_empty()
	continue_button.disabled = _menu_paused

func _on_intro_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_intro_root.accept_event()
		advance()
