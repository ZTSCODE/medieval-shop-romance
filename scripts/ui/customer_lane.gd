class_name CustomerLane
extends Node2D

const SLOT_COUNT := 3
const CARD_GAP := 170.0
const CARD_TOP := 96.0
const BOARD_MARGIN := 24.0
const CUSTOMER_ACCENT := Color("9aac9d")
const ENTRANCE_SECONDS := 0.48
const PATIENCE_HEIGHT := 9.0

var views: Dictionary = {}
var market_height: float = 116.0

var _session: ShopSession
var _viewport_size := Vector2(1440.0, 900.0)
var _visible_ids: Array[String] = []
var _entrance_elapsed: Dictionary = {}
var _entrance_origin: Dictionary = {}
var _content_tickets: Dictionary = {}
var _drop_customer: String = ""
var _drop_valid: bool = false
var _card_scale: float = 1.0
var _row_top: float = CARD_TOP
var _board := Rect2(24.0, 350.0, 1392.0, 410.0)
var _font: SystemFont
var _invalid_style: AspectTextureStyle
var _patience_track: AspectTextureStyle
var _patience_fill: AspectTextureStyle


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei"])
	_invalid_style = GameTheme.paper_style("card_frame", 0.0)
	_invalid_style.modulate_color = Color("b78371")
	_patience_track = GameTheme.bar_style(GameTheme.DEEP_INK)
	_patience_fill = GameTheme.bar_style(GameTheme.GOLD)


func configure(session: ShopSession) -> void:
	_session = session
	_drop_customer = ""
	_drop_valid = false
	if is_inside_tree():
		_sync_views()
	queue_redraw()


func restore_session(session: ShopSession) -> void:
	for child: Node in get_children():
		if child is TableCardView:
			child.hide()
			child.queue_free()
	views.clear()
	_visible_ids.clear()
	_entrance_elapsed.clear()
	_entrance_origin.clear()
	_content_tickets.clear()
	configure(session)
	_entrance_elapsed.clear()
	_entrance_origin.clear()
	for index in _visible_ids.size():
		var view: TableCardView = views[_visible_ids[index]]
		view.snap_to(_slot_position(index))
		view.modulate.a = 1.0
	queue_redraw()


func _ready() -> void:
	_sync_views()


func set_viewport_size(size: Vector2) -> void:
	_viewport_size = Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	if _chapter_mode():
		_card_scale = clampf((_viewport_size.x - 96.0) / (CARD_GAP * 2.0 + TableCardView.CARD_SIZE.x), 0.52, 0.62)
		_row_top = 86.0 if _viewport_size.y >= 600.0 else 54.0
		_layout_views()
		queue_redraw()
		return
	var width_scale := (_viewport_size.x - 96.0) / (CARD_GAP * 2.0 + TableCardView.CARD_SIZE.x)
	var height_scale := (_viewport_size.y - market_height - 254.0) / 360.0
	_card_scale = clampf(minf(width_scale, height_scale), 0.6, 1.0)
	_row_top = CARD_TOP if _viewport_size.y >= 600.0 else 80.0
	var board_top := _row_top + TableCardView.CARD_SIZE.y * _card_scale + 74.0
	_board = Rect2(
		Vector2(BOARD_MARGIN, board_top),
		Vector2(maxf(_viewport_size.x - BOARD_MARGIN * 2.0, 0.0), maxf(_viewport_size.y - market_height - board_top - BOARD_MARGIN, 0.0))
	)
	_layout_views()
	queue_redraw()


func board_rect() -> Rect2:
	return _board


func snap_resized_layout() -> void:
	_layout_views()
	for index in _visible_ids.size():
		var id := _visible_ids[index]
		if not _entrance_elapsed.has(id):
			var view: TableCardView = views[id]
			view.snap_to(_slot_position(index))


func set_market_height(height: float) -> void:
	var next_height := maxf(height, 0.0)
	if is_equal_approx(market_height, next_height):
		return
	market_height = next_height
	set_viewport_size(_viewport_size)


func customer_origin(id: String) -> Vector2:
	if not views.has(id):
		return Vector2.ZERO
	var view: TableCardView = views[id]
	return view.get_visual_rect().get_center()


func patience_rect(id: String) -> Rect2:
	if not views.has(id):
		return Rect2()
	var view: TableCardView = views[id]
	var face := view.get_visual_rect()
	return Rect2(Vector2(face.position.x, face.end.y + 26.0), Vector2(face.size.x, PATIENCE_HEIGHT))


func customer_at(screen: Vector2) -> String:
	for index in range(_visible_ids.size() - 1, -1, -1):
		var id := _visible_ids[index]
		if views.has(id):
			var view: TableCardView = views[id]
			if is_instance_valid(view) and view.hit_test(screen):
				return id
	return ""


