class_name OpeningFilmView
extends Control

# 开场动画的全屏播放：黑底、保持画面比例的视频、按语言显示的字幕、右下角长按才生效的“跳过”、结尾浮现的游戏名。
# 只负责播放与显示；播完或跳过后发 finished，由 OpeningOverlay / OpeningFlow 决定接下来做什么。
# 字幕时间与文字键来自内容里的 opening.film.captions，文字走本地化表。

signal finished

const Rail = preload("res://scripts/ui/narrative_rail_style.gd")
const BACKDROP := Color("000000")
const CAPTION := Color("f2f2f2")
const FADE_SECONDS := 0.45
const SKIP_DELAY := 1.2
const SKIP_HOLD_SECONDS := 1.2   # 按住这么久才跳过，免得误触
const SKIP_RELEASE_RATE := 2.5   # 松手后进度退回的速度（相对按住时）
# 画面真正露出来（主菜单到牌桌的转场结束）并稳定这么久之后才开始播放，
# 否则开头会被转场挡住，转场时的卡顿还会让解码器丢帧、画面花掉。
const START_HOLD := 0.6

var _backdrop: ColorRect
var _player: VideoStreamPlayer
var _caption: Label
var _skip: Button
var _skip_bar: ColorRect
var _skip_track: ColorRect
var _skip_progress := 0.0
var _title: Label
var _title_rule: ColorRect
var _title_start := -1.0
var _title_fade := 1.6
var _captions: Array = []
var _video_path := ""
var _aspect := 16.0 / 9.0
var _menu_paused := false
var _ending := false
var _shown_seconds := 0.0
var _started := false
var _hold := 0.0
static var _film_font: SystemFont
var _lead_in := 0.0  # 视频开头的黑场秒数（opening.film.lead_in）；字幕时间不含这段


func _init() -> void:
	name = "OpeningFilmView"
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = ColorRect.new()
	_backdrop.color = BACKDROP
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player = VideoStreamPlayer.new()
	_player.name = "OpeningFilmPlayer"
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.finished.connect(_on_video_finished)
	add_child(_player)
	_caption = Rail.label("OpeningFilmCaption", 30, CAPTION)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_override("font", film_font())
	_caption.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.04, 0.95))
	add_child(_caption)
	_skip = Button.new()
	_skip.name = "OpeningFilmSkip"
	Rail.setup_button(_skip)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		_skip.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_skip.add_theme_font_override("font", film_font())
	_skip.add_theme_color_override("font_color", Color(0.95, 0.91, 0.82, 0.92))
	_skip.add_theme_color_override("font_hover_color", Color("fff0d1"))
	_skip.add_theme_color_override("font_pressed_color", Color("fff0d1"))
	_skip.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.04, 0.9))
	_skip.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	add_child(_skip)
	_skip_track = ColorRect.new()
	_skip_track.color = Color(0.95, 0.91, 0.82, 0.22)
	_skip_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skip_track)
	_skip_bar = ColorRect.new()
	_skip_bar.name = "OpeningFilmSkipProgress"
	_skip_bar.color = Color("fff0d1")
	_skip_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skip_bar)
	_title = Rail.label("OpeningFilmTitle", 96, Color("efe4c8"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_override("font", film_font())
	_title.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02, 0.9))
	_title.modulate.a = 0.0
	add_child(_title)
	_title_rule = ColorRect.new()
	_title_rule.color = Color("efe4c8")
	_title_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_rule.modulate.a = 0.0
	add_child(_title_rule)
	resized.connect(_layout)
	hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_text()


# 字幕与片名用的字体：拉丁字母用 Georgia，中文落到宋体（界面通用字体把宋体排在前面，英文会用宋体自带的等宽拉丁字形）。
static func film_font() -> SystemFont:
	if _film_font == null:
		_film_font = SystemFont.new()
		_film_font.font_names = PackedStringArray(["Georgia"])
		_film_font.fallbacks = [preload("res://scripts/ui/forest_ui_typography.gd").regular()]
		_film_font.font_weight = 400
		_film_font.oversampling = 4.0
	return _film_font


# 内容里是否配置了可播放的开场动画。
static func available(definition: Dictionary) -> bool:
	var film: Variant = definition.get("film", {})
	return film is Dictionary and film.get("video") is String and ResourceLoader.exists(String(film.video))


func show_film(definition: Dictionary) -> void:
	var film: Dictionary = definition.get("film", {})
	var path := String(film.get("video", ""))
	if is_showing() and path == _video_path:
		return
	_video_path = path
	_captions = film.get("captions", []) if film.get("captions", []) is Array else []
	_skip.set_meta("text_key", String(film.get("skip_key", "OPENING_FILM_SKIP")))
	_lead_in = float(film.get("lead_in", 0.0))
	# 结尾浮现的游戏名：opening.film.title = {start, fade, key}；没配就不显示。
	var title: Variant = film.get("title", {})
	_title_start = float(title.get("start", -1.0)) if title is Dictionary else -1.0
	_title_fade = maxf(float(title.get("fade", 1.6)), 0.05) if title is Dictionary else 1.6
	_title.set_meta("text_key", String(title.get("key", "")) if title is Dictionary else "")
	_title.modulate.a = 0.0
	_title_rule.modulate.a = 0.0
	_skip_progress = 0.0
	_ending = false
	_started = false
	_hold = 0.0
	_shown_seconds = 0.0
	modulate.a = 1.0
	show()
	_player.stream = load(path)
	var texture := _player.get_video_texture()
	if texture != null and texture.get_height() > 0:
		_aspect = float(texture.get_width()) / float(texture.get_height())
	_update_text()
	_layout()
	_skip.visible = false


