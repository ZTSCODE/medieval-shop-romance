class_name CardFlight
extends RefCounted

var origin_screen: Vector2
var source_id: StringName
var elapsed := 0.0
var delay := 0.0
var duration := 0.55
var start_scale := 0.65
var order := 0


func _init(origin: Vector2, source: StringName, index: int) -> void:
	origin_screen = origin
	source_id = source
	order = index
	delay = index * 0.055
	start_scale = 0.58 if source in [&"supply", &"sell"] else 0.8


func advance(view: TableCardView, destination: Vector2, final_scale: float, delta: float, reduced: bool) -> bool:
	elapsed += maxf(delta, 0.0)
	var travel_time := 0.22 if reduced else duration
	var t := clampf((elapsed - delay) / travel_time, 0.0, 1.0)
	var smooth := t * t * (3.0 - 2.0 * t)
	var arc := minf(100.0, 42.0 + origin_screen.distance_to(destination) * 0.12)
	var center := origin_screen.lerp(destination, smooth)
	if not reduced:
		center.y -= sin(t * PI) * arc
	var card_scale := lerpf(start_scale, final_scale, smooth)
	if not reduced:
		card_scale += sin(t * PI) * 0.045
	view.scale = Vector2.ONE * card_scale
	view.position = center - TableCardView.HALF_SIZE * card_scale
	view.target_position = view.position
	view.rotation = 0.0
	view.z_index = 3200 + order
	return t >= 1.0
