class_name ChronicleView
extends Control

# 开场序幕的全屏呈现：暗场、插画缓慢推近，文字在插画下方左对齐淡入，翻页交叉淡化。
# 只负责显示；翻页仍由 OpeningOverlay / OpeningFlow 决定。点击任意处请求继续。

signal advance_requested

const Rail = preload("res://scripts/ui/narrative_rail_style.gd")
const TextLayout = preload("res://scripts/ui/dialogue_text_layout.gd")
const BACKDROP := Color("07090b")
const TEXT := Color("e8dcc4")
const FADE_SECONDS := 0.7
const TEXT_DELAY := 0.35
const TEXT_SECONDS := 1.1
const DRIFT_SECONDS := 14.0
const DRIFT_SCALE := 0.06

var _backdrop: ColorRect
var _art_clip: Control
var _art_front: TextureRect
var _art_back: TextureRect
var _text: Label
var _hint: Label
var _page_key := ""
var _art_path := ""
var _page_time := 0.0
var _art_fade := 1.0
var _visibility := 0.0
var _visibility_target := 0.0
var _menu_paused := false


func _init() -> void:
	name = "ChronicleView"
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = ColorRect.new()
	_backdrop.color = BACKDROP
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art_clip = Control.new()
	_art_clip.clip_contents = true
	_art_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art_clip)
	_art_back = _art_rect("ChronicleArtPrevious")
	_art_front = _art_rect("ChronicleArt")
	_art_clip.add_child(_art_back)
	_art_clip.add_child(_art_front)
	_text = Rail.label("ChronicleText", 26, TEXT)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_text)
	_hint = Rail.label("ChronicleHint", 15, Rail.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_hint)
	for label: Label in [_text, _hint]:
		label.add_theme_font_override("font", preload("res://scripts/ui/forest_ui_typography.gd").regular())
	gui_input.connect(_on_input)
	resized.connect(_layout)
	modulate.a = 0.0
	hide()


func show_page(page_key: String, art_path: String) -> void:
	_visibility_target = 1.0
	show()
	_text.text = tr(page_key)
	_hint.text = tr("OPENING_CONTINUE")
	if page_key != _page_key:
		_page_key = page_key
		_page_time = 0.0
	if art_path != _art_path:
		_art_back.texture = _art_front.texture
		_art_back.scale = _art_front.scale
		_art_front.texture = GameArt.texture(art_path) if not art_path.is_empty() else null
		_art_path = art_path
		_art_fade = 0.0 if _art_back.texture != null else 1.0
	_layout()
	_apply_motion()


func hide_view() -> void:
	_visibility_target = 0.0


func is_showing() -> bool:
	return _visibility_target > 0.0


func set_menu_paused(value: bool) -> void:
	_menu_paused = value


func _process(delta: float) -> void:
	if _menu_paused:
		return
	_visibility = move_toward(_visibility, _visibility_target, delta / FADE_SECONDS)
	modulate.a = smoothstep(0.0, 1.0, _visibility)
	if _visibility <= 0.0 and _visibility_target <= 0.0:
		if visible:
			hide()
			_page_key = ""
			_art_path = ""
			_art_front.texture = null
			_art_back.texture = null
		return
	_page_time += delta
	_art_fade = move_toward(_art_fade, 1.0, delta / FADE_SECONDS)
	_apply_motion()


func _apply_motion() -> void:
	var drift := clampf(_page_time / DRIFT_SECONDS, 0.0, 1.0)
	_art_front.scale = Vector2.ONE * (1.0 + DRIFT_SCALE * smoothstep(0.0, 1.0, drift))
	_art_front.modulate.a = smoothstep(0.0, 1.0, _art_fade)
	_art_back.modulate.a = 1.0 - _art_front.modulate.a
	_text.modulate.a = smoothstep(0.0, 1.0, clampf((_page_time - TEXT_DELAY) / TEXT_SECONDS, 0.0, 1.0))
	_hint.modulate.a = 0.75 * _text.modulate.a


func _layout() -> void:
	if not is_instance_valid(_text):
		return
	var screen := UiScale.reference_size(self)
	var scale := minf(screen.y / 941.0, screen.x / 1250.0)
	var art_width := minf(size.x * 0.72, size.y * 0.5 * 16.0 / 9.0)
	var art_size := Vector2(art_width, art_width * 9.0 / 16.0)
	var text_height := TextLayout.measure(_text, art_size.x, roundi(25 * scale))
	# 插画与文字作为一组垂直居中；文字与插画左边对齐，文字区留固定最小高度，翻页时插画不跳动。
	var text_reserve := maxf(text_height, 150 * scale)
	var gap := 28 * scale
	var top := maxf((size.y - art_size.y - gap - text_reserve) * 0.5, 16 * scale)
	_art_clip.position = Vector2((size.x - art_size.x) * 0.5, top)
	_art_clip.size = art_size
	for art: TextureRect in [_art_front, _art_back]:
		art.position = Vector2.ZERO
		art.size = art_size
		art.pivot_offset = art_size * 0.5
	_text.position = Vector2(_art_clip.position.x, top + art_size.y + gap)
	_text.size = Vector2(art_size.x, text_reserve)
	_hint.add_theme_font_size_override("font_size", roundi(16 * scale))
	_hint.position = Vector2(size.x - 260 * scale, size.y - 52 * scale)
	_hint.size = Vector2(220 * scale, 30 * scale)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _menu_paused:
		accept_event()
		advance_requested.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _page_key.is_empty():
		_text.text = tr(_page_key)
		_hint.text = tr("OPENING_CONTINUE")


func _art_rect(node_name: String) -> TextureRect:
	var result := TextureRect.new()
	result.name = node_name
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	return result
