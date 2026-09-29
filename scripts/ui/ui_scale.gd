class_name UiScale
extends Node

const OPTIONS := ["auto", "60", "75", "90", "100", "110", "120"]
const LEGACY_OPTIONS := ["auto", "75", "85", "100", "115"]
const CONFIG_VERSION := 2
const MAX_FACTOR := 0.75
const DISPLAY_MAX := 120.0
static var preference := "auto"
static var _bindings: Array[WeakRef] = []
var _root: Control
var _layout: Callable
var _last_pixels := Vector2i(-1, -1)
var _last_reference := Vector2.ZERO


static func configure(value: String) -> void:
	if value not in OPTIONS:
		return
	preference = value
	var active: Array[WeakRef] = []
	for reference: WeakRef in _bindings:
		var binding := reference.get_ref() as UiScale
		if is_instance_valid(binding):
			active.append(reference)
			binding.refresh()
	_bindings = active


static func factor_for_pixels(pixels: Vector2i, selected: String = "") -> float:
	if selected.is_empty():
		selected = preference
	if selected != "auto":
		return clampf(float(selected), 60.0, DISPLAY_MAX) / DISPLAY_MAX * MAX_FACTOR
	# 只使用游戏实际像素尺寸，不再叠乘 Windows 的桌面缩放。
	var short_axis := minf(float(pixels.y), float(pixels.x) * 9.0 / 16.0)
	return MAX_FACTOR * lerpf(1.0, 0.78, clampf((short_axis - 1080.0) / 1080.0, 0.0, 1.0))


static func migrate_legacy(value: String) -> String:
	if value == "auto":
		return value
	var converted := clampf(float(value) / 100.0 / MAX_FACTOR * DISPLAY_MAX, 60.0, DISPLAY_MAX)
	var closest := OPTIONS[1] as String
	for option: String in OPTIONS.slice(1):
		if absf(float(option) - converted) < absf(float(closest) - converted):
			closest = option
	return closest


static func reference_size(control: Control) -> Vector2:
	return control.get_viewport_rect().size


static func bind(control: Control, layout: Callable) -> void:
	var binding := UiScale.new()
	binding.name = "UiScaleBinding"
	binding._root = control
	binding._layout = layout
	control.add_child(binding)
	_bindings.append(weakref(binding))
	binding.refresh()


static func bottom_rect(rect: Rect2, reference: Vector2, available: Vector2) -> Rect2:
	return Rect2(Vector2((available.x - rect.size.x) * 0.5, available.y - (reference.y - rect.position.y)), rect.size)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().size_changed.connect(refresh)


func _process(_delta: float) -> void:
	# 相同比例的物理窗口缩放可能不改变逻辑画布尺寸，仍需更新自动比例。
	if get_window().size != _last_pixels or reference_size(_root) != _last_reference:
		refresh()


func refresh() -> void:
	if not is_instance_valid(_root):
		return
	var ratio := factor_for_pixels(get_window().size)
	var reference := reference_size(_root)
	_last_pixels = get_window().size
	_last_reference = reference
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_root.position = Vector2.ZERO
	_root.scale = Vector2.ONE * ratio
	_root.size = reference / ratio
	if _layout.is_valid():
		_layout.call_deferred()
