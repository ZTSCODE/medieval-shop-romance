class_name CrayonCardStyle
extends RefCounted

const EDGE_PATH := "res://assets/art/ui/ebb_crayon/card-edge-neutral.png"
const EDGE_SOURCE := Rect2(28, 42, 912, 1548)
const CORNER_PIXELS := 80.0
const EDGE_SCALE := 0.06
static var _edge: Texture2D
static var _frame: Texture2D


static func draw_frame(canvas: RID, rect: Rect2) -> void:
	if _frame == null:
		_frame = load("res://assets/art/ui/ebb_crayon/card-frame-v2.png") as Texture2D
	var source := Rect2(40, 42, 902, 1512)
	var scale_value := minf(rect.size.x / source.size.x, rect.size.y / source.size.y)
	var fitted := source.size * scale_value
	_frame.draw_rect_region(canvas, Rect2(rect.get_center() - fitted * 0.5, fitted), source)


static func palette(accent: Color) -> Dictionary:
	var color := accent
	if color.b > color.g * 1.035 and color.r > color.g * 1.035:
		color = Color("879995")
	var body := Color.from_hsv(color.h, maxf(color.s, 0.25), clampf(color.v * 0.86, 0.42, 0.68))
	body.a = 1.0
	return {"body": body, "title": body.darkened(0.68), "edge": color.lightened(0.14)}


static func draw_card(canvas: RID, rect: Rect2, accent: Color, opacity: float = 1.0) -> void:
	var colors := palette(accent)
	var inner := rect.grow(-2.0)
	var cut := 6.0
	var polygon := PackedVector2Array([
		inner.position + Vector2(cut, 0), Vector2(inner.end.x - cut, inner.position.y),
		Vector2(inner.end.x, inner.position.y + cut), inner.end - Vector2(0, cut),
		inner.end - Vector2(cut, 0), Vector2(inner.position.x + cut, inner.end.y),
		Vector2(inner.position.x, inner.end.y - cut), inner.position + Vector2(0, cut)
	])
	RenderingServer.canvas_item_add_polygon(canvas, polygon, PackedColorArray([Color(colors.body, opacity)]))


static func draw_edge(canvas: RID, rect: Rect2, color: Color) -> void:
	if _edge == null:
		_edge = load(EDGE_PATH) as Texture2D
	if _edge == null:
		return
	for patch in edge_patches(rect):
		_edge.draw_rect_region(canvas, patch.destination, patch.source, color, false, true)


static func edge_patches(rect: Rect2) -> Array[Dictionary]:
	var patches: Array[Dictionary] = []
	var corner := minf(CORNER_PIXELS * EDGE_SCALE, minf(rect.size.x, rect.size.y) * 0.25)
	var factor := corner / CORNER_PIXELS
	for side_y in 2:
		for side_x in 2:
			var src_pos := EDGE_SOURCE.position + Vector2(side_x * (EDGE_SOURCE.size.x - CORNER_PIXELS), side_y * (EDGE_SOURCE.size.y - CORNER_PIXELS))
			var dst_pos := rect.position + Vector2(side_x * (rect.size.x - corner), side_y * (rect.size.y - corner))
			patches.append({"source": Rect2(src_pos, Vector2.ONE * CORNER_PIXELS), "destination": Rect2(dst_pos, Vector2.ONE * corner)})
	for horizontal in [true, false]:
		var length := (rect.size.x if horizontal else rect.size.y) - corner * 2.0
		var sample_length := 256.0
		var offset := 0.0
		while offset < length - 0.001:
			var amount := minf(sample_length * factor, length - offset)
			for side in 2:
				var source := Rect2()
				var destination := Rect2()
				if horizontal:
					source = Rect2(EDGE_SOURCE.position + Vector2(320, side * (EDGE_SOURCE.size.y - CORNER_PIXELS)), Vector2(amount / factor, CORNER_PIXELS))
					destination = Rect2(rect.position + Vector2(corner + offset, side * (rect.size.y - corner)), Vector2(amount, corner))
				else:
					source = Rect2(EDGE_SOURCE.position + Vector2(side * (EDGE_SOURCE.size.x - CORNER_PIXELS), 540), Vector2(CORNER_PIXELS, amount / factor))
					destination = Rect2(rect.position + Vector2(side * (rect.size.x - corner), corner + offset), Vector2(corner, amount))
				patches.append({"source": source, "destination": destination})
			offset += amount
	return patches
