class_name JournalPanel
extends Control

const Paper = preload("res://scripts/ui/settings_control_paper.gd")
const BookSkin = preload("res://scripts/ui/settings_book_skin.gd")
const INK := Color("e3d6b8")
var progress: PlayerProgress
var journal_kind := "recipes"
var entry_controls: Dictionary = {}
var selected_id := ""
var _list: VBoxContainer
var _scroll: ScrollContainer
var _details: Control
var _discovered: Label

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_layout)
	refresh()

func configure(value: PlayerProgress, kind: String) -> void:
	if progress != null and progress.changed.is_connected(refresh):
		progress.changed.disconnect(refresh)
	progress = value
	journal_kind = kind
	if progress != null:
		progress.changed.connect(refresh)
	if is_node_ready():
		refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh.call_deferred()

func refresh() -> void:
	if not is_node_ready():
		return
	var probe_started := HitchProbe.stamp()
	for entry: Dictionary in entry_controls.values():
		if entry.has("motion") and is_instance_valid(entry.motion):
			entry.motion.kill()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	entry_controls.clear()
	var ids: Array[String] = []
	if progress != null:
		var source: Variant = progress.discovered_recipes if journal_kind == "recipes" else progress.npcs.keys()
		for id: String in source:
			var definition := ContentCatalog.recipe_definition(id) if journal_kind == "recipes" else ContentCatalog.npc_definition(id)
			if not definition.is_empty() and (journal_kind != "recipes" or ContentCatalog.recipe_is_repeatable(id)):
				ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool: return _entry_name(a).naturalnocasecmp_to(_entry_name(b)) < 0)
	_scroll = ScrollContainer.new()
	_scroll.name = "DiscoveredList"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 9)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_discovered = _text(tr("JOURNAL_DISCOVERED"), 21)
	_discovered.autowrap_mode = TextServer.AUTOWRAP_OFF
	_discovered.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_discovered)
	_discovered.visible = journal_kind == "recipes"
	BookSkin._style_popup_scrollbars(_scroll)
	_details = Control.new()
	_details.name = "JournalDetail"
	add_child(_details)
	if ids.is_empty():
		var empty := _text(tr("JOURNAL_RECIPES_EMPTY" if journal_kind == "recipes" else "JOURNAL_NPCS_EMPTY"), 23)
		empty.name = "JournalEmpty"
		empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_details.add_child(empty)
	else:
		if selected_id not in ids:
			selected_id = ids[0]
		for id: String in ids:
			_build_entry(id)
		_select(selected_id)
	_layout()
	HitchProbe.record("journal_refresh", probe_started)

func _layout() -> void:
	if not is_instance_valid(_scroll):
		return
	var left_width := minf(210.0, size.x * 0.26)
	_discovered.position = Vector2(8, 0)
	_discovered.size = Vector2(left_width - 8, 32)
	_scroll.position = Vector2(0, 42 if journal_kind == "recipes" else 0)
	_scroll.size = Vector2(left_width, maxf(0, size.y - _scroll.position.y))
	_details.position = Vector2(left_width + 30, 0)
	_details.size = Vector2(maxf(0, size.x - left_width - 30), size.y)
	queue_redraw()

func _draw() -> void:
	var x := minf(210.0, size.x * 0.26) + 15
	draw_line(Vector2(x, 8), Vector2(x, size.y - 8), Color(0.69, 0.66, 0.57, 0.23), 1.0, true)

func _build_entry(id: String) -> void:
	var button := Button.new()
	button.name = "Entry_" + id.replace(".", "_")
	button.custom_minimum_size.y = 76
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(_select.bind(id))
	var paper := Paper.make()
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, paper)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_list.add_child(button)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 11
	row.offset_right = -11
	row.offset_top = 8
	row.offset_bottom = -8
	row.add_theme_constant_override("separation", 9)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var marker := ColorRect.new()
	marker.name = "SelectedMarker"
	marker.color = INK
	marker.position = Vector2(4, 24)
	marker.size = Vector2(2, 28)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(marker)
	row.add_child(_image(_entry_texture(id), Vector2(53, 57)))
	var name_label := _text(_entry_name(id), 21)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)
	var feedback := UiPressFeedback.new()
	feedback.changed.connect(func(amount: float) -> void:
		paper.press_amount = amount
		row.pivot_offset = row.size * 0.5
		row.scale = Vector2.ONE * amount
		button.queue_redraw()
	)
	button.add_child(feedback)
	var detail := Control.new()
	detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_details.add_child(detail)
	entry_controls[id] = {"root": button, "detail": detail, "title": name_label, "paper": paper, "marker": marker}
	for event: String in ["mouse_entered", "mouse_exited", "focus_entered", "focus_exited"]:
		button.connect(event, _entry_highlight.bind(id))
	if journal_kind == "recipes":
		_recipe_detail(id, detail)
	else:
		_npc_detail(id, detail)

