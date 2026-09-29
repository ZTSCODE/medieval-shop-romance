extends Node2D

const DURATION := 0.28

var _age := 0.0
var _size_scale := 1.0
var _phase := 0.0


func setup(at: Vector2, size_scale: float, phase: float) -> void:
	position = at
	_size_scale = clampf(size_scale, 0.75, 1.5)
	_phase = phase
	process_mode = Node.PROCESS_MODE_ALWAYS
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress := clampf(_age / DURATION, 0.0, 1.0)
	var travel := 1.0 - pow(1.0 - progress, 3.0)
	var alpha := pow(1.0 - progress, 1.35)
	for index in 8:
		var angle := _phase - 1.22 + float(index) * 0.40
		var distance := (4.0 + float(index % 3) * 1.4 + 16.0 * travel) * _size_scale
		var point := Vector2.from_angle(angle) * distance
		var radius := maxf(0.9, (2.15 - progress * 0.55) * _size_scale)
		var color := Color(1.0, 0.84 + 0.025 * float(index % 2), 0.36, alpha * 0.96)
		draw_circle(point, radius, color, true)
		draw_circle(point, radius * 0.42, Color(1.0, 0.96, 0.76, alpha), true)
	for index in 4:
		var angle := _phase - 0.86 + float(index) * 0.58
		var direction := Vector2.from_angle(angle)
		var start := direction * (4.0 + 6.0 * travel) * _size_scale
		var finish := direction * (8.0 + 14.0 * travel) * _size_scale
		draw_line(start, finish, Color(1.0, 0.94, 0.62, alpha * 0.94), maxf(1.0, 1.25 * _size_scale), true)
