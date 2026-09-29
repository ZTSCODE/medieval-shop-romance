class_name MainMenu
extends CanvasLayer

signal continue_requested
signal new_journey_requested
signal load_requested
signal settings_requested
signal quit_requested

var buttons: Dictionary = {}
var panel: PanelContainer
var _root: Control
var _title: Label
var _status: Label
var _status_key := ""
var _status_error := false
var _can_continue := false
var _interactive := true
var _column: VBoxContainer
var _active_target := false
var _visibility_tween: Tween

class MenuPaper extends StyleBox:
	var texture: Texture2D
	var ink := Color.WHITE
	var compact_title := false
	func _draw(canvas: RID, rect: Rect2) -> void:
		if not compact_title:
			ImagePlacement.draw(canvas, texture, rect, &"contain", ink)
			return
		var source := texture as AtlasTexture
		var scale := minf(rect.size.x / 1436.0, rect.size.y / 570.0)
		var at := rect.position + (rect.size - Vector2(1436, 570) * scale) * 0.5
		for strip in [Vector2(0, 546), Vector2(726, 350), Vector2(1256, 540)]:
			var area := Rect2(source.region.position + Vector2(strip.x, 0), Vector2(strip.y, 570))
			RenderingServer.canvas_item_add_texture_rect_region(canvas, Rect2(at, area.size * scale), source.atlas.get_rid(), area, ink)
			at.x += strip.y * scale


func _paper(title: bool, color := Color.WHITE) -> StyleBox:
	var result := MenuPaper.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = GameArt.texture("res://assets/art/ui/forest_rebuild/menu-title-plaque.png" if title else "res://assets/art/ui/rebuild_20260923/system/button.png")
	atlas.region = Rect2(94,110,1796,570) if title else Rect2(35,97,2100,507)
	result.texture = atlas
	result.ink = color
	result.compact_title = title
	return result


func _init() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.name = "MainMenuRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = GameTheme.make_theme()
	var background := ColorRect.new()
	background.name = "MainMenuShade"
	background.color = Color(0.02, 0.025, 0.03, 0.12)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.name = "MainMenuPaper"
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.add_child(panel)
	var column := VBoxContainer.new()
	_column = column
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	column.minimum_size_changed.connect(_layout.call_deferred)
	_title = Label.new()
	_title.name = "MainMenuTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", Color("efe4c8"))
	_title.custom_minimum_size.y = 155.0
	_title.add_theme_stylebox_override("normal", _paper(true))
	column.add_child(_title)
	for id: String in ["continue", "new", "load", "settings", "quit"]:
		var button := preload("res://scripts/ui/main_menu_reference_button.gd").new()
		button.name = "MainMenu_" + id
		button.custom_minimum_size = Vector2(320.0, 65.0)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.add_theme_font_override("font",preload("res://scripts/ui/forest_ui_typography.gd").regular())
		button.add_theme_font_size_override("font_size",30)
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			button.add_theme_color_override(state,Color("e9ddc2"))
		button.add_theme_color_override("font_disabled_color",Color("b2a990"))
		column.add_child(button)
		buttons[id] = button
		if id == "load":
			button.visible = false
	buttons["continue"].pressed.connect(func() -> void: continue_requested.emit())
	buttons["new"].pressed.connect(func() -> void: new_journey_requested.emit())
	buttons["load"].pressed.connect(func() -> void: load_requested.emit())
	buttons["settings"].pressed.connect(func() -> void: settings_requested.emit())
	buttons["quit"].pressed.connect(func() -> void: quit_requested.emit())
	_status = Label.new()
	_status.name = "MainMenuStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.y = 36.0
	_status.add_theme_font_size_override("font_size", 15)
	column.add_child(_status)
	_root.resized.connect(_layout)
	UiScale.bind(_root, _layout)
	_update_text()
	_layout()
	visible = false
	_root.modulate.a = 0.0
	set_active(false)


func set_active(value: bool) -> void:
	if value == _active_target and is_node_ready():
		return
	_active_target = value
	if not is_node_ready():
		visible = value
		return
	if is_instance_valid(_visibility_tween):
		_visibility_tween.kill()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if value:
		visible = true
		_focus_default.call_deferred()
	_visibility_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_visibility_tween.tween_property(_root,"modulate:a",1.0 if value else 0.0,0.32)
	if not value:
		_visibility_tween.tween_callback(func(): visible = false)


func set_continue_available(value: bool) -> void:
	_can_continue = value
	if is_node_ready():
		_apply_enabled()


func set_interactive(value: bool) -> void:
	_interactive = value
	if is_node_ready():
		_apply_enabled()


func show_status(key: String, is_error: bool = false) -> void:
	_status_key = key
	_status_error = is_error
	if is_node_ready():
		_update_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_text()
		_layout.call_deferred()


func _update_text() -> void:
	_title.text = tr("FOREST_TABLE_TITLE")
	var keys := {"continue": "MAIN_MENU_CONTINUE", "new": "MENU_NEW_JOURNEY", "load": "MAIN_MENU_LOAD", "settings": "MENU_SETTINGS", "quit": "MAIN_MENU_QUIT"}
	for id: String in keys:
		buttons[id].text = tr(String(keys[id]))
	_apply_enabled()
	_status.text = tr(_status_key) if not _status_key.is_empty() else ""
	_status.add_theme_color_override("font_color", GameTheme.RED if _status_error else GameTheme.MUTED)


func _layout() -> void:
	if not is_instance_valid(panel):
		return
	var reference := UiScale.reference_size(_root)
	var scale := minf(reference.x / 1672.0, reference.y / 941.0)
	_title.custom_minimum_size.y = 206.0 * scale
	_title.add_theme_font_size_override("font_size",roundi(72*scale))
	_column.add_theme_constant_override("separation",roundi(16*scale))
	for button: Button in buttons.values():
		button.custom_minimum_size = Vector2(380,92) * scale
		button.add_theme_font_size_override("font_size",roundi(34*scale))
	panel.size = Vector2(480*scale,0)
	panel.position = Vector2(_root.size.x*0.085,_root.size.y*0.165).round()


func _focus_default() -> void:
	if visible and _interactive:
		buttons["continue" if _can_continue else "new"].grab_focus()


func _apply_enabled() -> void:
	for id: String in buttons:
		buttons[id].disabled = not _interactive or (id == "continue" and not _can_continue)
