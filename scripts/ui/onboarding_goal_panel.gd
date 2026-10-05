class_name OnboardingGoalPanel
extends CanvasLayer

# 右上新手目标栏：只读 OnboardingGoals，按顺序补播勾选、阶段完成与离场动画。
# 尺寸以 1672×941 参考像素设计，与右侧 HUD 列同一比例缩放，右对齐坐落在时间轴上方空白处；空间不足时整体缩小。

const Paper = preload("res://scripts/ui/settings_control_paper.gd")
const Palette = preload("res://scripts/ui/ui_paper_palette.gd")
const ColumnLayout = preload("res://scripts/ui/hud_column_layout.gd")

# HUD 列在常见分辨率下按 0.75 缩放；目标栏文字需要更大的阅读尺寸。
const DESIGN_SCALE := 1.3
const WIDTH := 300.0
const PAD_X := 22.0
const ROWS_TOP := 74.0
const ROW_GAP := 10.0
const BOX := 18.0
const TEXT_X := PAD_X + BOX + 12.0
const BOTTOM_PAD := 16.0
const AXIS_GAP := 12.0
const TOP_MARGIN := 10.0
const APPEAR_DELAY := 0.9
const RESHOW_DELAY := 0.2
const CAPTION_SIZE := 14
const TITLE_SIZE := 21
const ROW_SIZE := 16
const LINE_SPACING := 3.0
const GOLD := Color("e6c27c")
const GOLD_DEEP := Color("b8894a")
const GLOW := Color("fff0c4")
const WREATH_RADIUS := 21.0
const WREATH_LEAVES := 5
# 角度以正下方为起点，沿左侧向上展开；右侧镜像。
const WREATH_START := PI * 0.62
const WREATH_END := PI * 1.38

var goals: OnboardingGoals
var displayed_stage := -1
var rows: Array[Dictionary] = []
var panel: Control
var _available := false
var _available_time := 0.0
var _shown := false
var _left := false
var _busy := false
var _collapsed := false
var _collapse_t := 0.0
var _height := 200.0
var _divider_t := 0.0
var _header_t := 0.0
var _shine_t := -1.0
var _seal_t := 0.0
var _seal_key := "ONBOARD_STAGE_DONE"
var _title_alpha := 1.0
var _progress_pop := 0.0
var _clock := 0.0
var _sparks: Array[Dictionary] = []
var _visibility: Tween
var _layout_scale := 1.0
var _generation := 0
var _full_height := 200.0
var _slide := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 19
	name = "OnboardingGoalLayer"


func _ready() -> void:
	panel = Control.new()
	panel.name = "OnboardingGoalPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	panel.modulate.a = 0.0
	panel.draw.connect(_draw_panel)
	panel.gui_input.connect(_on_panel_input)
	add_child(panel)
	get_viewport().size_changed.connect(_layout)
	UiScale.bind(panel, _layout)
	_layout()


func configure(model: OnboardingGoals) -> void:
	goals = model
	goals.changed.connect(_on_goals_changed)


# 由场景控制器按游戏上下文调用；目标栏只在桌面可操作时现身。
# 读档或新旅程后调用：中止进行中的动画，按新进度重新登场；已完成的目标直接显示为勾选。
func resync() -> void:
	_generation += 1
	_busy = false
	_shown = false
	_left = false
	_available_time = 0.0
	displayed_stage = -1
	rows.clear()
	_sparks.clear()
	_seal_t = 0.0
	_title_alpha = 1.0
	_collapsed = false
	_collapse_t = 0.0
	if is_instance_valid(_visibility):
		_visibility.kill()
	if is_instance_valid(panel):
		panel.hide()
		panel.modulate.a = 0.0


func set_available(value: bool) -> void:
	if _available == value:
		return
	_available = value
	_available_time = 0.0
	if not value:
		_set_shown(false)


func is_shown() -> bool:
	return _shown


func blocks_pointer(point: Vector2) -> bool:
	return _shown and panel.visible and panel.get_global_rect().has_point(point)