func set_drop_target(customer_id: String, valid: bool) -> void:
	_drop_customer = customer_id if views.has(customer_id) else ""
	_drop_valid = valid and not _drop_customer.is_empty()
	for id: String in views:
		var view: TableCardView = views[id]
		view.drop_target = id == _drop_customer and _drop_valid
	queue_redraw()


func _process(delta: float) -> void:
	_sync_views()
	_advance_entrances(delta)
	var pointer := get_viewport().get_mouse_position()
	for id: String in _visible_ids:
		var view: TableCardView = views[id]
		view.hovered = view.hit_test(pointer)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_content_tickets.clear()
		if is_inside_tree():
			_sync_views()
		queue_redraw()


func _sync_views() -> void:
	var active: Array[String] = []
	if _session != null and _session.state != null:
		for id: String in _session.customers:
			if active.size() >= SLOT_COUNT:
				break
			if not _session.state.cards.has(id):
				continue
			var entry: Dictionary = _session.state.cards[id]
			if entry.get("kind", &"") == &"customer" and entry.get("zone", &"") == &"queue":
				active.append(id)
	for id: String in views.keys():
		if id not in active:
			_retire_view(id)
	_visible_ids = active
	for index in active.size():
		var id := active[index]
		if not views.has(id):
			_create_view(id, index)
		var view: TableCardView = views[id]
		var entry: Dictionary = _session.state.cards[id]
		var metadata: Dictionary = entry.get("metadata", {})
		var ticket := int(metadata.get("ticket", 0))
		if _content_tickets.get(id, -1) != ticket:
			var title_format := tr("CARD_CUSTOMER_TITLE")
			var title := title_format % ticket if "%" in title_format else title_format
			var npc := ContentCatalog.npc_definition(String(metadata.get("npc_id", "")))
			if not npc.is_empty():
				title = tr(String(npc.name_key))
			var detail_key := String(npc.get("description_key", ""))
			view.set_content(title, tr("CARD_CUSTOMER_CATEGORY"), tr(detail_key) if not detail_key.is_empty() else "", CUSTOMER_ACCENT)
			_content_tickets[id] = ticket
		var total_wait := maxf(float(metadata.get("total_wait", 1.0)), 0.001)
		view.set_meter(float(metadata.get("remaining", 0.0)) / total_wait, false)
		view.drop_target = id == _drop_customer and _drop_valid
	_layout_views()


func _create_view(id: String, index: int) -> void:
	var view := TableCardView.new()
	CardContent.apply_art(view, &"customer")
	view.name = "Customer_" + id
	view.card_id = id
	view.scale = Vector2.ONE * _card_scale
	view.modulate.a = 0.0
	add_child(view)
	var origin := Vector2(_slot_position(index).x, -TableCardView.CARD_SIZE.y * _card_scale - 64.0)
	if _chapter_mode():
		origin = _session.arrival_screen_origin - TableCardView.CARD_SIZE * _card_scale * 0.5
	_entrance_origin[id] = origin
	view.snap_to(origin)
	views[id] = view
	_entrance_elapsed[id] = 0.0


func _retire_view(id: String) -> void:
	if visible:
		AudioEvents.play_event("world.departure")
	var view: TableCardView = views[id]
	views.erase(id)
	_content_tickets.erase(id)
	_entrance_elapsed.erase(id)
	_entrance_origin.erase(id)
	if _drop_customer == id:
		_drop_customer = ""
		_drop_valid = false
	view.drop_target = false
	view.hovered = false
	view.target_position = view.position - Vector2(0.0, 12.0)
	var tween := view.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(view, "modulate:a", 0.0, 0.14)
	tween.tween_callback(view.queue_free)


func _layout_views() -> void:
	for index in _visible_ids.size():
		var id := _visible_ids[index]
		var view: TableCardView = views[id]
		view.scale = Vector2.ONE * _card_scale
		if _entrance_elapsed.has(id):
			var progress := clampf(float(_entrance_elapsed[id]) / ENTRANCE_SECONDS, 0.0, 1.0)
			var eased := 1.0 - pow(1.0 - progress, 3.0)
			var destination := _slot_position(index)
			var origin: Vector2 = _entrance_origin.get(id, Vector2(destination.x, -TableCardView.CARD_SIZE.y * _card_scale - 64.0))
			view.snap_to(origin.lerp(destination, eased))
			view.modulate.a = clampf(progress * 4.0, 0.0, 1.0)
		else:
			view.target_position = _slot_position(index)
		view.z_index = index + 1


