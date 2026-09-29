class_name ChapterMarketDock
extends MarketDock

signal selection_changed

const PaperStyle = preload("res://scripts/ui/paper_skin.gd")
var chapter: ChapterRuntime
var day := 1
var _clock: DayCycle
var board: TableInteraction
var selected: Dictionary = {"supply": "", "sell": ""}
var _offers: Dictionary = {"supply": [], "sell": []}
var _error_key := ""
var _press: Dictionary = {}


func _ready() -> void:
	for side: StringName in IDS:
		var host := Control.new()
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(host)
		var feedback := UiPressFeedback.new()
		host.add_child(feedback)
		feedback.changed.connect(func(_amount: float) -> void: queue_redraw())
		_press[side] = feedback


func set_viewport_size(_size: Vector2) -> void:
	# 固定菜单使用完整屏幕，不能跟随棋盘取景预留区域改变坐标。
	_viewport_size = get_viewport().get_visible_rect().size
	queue_redraw()


func configure(value: ChapterRuntime, interaction: TableInteraction, clock: DayCycle = null) -> void:
	chapter = value
	board = interaction
	_clock = clock
	_offers = {"supply": [], "sell": []}
	if chapter != null:
		for id: String in chapter.package.market_catalog.offers:
			var side := "supply" if chapter.package.market_catalog.offers[id].mode == "buy" else "sell"
			_offers[side].append(id)
	for side: String in _offers:
		_offers[side].sort()
		if selected[side] not in _offers[side]:
			selected[side] = _offers[side][0] if not _offers[side].is_empty() else ""
	_style = PaperStyle.make(&"button")
	queue_redraw()


func slot_rect(id: StringName) -> Rect2:
	var ratio := UiScale.factor_for_pixels(get_window().size)
	var width := minf(320.0 * ratio, maxf(120.0, (_viewport_size.x - 210.0 * ratio - 64.0) * 0.5))
	var height := 112.0 * ratio
	var start := (_viewport_size.x - 2.0 * width - 20.0 * ratio - 120.0 * ratio) * 0.5
	return Rect2(Vector2(start + IDS.find(id) * (width + 20.0 * ratio), _viewport_size.y - height - 22.0 * ratio), Vector2(width, height))


func active_offer(side: StringName) -> String:
	return selected.get(String(side), "")


func source_for(side: StringName) -> String:
	return "market.ch01.supply" if side == &"supply" else "market.ch01.sell"


func current_day() -> int:
	return _clock.day if is_instance_valid(_clock) else day


func preview_stack(stack_id: String, side: StringName) -> Dictionary:
	if chapter == null or not chapter.table.stacks.has(stack_id):
		return {"ok": false}
	var ids: Array[String] = []
	ids.assign(chapter.table.stacks[stack_id].cards)
	var result := chapter.market_preview(active_offer(side), ids, source_for(side), current_day())
	_error_key = ""
	if not result.ok:
		match result.get("error", ""):
			"shared_daily_order_limit_reached", "daily_offer_limit_reached":
				_error_key = "MARKET_LIMIT_REACHED"
			"capacity_exceeded":
				_error_key = "MARKET_NO_SPACE"
	return result


func perform_stack(stack_id: String, side: StringName) -> Dictionary:
	if chapter == null or not chapter.table.stacks.has(stack_id):
		return {"ok": false}
	var ids: Array[String] = []
	ids.assign(chapter.table.stacks[stack_id].cards)
	return chapter.trade(active_offer(side), ids, source_for(side), board.camera.to_world(slot_origin(side)), current_day())


func choose_offer(offer_id: String) -> void:
	for side: String in _offers:
		if offer_id in _offers[side]:
			selected[side] = offer_id
			_error_key = ""
			selection_changed.emit()
			queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or chapter == null or get_tree().paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if board != null and not board.pressed_id.is_empty():
			return
		var side := slot_at(event.position)
		if side.is_empty():
			return
		if _press.has(side):
			_press[side].set_pressed(true)
		var rect := slot_rect(side)
		var direction := -1 if event.position.x < rect.position.x + rect.size.x * 0.22 else 1
		var entries: Array = _offers[String(side)]
		if entries.size() > 1:
			var index := entries.find(active_offer(side))
			choose_offer(entries[posmod(index + direction, entries.size())])
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if chapter == null:
		return
	var ratio := UiScale.factor_for_pixels(get_window().size)
	for side: StringName in IDS:
		var rect := slot_rect(side)
		var amount: float = _press[side].amount if _press.has(side) else 1.0
		draw_set_transform(rect.get_center(), 0.0, Vector2.ONE * amount)
		rect = Rect2(-rect.size * 0.5, rect.size)
		var active := _target == side
		var strength := maxf(_mix if active else 0.0, float(_pulse.get(side, 0.0)))
		var accent := Color("94a184") if _valid else Color("ac7564")
		_style.modulate_color = Color.WHITE.lerp(accent, strength * 0.32)
		draw_style_box(_style, rect)
		var padding := 26.0 * ratio
		var label := tr("MARKET_SUPPLY_TITLE") if side == &"supply" else tr("MARKET_SELL_TITLE")
		draw_string(_font, rect.position + Vector2(padding, 27.0 * ratio), label, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(17 * ratio), GameTheme.INK)
		var offer_id := active_offer(side)
		if offer_id.is_empty():
			continue
		var offer: Dictionary = chapter.package.market_catalog.offers[offer_id]
		var terms: Dictionary = chapter.world.market.terms(offer_id, current_day())
		var output_rules: Array = terms.outputs if terms.ok else offer.outputs
		var quote := tr("MARKET_QUOTE").format({"give": _items(offer.inputs), "receive": _items(output_rules)})
		draw_string(_font, rect.position + Vector2(padding, 58.0 * ratio), quote, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - padding * 2.0, roundi(16 * ratio), GameTheme.INK)
		var hint := tr("MARKET_SELECT")
		if active:
			hint = tr("MARKET_RELEASE_BUY" if side == &"supply" else "MARKET_RELEASE_SELL") if _valid else tr(_error_key if not _error_key.is_empty() else "MARKET_WRONG_CARD")
		elif int(offer.limit_per_day) > 0:
			hint = tr("MARKET_REMAINING").format({"count": chapter.market_remaining(offer_id, current_day())})
		draw_string(_font, rect.position + Vector2(padding, 88.0 * ratio), hint, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - padding * 2.0, roundi(12 * ratio), GameTheme.MUTED)
		draw_string(_font, rect.position + Vector2(8, 59) * ratio, "‹", HORIZONTAL_ALIGNMENT_CENTER, 18 * ratio, roundi(24 * ratio), GameTheme.INK)
		draw_string(_font, Vector2(rect.end.x - 25 * ratio, rect.position.y + 59 * ratio), "›", HORIZONTAL_ALIGNMENT_CENTER, 18 * ratio, roundi(24 * ratio), GameTheme.INK)
		draw_set_transform(Vector2.ZERO)


func _items(rules: Array) -> String:
	var labels: PackedStringArray = []
	for rule: Dictionary in rules:
		var definition := chapter.table.content_card_definition(rule.card_id)
		labels.append(tr("MARKET_ITEM").format({"name": tr(definition.name_key), "count": int(rule.count)}))
	return tr("MARKET_SEPARATOR").join(labels)
