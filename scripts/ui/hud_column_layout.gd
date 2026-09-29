extends RefCounted

const REFERENCE_SIZE := Vector2(1672.0, 941.0)

static func metrics(available: Vector2, viewport_reference: Vector2 = Vector2.ZERO) -> Dictionary:
	if viewport_reference == Vector2.ZERO:
		viewport_reference = available
	var factor := minf(viewport_reference.x / REFERENCE_SIZE.x, viewport_reference.y / REFERENCE_SIZE.y)
	var column_height := 708.0 * factor
	var origin := Vector2(available.x - 138 * factor, (available.y - column_height) * 0.5)
	return {
		"reference_factor": factor,
		"axis": Rect2(origin, Vector2(114, 350) * factor),
		"day": Rect2(origin + Vector2(6, 277) * factor, Vector2(102, 24) * factor),
		"time_controls": Rect2(origin + Vector2(21, 304) * factor, Vector2(72, 36) * factor),
		"entries_center": origin + Vector2(57, 379) * factor,
		"portrait": Rect2(origin + Vector2(5, 551) * factor, Vector2(104, 157) * factor),
		"bounds": Rect2(origin, Vector2(114, 708) * factor),
	}