func _process(delta: float) -> void:
	if goals == null:
		return
	# 首次登场稍作停顿，避免与镜头/对白切换抢注意力；之后回到桌面时快速复现。
	if _available and not _shown and not _left and (displayed_stage >= 0 or not goals.is_finished()):
		_available_time += delta
		if _available_time >= (APPEAR_DELAY if displayed_stage < 0 else RESHOW_DELAY):
			_set_shown(true)
	if not panel.visible:
		return
	_clock += delta
	for spark: Dictionary in _sparks:
		spark.life += delta
		spark.vel *= pow(0.12, delta)
		spark.vel.y += 60.0 * delta
		spark.pos += spark.vel * delta
		spark.rot += spark.spin * delta
	_sparks.assign(_sparks.filter(func(spark: Dictionary) -> bool: return spark.life < spark.max))
	_relayout_height()
	panel.queue_redraw()


func _set_shown(value: bool) -> void:
	if _shown == value:
		return
	_shown = value
	if is_instance_valid(_visibility):
		_visibility.kill()
	if value:
		panel.show()
		if displayed_stage < 0:
			_play_pending()
			return
		_visibility = _tween()
		_visibility.tween_property(panel, "modulate:a", 1.0, 0.22)
		_play_pending()
	else:
		_visibility = _tween()
		_visibility.tween_property(panel, "modulate:a", 0.0, 0.16)
		_visibility.tween_callback(panel.hide)


func _on_goals_changed() -> void:
	if _shown:
		_play_pending()


# 动画串行补播：模型可能一次跨多个目标甚至阶段，界面逐步追上。
func _play_pending() -> void:
	if _busy or goals == null:
		return
	_busy = true
	var generation := _generation
	while _shown and is_inside_tree() and generation == _generation:
		if displayed_stage < 0:
			if goals.is_finished():
				break
			_load_stage(goals.stage_index, true)
			await _appear()
			continue
		var row := _next_unshown_completion()
		if not row.is_empty():
			await _animate_check(row)
			continue
		if _all_rows_done() and displayed_stage < goals.stage_index:
			await _celebrate_stage()
			if generation != _generation:
				break
			if displayed_stage + 1 >= goals.stages.size():
				await _leave()
				break
			await _swap_stage(displayed_stage + 1)
			continue
		break
	if generation == _generation:
		_busy = false


func _load_stage(index: int, settled: bool = false) -> void:
	displayed_stage = index
	_seal_t = 0.0
	_title_alpha = 1.0
	rows.clear()
	for goal: Dictionary in goals.stages[index].goals:
		rows.append({"id": goal.id, "key": goal.text_key, "appear": 0.0, "check": 0.0, "strike": 0.0,
			"fade": 0.0, "pop": 0.0, "flash": 0.0, "done_shown": false, "paragraph": TextParagraph.new()})
		if settled and goals.is_goal_complete(goal.id):
			var row: Dictionary = rows[rows.size() - 1]
			row.done_shown = true
			row.check = 1.0
			row.strike = 1.0
			row.fade = 1.0
	_shape_rows()


func _appear() -> void:
	panel.modulate.a = 0.0
	_slide = -34.0
	_divider_t = 0.0
	_header_t = 0.0
	var motion := _tween().set_parallel(true)
	motion.tween_property(panel, "modulate:a", 1.0, 0.32)
	motion.tween_property(self, "_slide", 0.0, 0.62).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "_header_t", 1.0, 0.45).set_delay(0.12)
	motion.tween_property(self, "_divider_t", 1.0, 0.5).set_delay(0.24).set_trans(Tween.TRANS_QUART)
	motion.tween_property(self, "_shine_t", 1.0, 0.9).from(0.0).set_delay(0.3)
	for index: int in rows.size():
		motion.tween_method(_set_row.bind(index, "appear"), 0.0, 1.0, 0.42).set_delay(0.34 + index * 0.09).set_trans(Tween.TRANS_CUBIC)
	await motion.finished
	_shine_t = -1.0


