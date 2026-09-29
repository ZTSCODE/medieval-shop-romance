class_name TableCamera
extends RefCounted

const MIN_ZOOM := 0.44
const MAX_ZOOM := 1.8
var zoom := 1.0
var target_zoom := 1.0
var offset := Vector2.ZERO
var target_offset := Vector2.ZERO
var bounds := Rect2()
var projection: Node


func set_bounds(value: Rect2) -> void:
	if bounds.size == Vector2.ZERO:
		offset = value.get_center()
		target_offset = offset
	else:
		var shift := value.get_center() - bounds.get_center()
		offset += shift
		target_offset += shift
	bounds = value


func to_world(screen: Vector2) -> Vector2:
	if is_instance_valid(projection):
		return projection.to_world(screen)
	return (screen - offset) / zoom


func to_screen(world: Vector2) -> Vector2:
	if is_instance_valid(projection):
		return projection.to_screen(world)
	return world * zoom + offset


func zoom_at(screen: Vector2, factor: float) -> void:
	var anchor := to_world(screen)
	if is_instance_valid(projection):
		var center := (bounds.get_center() - target_offset) / target_zoom
		target_zoom = clampf(target_zoom * factor, MIN_ZOOM, MAX_ZOOM)
		target_offset = bounds.get_center() - center * target_zoom
		var old_zoom := zoom
		var old_offset := offset
		zoom = target_zoom
		offset = target_offset
		projection.refresh_camera()
		center += anchor - projection.to_world(screen)
		target_offset = bounds.get_center() - center * target_zoom
		zoom = old_zoom
		offset = old_offset
		projection.refresh_camera()
		constrain()
		return
	target_zoom = clampf(target_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	target_offset = screen - anchor * target_zoom
	constrain()


func pan(amount: Vector2) -> void:
	if is_instance_valid(projection):
		amount = (to_world(bounds.get_center() + amount) - to_world(bounds.get_center())) * zoom
	offset += amount
	target_offset += amount
	constrain()
	offset = target_offset


func constrain() -> void:
	var center := bounds.get_center()
	var world_center := (center - target_offset) / target_zoom
	var limit := get_pan_limit()
	world_center = world_center.clamp(-limit, limit)
	target_offset = center - world_center * target_zoom


func get_pan_limit() -> Vector2:
	var zoom_fraction := clampf((target_zoom - MIN_ZOOM) / (MAX_ZOOM - MIN_ZOOM), 0.0, 1.0)
	return TableState.WORLD_BOUNDS.size * lerpf(0.225, 0.5, zoom_fraction)


func focus(rect: Rect2) -> void:
	var padding := Vector2(110, 100)
	var available := bounds.size - padding
	target_zoom = clampf(minf(available.x / maxf(rect.size.x, TableState.CARD_SIZE.x), available.y / maxf(rect.size.y, TableState.CARD_SIZE.y)), MIN_ZOOM, 1.0)
	target_offset = bounds.get_center() - rect.get_center() * target_zoom
	constrain()


func focus_card(at: Vector2) -> void:
	target_zoom = maxf(1.0, target_zoom)
	target_offset = bounds.get_center() - at * target_zoom


func update(delta: float, reduced: bool) -> void:
	var blend := 1.0 if reduced else 1.0 - exp(-20.0 * delta)
	zoom = lerpf(zoom, target_zoom, blend)
	offset = offset.lerp(target_offset, blend)
