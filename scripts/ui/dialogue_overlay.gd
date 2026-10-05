class_name DialogueOverlay
extends CanvasLayer

signal presentation_finished

const Rail = preload("res://scripts/ui/narrative_rail_style.gd")
const BottomPaper = preload("res://scripts/ui/reference_dialogue_paper.gd")
const TextLayout = preload("res://scripts/ui/dialogue_text_layout.gd")
const BODY_FONT_SIZE := 28
const NAME_FONT_SIZE := 32
const CONTINUE_FONT_SIZE := 25

var flow: DialogueFlow
var text_panel: PanelContainer
var speaker_label: Label
var story_label: Label
var continue_button: Button
var hero_portrait: TextureRect
var npc_portrait: TextureRect
var player_name := ""

var _root: Control
var _stage: Control
var _content: ScrollContainer
var _hint: Label
var _page_label: Label
var _menu_paused := false
var _shown_key := ""
var _characters := 0.0
var _presentation := 0.0
var _presentation_target := 0.0
var _speaker_blend := 0.0
var _hero_speaking := false
var _narrating := false
var _narration_blend := 0.0
var _leaf: TextureRect
var _divider: ColorRect
var _speaker_tab: Panel
var _choice_scroll: ScrollContainer
var _choice_root: Control
var _choice_buttons: Array[Button] = []
var _choice_specs: Array = []
var _choice_signature := ""
const PRESENTATION_DURATION := 0.28

func _init() -> void:
	layer = 17
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_root = Control.new()
	_root.name = "DialogueRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameTheme.make_theme()
	text_panel = PanelContainer.new()
	text_panel.name = "DialogueTextWindow"
	text_panel.add_theme_stylebox_override("panel", BottomPaper.create())
	text_panel.material = BottomPaper.material()
	text_panel.z_index = 3
	text_panel.gui_input.connect(_on_text_input)
	_root.add_child(text_panel)
	_speaker_tab = Panel.new()
	_speaker_tab.name = "DialogueSpeakerTab"
	_speaker_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker_tab.z_index = 5
	_speaker_tab.add_theme_stylebox_override("panel", preload("res://scripts/ui/paper_skin.gd").make(&"heading"))
	_root.add_child(_speaker_tab)
	_speaker_tab.hide()
	speaker_label = Rail.label("DialogueSpeaker", NAME_FONT_SIZE)
	speaker_label.z_index = 6
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speaker_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	speaker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_root.add_child(speaker_label)
	_leaf = TextureRect.new()
	_leaf.texture = GameArt.texture("res://assets/art/ui/forest_rebuild/type-leaf.png")
	_leaf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_leaf.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_leaf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leaf.modulate = Color("a99a79")
	_leaf.z_index = 4
	_root.add_child(_leaf)
	_leaf.hide()
	_divider = ColorRect.new()
	_divider.color = Color(0.68, 0.61, 0.46, 0.44)
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_divider)
	_divider.hide()
	_content = ScrollContainer.new()
	_content.name = "DialogueText"
	_content.z_index = 4
	_content.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.gui_input.connect(_on_text_input)
	_root.add_child(_content)
	story_label = Rail.label("DialogueSubtitle", BODY_FONT_SIZE)
	story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	story_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_content.add_child(story_label)
	_choice_scroll = ScrollContainer.new()
	_choice_scroll.name = "DialogueChoices"
	_choice_scroll.z_index = 8
	_choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_root.add_child(_choice_scroll)
	_choice_root = Control.new()
	_choice_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_scroll.add_child(_choice_root)
	_choice_scroll.hide()
	_stage = Control.new()
	_stage.name = "DialoguePortraitStage"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.clip_contents = false
	_root.add_child(_stage)
	hero_portrait = _portrait("PlayerPortrait")
	npc_portrait = _portrait("NpcPortrait")
	_stage.add_child(hero_portrait)
	_stage.add_child(npc_portrait)
	_hint = Rail.label("DialogueHint", 13, Rail.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_hint)
	_page_label = Rail.label("DialoguePage", 13, Rail.MUTED)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_page_label)
	continue_button = Button.new()
	continue_button.name = "DialogueContinue"
	continue_button.z_index = 10
	Rail.setup_button(continue_button)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		continue_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	preload("res://scripts/ui/paper_button_feedback.gd").bind(continue_button)
	continue_button.add_theme_color_override("font_color", Color("e5d6b4"))
	continue_button.add_theme_color_override("font_hover_color", Color("fff0d1"))
	continue_button.pressed.connect(advance)
	_root.add_child(continue_button)
	preload("res://scripts/ui/dialogue_hover_paper.gd").bind(continue_button)
	continue_button.add_theme_color_override("font_pressed_color", Color("fff0d1"))
	for text_control: Control in [speaker_label, story_label, continue_button]:
		text_control.add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	continue_button.draw.connect(func() -> void:
		var end := Vector2(continue_button.size.x - 5, continue_button.size.y * 0.5)
		var hover_paper := continue_button.get_node_or_null("DialogueHoverPaper") as Control
		var ink := Color("d5c6a4").lerp(Color("eadfc7"), hover_paper.modulate.a if hover_paper != null else 0.0)
		continue_button.draw_colored_polygon(PackedVector2Array([end + Vector2(-8, -9), end, end + Vector2(-8, 9)]), ink)
	)
	_hint.hide()
	_page_label.hide()
	_root.resized.connect(_layout)
	UiScale.bind(_root, _layout)
	_root.hide()
	_layout()
	if flow != null:
		sync()

