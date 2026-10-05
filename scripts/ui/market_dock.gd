class_name MarketDock
extends Node2D

const RESERVED_HEIGHT := 250.0
const IDS: Array[StringName] = [&"sell", &"supply"]
var _viewport_size := Vector2(1440, 900)
var _target: StringName = &""
var _valid := false
var _mix := 0.0
var _pulse: Dictionary = {}
var _font := SystemFont.new()
var _style: AspectTextureStyle


func _init() -> void:
	_font = preload("res://scripts/ui/forest_ui_typography.gd").regular()
	_style = GameTheme.paper_style("market_panel", 0.0)


func set_viewport_size(size: Vector2) -> void:
	_viewport_size = size
	queue_redraw()


func slot_rect(id: StringName) -> Rect2:
	var width := minf(280.0, (_viewport_size.x - 72.0) * 0.5)
	var left := (_viewport_size.x - width * 2.0 - 20.0) * 0.5
	return Rect2(Vector2(left + (width + 20.0) * IDS.find(id), _viewport_size.y - 208.0), Vector2(width, 80.0))


func slot_origin(id: StringName) -> Vector2:
	return slot_rect(id).get_center()


func slot_at(point: Vector2) -> StringName:
	for id: StringName in IDS:
		if slot_rect(id).has_point(point):
			return id
	return &""


func set_drop_target(id: StringName, valid: bool) -> void:
	if _target != id or _valid != valid:
		_mix = 0.0
	_target = id
	_valid = valid
	queue_redraw()


func confirm(id: StringName) -> void:
	_pulse[id] = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	_mix = lerpf(_mix, 1.0, 1.0 - exp(-22.0 * delta))
	for id: StringName in _pulse.keys():
		_pulse[id] = move_toward(float(_pulse[id]), 0.0, delta * 3.2)
		if _pulse[id] <= 0.0:
			_pulse.erase(id)
	queue_redraw()


func _draw() -> void:
	for id: StringName in IDS:
		var rect := slot_rect(id)
		var active := _target == id
		var accent := Color("9db5a3") if id == &"supply" else Color("c2ab79")
		var strength := _mix if active else 0.0
		if active and not _valid:
			accent = Color("c58f7d")
		strength = maxf(strength, float(_pulse.get(id, 0.0)))
		_style.modulate_color = Color.WHITE.lerp(accent, strength * 0.3)
		draw_style_box(_style, rect.grow(strength * 1.5))
		var heading := tr("MARKET_SUPPLY_TITLE") if id == &"supply" else tr("MARKET_SELL_TITLE")
		var price := tr("MARKET_SUPPLY_PRICE") if id == &"supply" else tr("MARKET_SELL_PRICE")
		var hint := tr("MARKET_SUPPLY_HINT") if id == &"supply" else tr("MARKET_SELL_HINT")
		if active:
			hint = tr("MARKET_RELEASE_BUY" if id == &"supply" else "MARKET_RELEASE_SELL") if _valid else tr("MARKET_WRONG_CARD")
		draw_string(_font, rect.position + Vector2(18, 28), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GameTheme.INK)
		var price_width := _font.get_string_size(price, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(_font, Vector2(rect.end.x - 18.0 - price_width, rect.position.y + 27.0), price, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GameTheme.INK)
		draw_string(_font, rect.position + Vector2(18, 58), hint, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36, 13, GameTheme.MUTED)