func _animate_check(row: Dictionary) -> void:
	row.done_shown = true
	var at := _box_center(rows.find(row))
	var motion := _tween().set_parallel(true)
	motion.tween_method(func(value: float) -> void: row.pop = value, 0.0, 1.0, 0.42)
	motion.tween_method(func(value: float) -> void: row.check = value, 0.0, 1.0, 0.32).set_trans(Tween.TRANS_CUBIC)
	motion.tween_method(func(value: float) -> void: row.flash = value, 1.0, 0.0, 0.7)
	motion.tween_method(func(value: float) -> void: row.strike = value, 0.0, 1.0, 0.34).set_delay(0.2).set_trans(Tween.TRANS_QUART)
	motion.tween_method(func(value: float) -> void: row.fade = value, 0.0, 1.0, 0.4).set_delay(0.24)
	motion.tween_method(func(value: float) -> void: _progress_pop = value, 1.0, 0.0, 0.5).set_delay(0.18)
	motion.tween_callback(_burst.bind(at, 12)).set_delay(0.16)
	await motion.finished
	await _pause(0.12)


func _celebrate_stage() -> void:
	_seal_key = "ONBOARD_ALL_DONE" if displayed_stage + 1 >= goals.stages.size() else "ONBOARD_STAGE_DONE"
	var motion := _tween().set_parallel(true)
	motion.tween_property(self, "_seal_t", 1.0, 0.9).from(0.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "_shine_t", 1.0, 0.85).from(0.0).set_delay(0.1)
	motion.tween_callback(_burst.bind(_seal_center() + Vector2(0, -WREATH_RADIUS), 10)).set_delay(0.62)
	await motion.finished
	_shine_t = -1.0
	await _pause(0.85)


func _swap_stage(index: int) -> void:
	var exit := _tween().set_parallel(true)
	for row_index: int in rows.size():
		exit.tween_method(_set_row.bind(row_index, "appear"), 1.0, 0.0, 0.26).set_delay(row_index * 0.06)
	exit.tween_property(self, "_title_alpha", 0.0, 0.24)
	exit.tween_property(self, "_seal_t", 0.0, 0.3).set_delay(0.1)
	await exit.finished
	_load_stage(index)
	var enter := _tween().set_parallel(true)
	enter.tween_property(self, "_title_alpha", 1.0, 0.3)
	enter.tween_property(self, "_divider_t", 1.0, 0.45).from(0.25).set_trans(Tween.TRANS_QUART)
	for row_index: int in rows.size():
		enter.tween_method(_set_row.bind(row_index, "appear"), 0.0, 1.0, 0.42).set_delay(0.12 + row_index * 0.09).set_trans(Tween.TRANS_CUBIC)
	await enter.finished


func _leave() -> void:
	var generation := _generation
	var motion := _tween().set_parallel(true)
	motion.tween_property(self, "_slide", -40.0, 0.5).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	motion.tween_property(panel, "modulate:a", 0.0, 0.42).set_delay(0.28)
	await motion.finished
	if generation != _generation:
		return
	panel.hide()
	_shown = false
	_left = true


func _set_row(value: float, index: int, field: String) -> void:
	if index < rows.size():
		rows[index][field] = value


func _next_unshown_completion() -> Dictionary:
	for row: Dictionary in rows:
		if not row.done_shown and goals.is_goal_complete(row.id):
			return row
	return {}


func _all_rows_done() -> bool:
	for row: Dictionary in rows:
		if not row.done_shown:
			return false
	return true