func set_player_name(value: String) -> void:
	player_name = value
	if is_node_ready():
		sync()

func configure(value: DialogueFlow) -> void:
	if flow != null and flow.changed.is_connected(sync):
		flow.changed.disconnect(sync)
	flow = value
	if flow != null:
		flow.changed.connect(sync)
	sync()

func sync() -> void:
	if not is_node_ready() or flow == null:
		return
	if not flow.is_active():
		_presentation_target = 0.0
		_shown_key = ""
		return
	var entering := not is_presenting()
	_root.show()
	_presentation_target = 1.0
	var line := flow.current_line()
	var hero_speaking := String(line.get("speaker", "")) == "hero"
	_hero_speaking = hero_speaking
	if entering:
		_speaker_blend = 1.0 if hero_speaking else 0.0
	var npc_definition := ContentCatalog.npc_definition(flow.active_npc_id)
	var info: Dictionary = flow.call("presentation_info") if flow.has_method("presentation_info") else {}
	var narrator: bool = info.get("narrator", false)
	_narrating = narrator
	if entering:
		_narration_blend = 1.0 if narrator else 0.0
	speaker_label.text = tr("DIALOGUE_NARRATOR") if narrator else ((player_name if not player_name.is_empty() else tr("PLAYER_DEFAULT_NAME")) if hero_speaking else tr(String(npc_definition.get("name_key", ""))))
	story_label.text = tr(String(line.get("text_key", "")))
	var marker: String = info.get("marker", flow.story_id + ":" + str(flow.line_index))
	_sync_choices(info)
	if marker != _shown_key:
		_characters = 0.0
		story_label.visible_characters = 0
		_content.scroll_vertical = 0
		_shown_key = marker
	hero_portrait.texture = _close_portrait(GameArt.portrait("hero"))
	npc_portrait.texture = _close_portrait(GameArt.portrait(flow.active_npc_id))
	hero_portrait.show()
	npc_portrait.visible = not bool(info.get("npc_hidden", false))
	var total: int = int(info.get("total", 0)) if not info.is_empty() else ContentCatalog.story_definition(flow.story_id).lines.size()
	_page_label.text = tr("OPENING_PAGE_FORMAT") % [flow.line_index + 1, total]
	var last_line: bool = info.get("last_line", flow.line_index == total - 1)
	continue_button.text = tr("DIALOGUE_FINISH" if last_line else "DIALOGUE_CONTINUE")
	continue_button.visible = _choice_specs.is_empty()
	_hint.text = tr("DIALOGUE_SHORT_HINT")
	continue_button.disabled = _menu_paused
	_layout()

func _process(delta: float) -> void:
	if flow == null or _menu_paused or not is_presenting():
		return
	_presentation = move_toward(_presentation, _presentation_target, delta / PRESENTATION_DURATION)
	_speaker_blend = move_toward(_speaker_blend, 1.0 if _hero_speaking else 0.0, delta / 0.24)
	_narration_blend = move_toward(_narration_blend, 1.0 if _narrating else 0.0, delta / 0.24)
	_layout()
	if _presentation_target == 0.0 and _presentation <= 0.0:
		_root.hide()
		presentation_finished.emit()
		return
	if not flow.is_active():
		return
	_characters += delta * 38.0
	story_label.visible_characters = mini(int(_characters), story_label.get_total_character_count())