func hide_view() -> void:
	if not visible:
		return
	_player.stop()
	_player.stream = null
	_video_path = ""
	_caption.text = ""
	hide()


func is_showing() -> bool:
	return visible and not _video_path.is_empty()


func set_menu_paused(value: bool) -> void:
	_menu_paused = value
	if is_node_ready():
		_player.paused = value
		_skip.disabled = value


# 跳过：淡出后发 finished。播完走同一条路。界面上要按住“跳过”（或空格、回车）满 SKIP_HOLD_SECONDS 才会调用。
func skip() -> void:
	if not is_showing() or _ending or _menu_paused:
		return
	_ending = true


# 影片本身的时间（不含开头黑场）。
func playback_seconds() -> float:
	return _player.stream_position - _lead_in if is_node_ready() else 0.0


func _process(delta: float) -> void:
	if not is_showing():
		return
	if _ending:
		modulate.a = maxf(0.0, modulate.a - delta / FADE_SECONDS)
		_player.volume_db = linear_to_db(maxf(modulate.a, 0.001))
		if modulate.a <= 0.0:
			_player.volume_db = 0.0
			hide_view()
			finished.emit()
		return
	if _menu_paused:
		return
	if not _started:
		_hold = _hold + delta if is_visible_in_tree() else 0.0
		if _hold < START_HOLD:
			return
		_started = true
		_player.play()
	_shown_seconds += delta
	var texture := _player.get_video_texture()
	if texture != null and texture.get_height() > 0 and not is_equal_approx(_aspect, float(texture.get_width()) / float(texture.get_height())):
		_aspect = float(texture.get_width()) / float(texture.get_height())
		_layout()
	_skip.visible = _shown_seconds >= SKIP_DELAY
	_caption.text = _caption_at(playback_seconds())
	_update_skip_hold(delta)
	var title_alpha := clampf((playback_seconds() - _title_start) / _title_fade, 0.0, 1.0) if _title_start >= 0.0 else 0.0
	_title.modulate.a = title_alpha
	_title_rule.modulate.a = title_alpha * 0.7


# 是否正按着跳过：鼠标按在按钮上，或按着空格/回车。
func skip_held() -> bool:
	return _skip.visible and (_skip.button_pressed or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER))


func _update_skip_hold(delta: float) -> void:
	if skip_held():
		_skip_progress = minf(1.0, _skip_progress + delta / SKIP_HOLD_SECONDS)
	else:
		_skip_progress = maxf(0.0, _skip_progress - delta / SKIP_HOLD_SECONDS * SKIP_RELEASE_RATE)
	_skip_track.visible = _skip.visible
	_skip_bar.visible = _skip.visible and _skip_progress > 0.0
	_skip_bar.size.x = _skip_track.size.x * _skip_progress
	if _skip_progress >= 1.0:
		skip()


func _caption_at(seconds: float) -> String:
	for entry: Variant in _captions:
		if entry is Dictionary and seconds >= float(entry.get("start", 0.0)) and seconds < float(entry.get("end", 0.0)):
			return tr(String(entry.get("key", "")))
	return ""


func _on_video_finished() -> void:
	if is_showing() and not _ending:
		_ending = true


func _update_text() -> void:
	_skip.text = tr(String(_skip.get_meta("text_key", "OPENING_FILM_SKIP")))
	var title_key := String(_title.get_meta("text_key", ""))
	_title.text = tr(title_key) if not title_key.is_empty() else ""


func _layout() -> void:
	if not is_instance_valid(_player) or size.x <= 0.0 or size.y <= 0.0:
		return
	var picture := Vector2(size.x, size.x / _aspect)
	if picture.y > size.y:
		picture = Vector2(size.y * _aspect, size.y)
	var origin := (size - picture) * 0.5
	_player.position = origin
	_player.size = picture
	var scale := picture.y / 960.0
	_caption.add_theme_font_size_override("font_size", roundi(34 * scale))
	_caption.add_theme_constant_override("outline_size", roundi(8 * scale))
	_caption.position = origin + Vector2(picture.x * 0.08, picture.y * 0.72)
	_caption.size = Vector2(picture.x * 0.84, picture.y * 0.22)
	_skip.add_theme_font_size_override("font_size", roundi(24 * scale))
	_skip.add_theme_constant_override("outline_size", roundi(6 * scale))
	_skip.size = Vector2(220, 52) * scale
	_skip.position = origin + picture - _skip.size - Vector2(36, 34) * scale
	_skip_track.size = Vector2(_skip.size.x - 40 * scale, maxf(2.0, 3 * scale))
	_skip_track.position = _skip.position + Vector2(20 * scale, _skip.size.y - 2 * scale)
	_skip_bar.position = _skip_track.position
	_skip_bar.size = Vector2(_skip_track.size.x * _skip_progress, _skip_track.size.y)
	_title.add_theme_font_size_override("font_size", roundi(108 * scale))
	_title.add_theme_constant_override("outline_size", roundi(10 * scale))
	_title.position = origin + Vector2(0, picture.y * 0.36)
	_title.size = Vector2(picture.x, picture.y * 0.2)
	_title_rule.size = Vector2(picture.x * 0.16, maxf(1.0, 2 * scale))
	_title_rule.position = origin + Vector2((picture.x - _title_rule.size.x) * 0.5, picture.y * 0.585)
