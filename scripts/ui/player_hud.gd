class_name PlayerHud
extends Control

signal focus_hero_requested

var player_name := ""
var day := 1
var progress := 0.0
var day_label: Label
var name_label: Label
var day_progress: ProgressBar
var portrait: PortraitBadge
var name_paper: Panel
var focus_enabled := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = GameTheme.make_theme()
	portrait = preload("res://scripts/ui/ebb_portrait_badge.gd").new()
	portrait.name = "PlayerPortraitBadge"
	portrait.subject_id = "hero"
	portrait.position = Vector2(0, 25)
	portrait.size = Vector2(104, 132)
	add_child(portrait)
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	portrait.gui_input.connect(_on_portrait_input)
	name_paper = Panel.new()
	name_paper.name = "PlayerNamePaper"
	name_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_paper.position = Vector2.ZERO
	name_paper.size = Vector2(112,35)
	name_paper.add_theme_stylebox_override("panel",preload("res://scripts/ui/whole_paper_style.gd").make("res://assets/art/ui/independent_components_20260922/hud/portrait-name-tag-v1.png",Rect2()))
	add_child(name_paper)
	name_paper.visible = false
	name_label = Label.new()
	name_label.name = "PlayerName"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.position = Vector2.ZERO
	name_label.size = Vector2(104, 24)
	name_label.add_theme_color_override("font_color", Color("e3d6b8"))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_override("font", GameTheme.paper_font())
	name_label.add_theme_font_size_override("font_size", 16)
	add_child(name_label)
	portrait.get("press_feedback").changed.connect(func(amount: float) -> void:
		name_label.pivot_offset = portrait.size * 0.5 - name_label.position
		name_label.scale = Vector2.ONE * amount
	)
	day_label = Label.new()
	day_label.name = "DayCount"
	day_label.add_theme_font_override("font",preload("res://scripts/ui/forest_ui_typography.gd").regular())
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	day_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	day_label.position = Vector2(0, 91)
	day_label.size = Vector2(104, 22)
	day_label.add_theme_color_override("font_color", preload("res://scripts/ui/ui_paper_palette.gd").INK)
	day_label.add_theme_font_size_override("font_size", 14)
	add_child(day_label)
	day_progress = preload("res://scripts/ui/solar_day_axis.gd").new()
	day_progress.name = "DayProgress"
	day_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	day_progress.min_value = 0.0
	day_progress.max_value = 1.0
	day_progress.step = 0.0
	day_progress.show_percentage = false
	add_child(day_progress)
	refresh()


func set_identity(value: String) -> void:
	player_name = value
	if is_node_ready():
		refresh()


func set_day(value: int, fraction: float) -> void:
	day = maxi(value, 1)
	progress = clampf(fraction, 0.0, 1.0)
	if is_node_ready():
		refresh()


func refresh() -> void:
	name_label.text = player_name if not player_name.is_empty() else tr("PLAYER_DEFAULT_NAME")
	day_label.text = tr("SESSION_DAY_FORMAT") % day
	day_progress.value = progress


func _on_portrait_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		portrait.accept_event()
		portrait.get("press_feedback").set_pressed(event.pressed and focus_enabled and not get_tree().paused)
		if event.pressed and focus_enabled and not get_tree().paused:
			focus_hero_requested.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()