func is_presenting() -> bool:
	return _presentation_target > 0.0 or _presentation > 0.0

func advance() -> void:
	if flow == null or not flow.is_active() or _menu_paused:
		return
	if story_label.visible_characters >= 0 and story_label.visible_characters < story_label.get_total_character_count():
		_characters = story_label.get_total_character_count()
		story_label.visible_characters = -1
	else:
		flow.advance()

func set_menu_paused(value: bool) -> void:
	_menu_paused = value
	if flow != null and flow.has_method("set_menu_paused"):
		flow.call("set_menu_paused", value)
	if is_node_ready():
		continue_button.disabled = value
		_content.mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_STOP
		for button: Button in _choice_buttons:
			button.disabled = value or bool(button.get_meta("replay_locked", false))

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and flow != null:
		sync()

func _layout() -> void:
	if not is_instance_valid(text_panel):
		return
	var screen := UiScale.reference_size(_root)
	var scale := minf(screen.y / 941.0, screen.x / 1250.0)
	var rect := UiScale.bottom_rect(BottomPaper.metrics(screen), screen, _root.size)
	var text_width := rect.size.x - 134 * scale
	var text_height := TextLayout.measure(story_label, text_width, roundi(26 * scale))
	var choices_height := _layout_choices(text_width, scale)
	var choices_view_height := minf(choices_height, screen.y * 0.32)
	rect = BottomPaper.fit_text(rect, text_height + choices_view_height, scale, _root.size)
	text_width = rect.size.x - 134 * scale
	text_height = TextLayout.measure(story_label, text_width, roundi(26 * scale))
	choices_height = _layout_choices(text_width, scale)
	choices_view_height = minf(choices_height, screen.y * 0.32)
	var body_top := BottomPaper.body_top(rect, scale)
	choices_view_height = minf(choices_view_height, maxf(0.0, rect.size.y - body_top - 60 * scale - minf(text_height, 84 * scale)))
	text_panel.position = rect.position
	text_panel.size = rect.size
	_speaker_tab.position = rect.position + rect.size * Vector2(0.057, 0.014)
	_speaker_tab.size = rect.size * Vector2(0.174, 0.245)
	speaker_label.add_theme_font_size_override("font_size", roundi(23 * scale))
	speaker_label.add_theme_color_override("font_color", Color("eadfc7"))
	speaker_label.position = _speaker_tab.position + Vector2(10, 0) * scale
	speaker_label.size = _speaker_tab.size - Vector2(20, 0) * scale
	_leaf.position = Vector2(rect.position.x + 25 * scale, rect.end.y - 80 * scale)
	_leaf.size = Vector2(38, 59) * scale
	_leaf.modulate.a = 0.42
	_content.position = rect.position + Vector2(88 * scale, body_top)
	_content.size = Vector2(text_width, rect.size.y - body_top - 60 * scale - choices_view_height)
	_content.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if text_height > _content.size.y else ScrollContainer.SCROLL_MODE_DISABLED
	_choice_scroll.position = _content.position + Vector2(0, _content.size.y + 8 * scale)
	_choice_scroll.size = Vector2(text_width, choices_view_height)
	_choice_root.custom_minimum_size = Vector2(0, choices_height)
	story_label.add_theme_color_override("font_color", Color("e5d8be"))
	var hero_aspect := hero_portrait.texture.get_width() / float(hero_portrait.texture.get_height()) if hero_portrait.texture != null else 0.9
	var npc_aspect := npc_portrait.texture.get_width() / float(npc_portrait.texture.get_height()) if npc_portrait.texture != null else 0.9
	var overlap_aspect := minf(hero_aspect, npc_aspect) * 0.26
	var combined_aspect := hero_aspect + npc_aspect - overlap_aspect
	var stage_height := minf(minf(screen.y * 0.43, rect.size.x * 0.94 / combined_aspect), maxf(0, rect.position.y - 40 * scale) / 1.06)
	var stage_width := stage_height * combined_aspect
	_stage.position = Vector2(rect.get_center().x - stage_width * 0.5, rect.position.y - stage_height + 12 * scale)
	_stage.size = Vector2(stage_width, stage_height)
	var portraits: Array[TextureRect] = [hero_portrait, npc_portrait]
	for index: int in range(portraits.size()):
		var portrait_view := portraits[index]
		portrait_view.z_index = 1 if (index == 0) == _hero_speaking else 0
		var source := portrait_view.texture
		var aspect := source.get_width() / float(source.get_height()) if source != null else 0.9
		var portrait_height := stage_height
		portrait_view.size = Vector2(portrait_height * aspect, portrait_height)
		portrait_view.position = Vector2(0.0 if index == 0 else stage_height * (hero_aspect - overlap_aspect), stage_height - portrait_height)
		portrait_view.pivot_offset = Vector2(portrait_view.size.x * 0.5, portrait_height)
		# 旁白时两侧人物一同退暗，不让任何一方看起来在说话。
		var speaking := smoothstep(0.0, 1.0, _speaker_blend if index == 0 else 1.0 - _speaker_blend) * (1.0 - smoothstep(0.0, 1.0, _narration_blend))
		portrait_view.scale = Vector2.ONE * lerpf(0.95, 1.06, speaking)
		portrait_view.modulate = Color.WHITE * lerpf(0.55, 1.0, speaking)
		portrait_view.modulate.a = 1.0
	continue_button.add_theme_font_size_override("font_size", roundi(22 * scale))
	continue_button.position = Vector2(rect.end.x - 184 * scale, rect.end.y - 76 * scale)
	continue_button.size = Vector2(160 * scale, 54 * scale)
	continue_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var eased := smoothstep(0.0, 1.0, _presentation)
	_root.modulate.a = eased
	for item: Control in [text_panel, _speaker_tab, speaker_label, _content, continue_button, _leaf, _choice_scroll]:
		item.position.y += (1.0 - eased) * 30.0 * scale
	_stage.position.y += (1.0 - eased) * 58.0 * scale