func _entry_highlight(id: String) -> void:
	if not entry_controls.has(id):
		return
	var entry: Dictionary = entry_controls[id]
	var button: Button = entry.root
	var active := button.has_focus() or button.get_global_rect().has_point(button.get_global_mouse_position())
	if entry.has("motion") and is_instance_valid(entry.motion):
		entry.motion.kill()
	var motion := button.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	entry.motion = motion
	var target := Paper.TAB_ACTIVE if selected_id == id else (Paper.HOVER_TINT if active else Paper.BASE_TINT)
	motion.tween_property(entry.paper, "tint", target, 0.14)
	motion.parallel().tween_method(func(_value: float): button.queue_redraw(), 0.0, 1.0, 0.14)
	entry.title.modulate = Color.WHITE
	entry.marker.visible = selected_id == id

func _select(id: String) -> void:
	selected_id = id
	for key: String in entry_controls:
		var entry: Dictionary = entry_controls[key]
		entry.detail.visible = key == id
		_entry_highlight(key)
	if entry_controls.has(id):
		_scroll.ensure_control_visible.call_deferred(entry_controls[id].root)

func _recipe_detail(id: String, column: Control) -> void:
	var definition := ContentCatalog.recipe_definition(id)
	var heading := _text(_entry_name(id), 29)
	heading.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	heading.offset_bottom = 46
	column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.name = "RecipeScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 56
	column.add_child(scroll)
	BookSkin._style_popup_scrollbars(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	var parts: Array = definition.get("inputs", []).duplicate(true)
	for part: Dictionary in definition.get("reusable", []):
		var retained := part.duplicate()
		retained["reusable"] = true
		parts.append(retained)
	var outputs: Array = definition.get("outputs", [])
	var total := parts.size() + outputs.size()
	if total <= 4:
		var graph := HBoxContainer.new()
		graph.name = "RecipeHorizontalGraph"
		graph.alignment = BoxContainer.ALIGNMENT_CENTER
		graph.add_theme_constant_override("separation", 10)
		content.add_child(graph)
		var width := minf(160.0, (540.0 - 40.0 - 10.0 * maxf(total - 1, 0)) / maxf(total, 1))
		for part: Dictionary in parts:
			graph.add_child(_mini_card(part, bool(part.get("reusable", false)), false, width))
		if not outputs.is_empty():
			var arrow := preload("res://scripts/ui/journal_arrow.gd").new()
			arrow.custom_minimum_size = Vector2(30, 60)
			arrow.size_flags_vertical = Control.SIZE_EXPAND_FILL
			graph.add_child(arrow)
			for part: Dictionary in outputs:
				graph.add_child(_mini_card(part, false, true, width))
	else:
		var ingredients := HFlowContainer.new()
		ingredients.name = "RecipeIngredients"
		ingredients.add_theme_constant_override("h_separation", 14)
		ingredients.add_theme_constant_override("v_separation", 12)
		content.add_child(ingredients)
		for part: Dictionary in parts:
			ingredients.add_child(_mini_card(part, bool(part.get("reusable", false)), false, 132))
		content.add_child(_rule())
		var results := HFlowContainer.new()
		results.name = "RecipeResults"
		results.add_theme_constant_override("h_separation", 14)
		content.add_child(results)
		for part: Dictionary in outputs:
			results.add_child(_mini_card(part, false, true, 132))

func _mini_card(part: Dictionary, _reusable: bool, output: bool, width: float) -> Control:
	var definition := ContentCatalog.card_definition(str(part.get("card_id", "")))
	var card := preload("res://scripts/ui/journal_card_preview.gd").new()
	card.name = "ResultCard" if output else "IngredientCard"
	var count := int(part.get("count", 1))
	var card_name := tr(str(definition.get("name_key", "")))
	card.configure(str(part.get("card_id", "")), width, output, card_name if count == 1 else tr("RECIPE_COMPONENT_FORMAT") % [card_name, count])
	return card

func _npc_detail(id: String, column: Control) -> void:
	var definition := ContentCatalog.npc_definition(id)
	var record: Dictionary = progress.npcs.get(id, {})
	var heading := _text(_entry_name(id), 29)
	heading.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	heading.offset_bottom = 46
	column.add_child(heading)
	var large_portrait := _image(GameArt.portrait(id), Vector2.ZERO)
	large_portrait.name = "FullRelationshipPortrait"
	large_portrait.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	large_portrait.anchor_right = 0.39
	large_portrait.offset_top = 54
	large_portrait.offset_bottom = -4
	column.add_child(large_portrait)
	var story_scroll := ScrollContainer.new()
	story_scroll.name = "EncounterStoryScroll"
	story_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	story_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_scroll.anchor_left = 0.39
	story_scroll.offset_left = 22
	story_scroll.offset_top = 56
	column.add_child(story_scroll)
	BookSkin._style_popup_scrollbars(story_scroll)
	var story := VBoxContainer.new()
	story.name = "EncounterStory"
	story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story.add_theme_constant_override("separation", 12)
	story_scroll.add_child(story)
	story.add_child(_text(tr("JOURNAL_MEETING_HEADING"), 23))
	story.add_child(_rule())
	var encounter := ContentCatalog.card_definition(String(definition.get("encounter_card_id", "")))
	var encounter_name_key := String(definition.get("encounter_name_key", encounter.get("name_key", "")))
	var encounter_art := GameArt.texture(String(encounter.get("art_path", "")))
	if encounter_art != null:
		var landscape := _image(encounter_art, Vector2(0, 116))
		landscape.name = "EncounterLocationImage"
		landscape.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		landscape.clip_contents = true
		story.add_child(landscape)
	if not encounter_name_key.is_empty():
		story.add_child(_text(tr(encounter_name_key), 20))
	story.add_child(_rule())
	story.add_child(_text(tr(str(definition.get("description_key", ""))),22))
	var affection := clampi(int(record.get("affection", 0)), 0, ContentCatalog.AFFECTION_MAX)
	var relationship: Dictionary = progress.chapter_relationships.get(id, {})
	story.add_child(_rule())
	var stage_label := _text(tr("JOURNAL_REL_STAGE_FORMAT") % tr(_relationship_stage_key(relationship)), 20)
	stage_label.name = "RelationshipStage"
	story.add_child(stage_label)
	if int(relationship.get("story_total", 0)) > 0:
		var story_label := _text(tr("JOURNAL_REL_STORY_PROGRESS") % [int(relationship.get("story_seen", 0)), int(relationship.story_total)], 18)
		story_label.name = "RelationshipStoryProgress"
		story.add_child(story_label)
	story.add_child(_text(tr("NPC_AFFECTION_FORMAT") % [affection, ContentCatalog.AFFECTION_MAX], 20))
	var bar := ProgressBar.new()
	bar.name = "RelationshipAffectionBar"
	bar.max_value = ContentCatalog.AFFECTION_MAX
	bar.value = affection
	bar.custom_minimum_size.y = 12
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", BookSkin.make(false, true))
	bar.add_theme_stylebox_override("fill", BookSkin.make(true, true))
	story.add_child(bar)
	entry_controls[id]["affection_bar"] = bar

func _relationship_stage_key(relationship: Dictionary) -> String:
	var signals: Dictionary = relationship.get("signals", {})
	if str(signals.get("private_time", "")) in ["shared_personal", "shared_friendship"]:
		return "JOURNAL_REL_STAGE_PRIVATE"
	if signals.get("regular_contact") == "ready":
		return "JOURNAL_REL_STAGE_CONTACT"
	if signals.get("meeting_consent") == "agreed":
		return "JOURNAL_REL_STAGE_AGREED"
	return "JOURNAL_REL_STAGE_MET"

func _entry_texture(id: String) -> Texture2D:
	if journal_kind != "recipes":
		return GameArt.card_face(id)
	var recipe := ContentCatalog.recipe_definition(id)
	for key: String in ["outputs", "inputs", "reusable"]:
		var parts: Array = recipe.get(key, [])
		if not parts.is_empty():
			return _component_art(ContentCatalog.card_definition(str(parts[0].card_id)))
	return null

func _component_art(definition: Dictionary) -> Texture2D:
	return GameArt.texture(str(definition.get("art_path", "")))

func _entry_name(id: String) -> String:
	var definition := ContentCatalog.recipe_definition(id) if journal_kind == "recipes" else ContentCatalog.npc_definition(id)
	return tr(str(definition.get("name_key", "")))

func _image(texture: Texture2D, minimum: Vector2) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.custom_minimum_size = minimum
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _rule() -> HSeparator:
	var rule := HSeparator.new()
	var style := StyleBoxLine.new()
	style.color = Color(0.69, 0.66, 0.57, 0.28)
	rule.add_theme_stylebox_override("separator", style)
	return rule

func _text(value: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	return label