func _advance_entrances(delta: float) -> void:
	var landed: Array[String] = []
	for id: String in _entrance_elapsed:
		_entrance_elapsed[id] = minf(float(_entrance_elapsed[id]) + maxf(delta, 0.0), ENTRANCE_SECONDS)
		if float(_entrance_elapsed[id]) >= ENTRANCE_SECONDS:
			landed.append(id)
	_layout_views()
	for id in landed:
		_entrance_elapsed.erase(id)
		_entrance_origin.erase(id)
		var view: TableCardView = views[id]
		view.modulate.a = 1.0
		view.land()


func _slot_position(index: int) -> Vector2:
	var row_width := (CARD_GAP * float(SLOT_COUNT - 1) + TableCardView.CARD_SIZE.x) * _card_scale
	return Vector2(roundf((_viewport_size.x - row_width) * 0.5 + index * CARD_GAP * _card_scale), _row_top)


func _draw() -> void:
	if _chapter_mode():
		for id in _visible_ids:
			_draw_patience(id)
		return
	var label_color := Color("87938f")
	draw_string(_font, Vector2(BOARD_MARGIN + 16.0, _row_top - 12.0), tr("CUSTOMER_LANE_LABEL"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, label_color)
	draw_string(_font, Vector2(BOARD_MARGIN + 16.0, _board.position.y - 12.0), tr("SHOP_BOARD_LABEL"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, label_color)
	if _visible_ids.is_empty():
		var is_open := _session != null and _session.is_open
		var hint := tr("CUSTOMER_LANE_OPEN_HINT") if is_open else tr("CUSTOMER_LANE_CLOSED_HINT")
		var hint_size := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15)
		var hint_at := Vector2((_viewport_size.x - hint_size.x) * 0.5, _row_top + TableCardView.CARD_SIZE.y * _card_scale * 0.5 + 5.0)
		draw_string(_font, hint_at, hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, label_color)
	if not _drop_valid and views.has(_drop_customer):
		var view: TableCardView = views[_drop_customer]
		draw_style_box(_invalid_style, view.get_visual_rect().grow(3.0))
	for id in _visible_ids:
		_draw_patience(id)


func _chapter_mode() -> bool:
	return _session is ChapterCustomerQueue and _session.chapter != null


func _chapter_order_name(id: String) -> String:
	if _session == null or not _session.state.cards.has(id):
		return ""
	var item_id := ""
	var order_id := String(_session.state.cards[id].metadata.get("chapter_order_id", ""))
	for order: Dictionary in _session.catalog.get("orders", []):
		if order.id == order_id:
			item_id = String(order.item_card_id)
			break
	if item_id.is_empty():
		return ""
	var definition: Dictionary = _session.state.content_card_definition(item_id)
	return tr(String(definition.get("name_key", "")))


func _draw_patience(id: String) -> void:
	if _session == null or not _session.state.cards.has(id):
		return
	var view: TableCardView = views[id]
	var metadata: Dictionary = _session.state.cards[id].get("metadata", {})
	var remaining := maxf(float(metadata.get("remaining", 0.0)), 0.0)
	var total_wait := maxf(float(metadata.get("total_wait", 1.0)), 0.001)
	var ratio := clampf(remaining / total_wait, 0.0, 1.0)
	var rect := patience_rect(id)
	var meter_color := Color("91ad9d")
	if ratio <= 0.25:
		meter_color = Color("d58f77")
	elif ratio <= 0.5:
		meter_color = Color("c7ac7f")
	var label_format := tr("CUSTOMER_PATIENCE_LOW") if ratio <= 0.25 else tr("CUSTOMER_PATIENCE_NORMAL")
	var label := label_format % int(ceil(remaining)) if "%" in label_format else label_format
	if _chapter_mode():
		label = tr("CUSTOMER_ORDER_PATIENCE").format({"item": _chapter_order_name(id), "seconds": int(ceil(remaining))})
	var font_size := 12
	while font_size > 9 and _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x > rect.size.x:
		font_size -= 1
	var text_color := Color("cad1c8") if ratio > 0.25 else Color("e3ad98")
	text_color.a = view.modulate.a
	draw_string(_font, rect.position - Vector2(0.0, 8.0), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, font_size, text_color)
	_patience_track.modulate_color = Color(1.0, 1.0, 1.0, view.modulate.a)
	draw_style_box(_patience_track, rect)
	if ratio > 0.0:
		meter_color.a = view.modulate.a
		_patience_fill.modulate_color = meter_color
		var fill_rect := rect
		fill_rect.size.x *= ratio
		draw_style_box(_patience_fill, fill_rect)


func _meter_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.corner_detail = 8
	style.anti_aliasing = true
	return style