func _layout_choices(width: float, scale: float) -> float:
	var height := 0.0
	for index: int in _choice_buttons.size():
		var button := _choice_buttons[index]
		button.position = Vector2(0, height)
		height += button.call("fit_caption", tr(String(_choice_specs[index].text_key)), width - 16 * scale, roundi(22 * scale), scale) + 8 * scale
	return height


func _sync_choices(info: Dictionary) -> void:
	_choice_specs = info.get("choices", []).duplicate(true)
	var signature := JSON.stringify([_choice_specs, info.get("locked_choice_id", ""), TranslationServer.get_locale()])
	if signature != _choice_signature:
		_choice_signature = signature
		for old: Button in _choice_buttons:
			_choice_root.remove_child(old)
			old.queue_free()
		_choice_buttons.clear()
		for choice: Dictionary in _choice_specs:
			var button: Button = preload("res://scripts/ui/dialogue_choice_button.gd").new()
			button.name = "Choice_" + String(choice.id)
			var locked := String(info.get("locked_choice_id", ""))
			button.set_meta("replay_locked", not locked.is_empty() and locked != choice.id)
			button.pressed.connect(_choose.bind(String(choice.id)))
			_choice_root.add_child(button)
			_choice_buttons.append(button)
		_choice_scroll.scroll_vertical = 0
	for button: Button in _choice_buttons:
		button.disabled = _menu_paused or bool(button.get_meta("replay_locked", false))
	_choice_scroll.visible = not _choice_specs.is_empty()


func _choose(choice_id: String) -> void:
	if _menu_paused or flow == null or not flow.has_method("choose"):
		return
	flow.call("choose", choice_id)

func _on_text_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		text_panel.accept_event()
		advance()

func _portrait(node_name: String) -> TextureRect:
	var result := TextureRect.new()
	result.name = node_name
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return result

func _close_portrait(source: Texture2D) -> Texture2D:
	if source == null:
		return null
	var cropped := AtlasTexture.new()
	cropped.atlas = source
	cropped.region = Rect2(Vector2.ZERO, Vector2(source.get_width(), source.get_height() * 0.43))
	cropped.filter_clip = true
	return cropped