func _burst(at: Vector2, count: int) -> void:
	for index: int in count:
		var angle := TAU * (float(index) + randf_range(-0.3, 0.3)) / float(count)
		var speed := randf_range(70.0, 150.0)
		_sparks.append({"pos": at, "vel": Vector2.from_angle(angle) * speed, "life": 0.0,
			"max": randf_range(0.45, 0.8), "size": randf_range(2.6, 4.6), "rot": angle, "spin": randf_range(-6.0, 6.0)})


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		panel.accept_event()
		if event.position.y <= ROWS_TOP - 8.0:
			_collapsed = not _collapsed
			_tween().tween_property(self, "_collapse_t", 1.0 if _collapsed else 0.0, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	elif event is InputEventMouseButton:
		panel.accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_shape_rows()


func _shape_rows() -> void:
	var font := GameTheme.paper_font()
	for row: Dictionary in rows:
		var paragraph: TextParagraph = row.paragraph
		paragraph.clear()
		paragraph.width = WIDTH - TEXT_X - PAD_X
		paragraph.add_string(tr(row.key), font, ROW_SIZE)
	_relayout_height()


func _row_height(row: Dictionary) -> float:
	var paragraph: TextParagraph = row.paragraph
	var lines := maxi(paragraph.get_line_count(), 1)
	return maxf(BOX + 2.0, lines * (ROW_SIZE + LINE_SPACING + 2.0) - LINE_SPACING)


func _relayout_height() -> void:
	var full := ROWS_TOP
	for row: Dictionary in rows:
		full += _row_height(row) + ROW_GAP
	full += BOTTOM_PAD - ROW_GAP
	var compact := ROWS_TOP - 8.0
	_height = lerpf(full, compact, _collapse_t)
	panel.size = Vector2(WIDTH, _height)
	if not is_equal_approx(full, _full_height):
		_full_height = full
		_layout()
	else:
		panel.position = _rest_position()


func _layout() -> void:
	if not is_instance_valid(panel):
		return
	var metrics := _axis_pixels()
	var axis: Rect2 = metrics.axis
	var room := axis.position.y - (AXIS_GAP + TOP_MARGIN) * float(metrics.scale)
	# 时间轴上方高度有限：优先保持设计比例，放不下时按完整展开高度等比缩小。
	_layout_scale = minf(float(metrics.scale) * DESIGN_SCALE, room / _full_height)
	panel.scale = Vector2.ONE * _layout_scale
	panel.position = _rest_position()


func _axis_pixels() -> Dictionary:
	var viewport_size := panel.get_viewport_rect().size
	var hud_ratio := UiScale.factor_for_pixels(get_window().size)
	var column := ColumnLayout.metrics(viewport_size / hud_ratio, viewport_size)
	var axis: Rect2 = column.axis
	return {"axis": Rect2(axis.position * hud_ratio, axis.size * hud_ratio), "scale": hud_ratio * float(column.reference_factor)}


# 右缘与时间轴对齐，底边落在时间轴上方；_slide 为登场/离场的竖向位移。
func _rest_position() -> Vector2:
	var axis: Rect2 = _axis_pixels().axis
	var bottom := axis.position.y - AXIS_GAP * _layout_scale / DESIGN_SCALE
	return Vector2(axis.end.x - WIDTH * _layout_scale, bottom - _height * _layout_scale + _slide * _layout_scale)


func _box_center(index: int) -> Vector2:
	var y := ROWS_TOP
	for row_index: int in index:
		y += _row_height(rows[row_index]) + ROW_GAP
	return Vector2(PAD_X + BOX * 0.5, y + BOX * 0.5 + 1.0)


func _seal_center() -> Vector2:
	return Vector2(WIDTH - 46.0, 38.0)


func _draw_panel() -> void:
	var canvas := panel.get_canvas_item()
	var rect := Rect2(Vector2.ZERO, panel.size)
	Paper.draw_paper(canvas, rect, Paper.BASE_TINT, true, 6.0)
	panel.draw_rect(Rect2(rect.position + Vector2(5, 5), rect.size - Vector2(10, 10)), Color(GOLD, 0.16), false, 1.0)
	_draw_header()
	var body_alpha := 1.0 - _collapse_t
	if body_alpha > 0.01:
		var y := ROWS_TOP
		var focus_index := _focus_row()
		for index: int in rows.size():
			_draw_row(rows[index], y, index == focus_index, body_alpha)
			y += _row_height(rows[index]) + ROW_GAP
	_draw_shine(rect)
	_draw_seal()
	for spark: Dictionary in _sparks:
		_draw_spark(spark)


func _draw_header() -> void:
	var font := GameTheme.paper_font()
	var appear := ease(_header_t, 0.4)
	var shift := (1.0 - appear) * 10.0
	var diamond := Vector2(PAD_X + 5.0, 20.0 + shift)
	var bob := sin(_clock * 2.2) * 0.12
	panel.draw_set_transform(diamond, PI * 0.25 + bob, Vector2.ONE)
	panel.draw_rect(Rect2(-4, -4, 8, 8), Color(GOLD, appear))
	panel.draw_rect(Rect2(-6.5, -6.5, 13, 13), Color(GOLD, 0.45 * appear), false, 1.0)
	panel.draw_set_transform(Vector2.ZERO)
	panel.draw_string(font, Vector2(PAD_X + 18.0, 25.0 + shift), tr("ONBOARD_PANEL_TITLE"), HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, Color(Palette.MUTED, appear))
	if displayed_stage >= 0 and displayed_stage < goals.stages.size():
		var stage: Dictionary = goals.stages[displayed_stage]
		var done := 0
		for row: Dictionary in rows:
			if row.done_shown:
				done += 1
		var counter := "%d/%d" % [done, rows.size()]
		var counter_size := font.get_string_size(counter, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE + 1)
		var pop := 1.0 + 0.35 * sin(_progress_pop * PI) * _progress_pop
		var counter_at := Vector2(WIDTH - PAD_X - counter_size.x * 0.5, 20.0 + shift)
		panel.draw_set_transform(counter_at, 0.0, Vector2.ONE * pop)
		panel.draw_string(font, Vector2(-counter_size.x * 0.5, 5.0), counter, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE + 1, Color(GOLD, appear * (1.0 - _seal_t * 0.85)))
		panel.draw_set_transform(Vector2.ZERO)
		var title_alpha := appear * _title_alpha
		panel.draw_string(font, Vector2(PAD_X, 50.0 + shift * 1.4 + (1.0 - _title_alpha) * 6.0), tr(stage.title_key), HORIZONTAL_ALIGNMENT_LEFT, WIDTH - PAD_X * 2.0 - 40.0, TITLE_SIZE, Color(Palette.INK, title_alpha))
	var chevron := Vector2(WIDTH - PAD_X - 2.0, 45.0)
	var turn := lerpf(0.0, -PI * 0.5, _collapse_t)
	panel.draw_set_transform(chevron, turn, Vector2.ONE)
	panel.draw_polyline(PackedVector2Array([Vector2(-4, -2), Vector2(0, 2), Vector2(4, -2)]), Color(Palette.MUTED, 0.7 * appear * (1.0 - _seal_t)), 1.5, true)
	panel.draw_set_transform(Vector2.ZERO)
	var reach := ease(_divider_t, 0.3) * (WIDTH * 0.5 - PAD_X)
	var center := WIDTH * 0.5
	if reach > 1.0:
		var line_y := 62.0
		var points := PackedVector2Array([Vector2(center - reach, line_y), Vector2(center, line_y), Vector2(center + reach, line_y)])
		panel.draw_polyline_colors(points, PackedColorArray([Color(GOLD, 0.0), Color(GOLD, 0.75), Color(GOLD, 0.0)]), 1.2, true)
		panel.draw_set_transform(Vector2(center, line_y), PI * 0.25, Vector2.ONE)
		panel.draw_rect(Rect2(-2.5, -2.5, 5, 5), Color(GOLD, ease(_divider_t, 2.0)))
		panel.draw_set_transform(Vector2.ZERO)


func _draw_row(row: Dictionary, y: float, focused: bool, body_alpha: float) -> void:
	var appear: float = ease(row.appear, 0.5)
	if appear <= 0.01:
		return
	var alpha := appear * body_alpha
	var offset := (1.0 - appear) * 18.0
	var box_center := Vector2(PAD_X + BOX * 0.5 + offset, y + BOX * 0.5 + 1.0)
	if row.flash > 0.0:
		var band := Rect2(Vector2(PAD_X - 8.0, y - 5.0), Vector2(WIDTH - PAD_X * 2.0 + 16.0, _row_height(row) + 10.0))
		panel.draw_rect(band, Color(GLOW, 0.16 * row.flash * alpha))
	var pop: float = 1.0 + 0.32 * sin(row.pop * PI) * (1.0 - row.pop * 0.4)
	panel.draw_set_transform(box_center, 0.0, Vector2.ONE * pop)
	var half := BOX * 0.5
	var box := Rect2(-half, -half, BOX, BOX)
	if row.check > 0.0:
		panel.draw_rect(box, Color(GOLD_DEEP, 0.55 * alpha * minf(row.check * 2.0, 1.0)))
	panel.draw_rect(box, Color(GOLD, 0.92 * alpha), false, 1.6, true)
	if focused and row.check <= 0.0:
		var breathe := 0.5 + 0.5 * sin(_clock * 3.4)
		panel.draw_rect(box.grow(2.5 + breathe * 2.0), Color(GOLD, (0.38 - breathe * 0.26) * alpha), false, 1.2, true)
	if row.check > 0.0:
		_draw_check(row.check, alpha)
	panel.draw_set_transform(Vector2.ZERO)
	var paragraph: TextParagraph = row.paragraph
	var faded: Color = Palette.INK.lerp(Palette.MUTED, row.fade * 0.7)
	if focused and row.check <= 0.0:
		faded = Palette.INK.lerp(GLOW, 0.18 + 0.1 * sin(_clock * 3.4))
	faded.a = alpha * lerpf(1.0, 0.82, row.fade)
	var line_y := y - 1.0
	var text_x := TEXT_X + offset
	for line: int in paragraph.get_line_count():
		var line_size := paragraph.get_line_size(line)
		paragraph.draw_line(panel.get_canvas_item(), Vector2(text_x, line_y), line, faded)
		if row.strike > 0.0:
			var progress := clampf(row.strike * paragraph.get_line_count() - line, 0.0, 1.0)
			if progress > 0.0:
				var mid := line_y + line_size.y * 0.55
				panel.draw_line(Vector2(text_x - 2.0, mid), Vector2(text_x - 2.0 + (line_size.x + 4.0) * progress, mid), Color(GOLD, 0.62 * alpha), 1.3, true)
		line_y += line_size.y + LINE_SPACING


# 勾号分两笔描出，笔尾带亮点，模拟墨水快速落笔。
func _draw_check(amount: float, alpha: float) -> void:
	var a := Vector2(-5.5, 0.5)
	var b := Vector2(-1.5, 4.5)
	var c := Vector2(6.5, -5.5)
	var first := clampf(amount / 0.4, 0.0, 1.0)
	var second := clampf((amount - 0.4) / 0.6, 0.0, 1.0)
	var points := PackedVector2Array([a, a.lerp(b, first)])
	if second > 0.0:
		points.append(b.lerp(c, second))
	var ink := Color(Color("fff6dc"), alpha)
	panel.draw_polyline(points, Color(GOLD_DEEP, 0.6 * alpha), 4.2, true)
	panel.draw_polyline(points, ink, 2.4, true)
	if amount < 1.0:
		panel.draw_circle(points[points.size() - 1], 2.2, Color(GLOW, alpha))


func _draw_shine(rect: Rect2) -> void:
	if _shine_t < 0.0 or _shine_t >= 1.0:
		return
	var x := lerpf(-80.0, rect.size.x + 80.0, ease(_shine_t, -1.6))
	var band := PackedVector2Array([Vector2(x - 26.0, -4.0), Vector2(x + 14.0, -4.0), Vector2(x - 26.0 - rect.size.y * 0.35 + 40.0, rect.size.y + 4.0), Vector2(x - 66.0 - rect.size.y * 0.35 + 40.0, rect.size.y + 4.0)])
	var bounds := PackedVector2Array([Vector2(4, 4), Vector2(rect.size.x - 4, 4), Vector2(rect.size.x - 4, rect.size.y - 4), Vector2(4, rect.size.y - 4)])
	var strength := sin(_shine_t * PI)
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(band, bounds):
		panel.draw_colored_polygon(piece, Color(GLOW, 0.09 * strength))


# 完成徽记：金线月桂环自下而上逐叶生长，顶端小星点亮；与纸面 UI 的暖金描线同一语言。
func _draw_seal() -> void:
	if _seal_t <= 0.01:
		return
	var font := GameTheme.paper_font()
	var center := _seal_center()
	var alpha := clampf(_seal_t * 2.5, 0.0, 1.0)
	panel.draw_set_transform(center, 0.0, Vector2.ONE * lerpf(1.12, 1.0, ease(_seal_t, 0.4)))
	for side: float in [-1.0, 1.0]:
		var stem := PackedVector2Array()
		var reach := clampf(_seal_t * 1.25, 0.0, 1.0)
		for step: int in 13:
			var angle := lerpf(WREATH_START, WREATH_END, reach * step / 12.0)
			stem.append(_wreath_point(angle, side, WREATH_RADIUS))
		panel.draw_polyline(stem, Color(GOLD_DEEP, 0.9 * alpha), 1.3, true)
		for leaf: int in WREATH_LEAVES:
			var grow := clampf((_seal_t * 1.5 - leaf * 0.13) / 0.35, 0.0, 1.0)
			if grow > 0.0:
				var angle := lerpf(WREATH_START, WREATH_END, (leaf + 0.6) / float(WREATH_LEAVES))
				_draw_leaf(_wreath_point(angle, side, WREATH_RADIUS), angle, side, ease(grow, 0.5), alpha)
	var star_t := clampf((_seal_t - 0.65) / 0.35, 0.0, 1.0)
	if star_t > 0.0:
		var twinkle := 1.0 + 0.12 * sin(_clock * 4.0)
		_draw_star(Vector2(0, -WREATH_RADIUS - 1.0), 5.5 * ease(star_t, 0.5) * twinkle, Color(GLOW, star_t))
	var text := tr(_seal_key)
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
	panel.draw_string(font, Vector2(-size.x * 0.5, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(GOLD, clampf((_seal_t - 0.3) / 0.4, 0.0, 1.0)))
	panel.draw_set_transform(Vector2.ZERO)


func _wreath_point(angle: float, side: float, radius: float) -> Vector2:
	var point := Vector2.from_angle(angle) * radius
	return Vector2(point.x * side, point.y)


func _draw_leaf(at: Vector2, angle: float, side: float, grow: float, alpha: float) -> void:
	# 叶尖沿环向上并略向外翻，尖头椭圆叶形。
	var tangent := Vector2.from_angle(angle + PI * 0.5)
	tangent = Vector2(tangent.x * side, tangent.y)
	if tangent.y > 0.0:
		tangent = -tangent
	var outward := Vector2(at.x, at.y).normalized()
	var axis := (tangent + outward * 0.55).normalized()
	var normal := Vector2(-axis.y, axis.x)
	var length := 8.5 * grow
	var width := 2.6 * grow
	var points := PackedVector2Array()
	for step: int in 9:
		var t := step / 8.0
		points.append(at + axis * length * t + normal * width * sin(t * PI))
	for step: int in range(7, 0, -1):
		var t := step / 8.0
		points.append(at + axis * length * t - normal * width * sin(t * PI))
	panel.draw_colored_polygon(points, Color(GOLD, 0.85 * alpha))
	panel.draw_line(at, at + axis * length * 0.8, Color(GOLD_DEEP, 0.7 * alpha), 0.8, true)


func _draw_star(at: Vector2, radius: float, color: Color) -> void:
	var star := PackedVector2Array()
	for index: int in 8:
		star.append(at + Vector2.from_angle(index * PI * 0.25 - PI * 0.5) * (radius if index % 2 == 0 else radius * 0.3))
	panel.draw_colored_polygon(star, color)


func _draw_spark(spark: Dictionary) -> void:
	var t: float = spark.life / spark.max
	var alpha := (1.0 - t) * (1.0 - t)
	var radius: float = spark.size * (1.0 - t * 0.5)
	panel.draw_set_transform(spark.pos, spark.rot, Vector2.ONE)
	var star := PackedVector2Array()
	for index: int in 8:
		var length := radius if index % 2 == 0 else radius * 0.32
		star.append(Vector2.from_angle(index * PI * 0.25) * length)
	panel.draw_colored_polygon(star, Color(GLOW.lerp(GOLD, t), alpha))
	panel.draw_set_transform(Vector2.ZERO)


func _focus_row() -> int:
	for index: int in rows.size():
		if not rows[index].done_shown:
			return index
	return -1


func _tween() -> Tween:
	return create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)


func _pause(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
