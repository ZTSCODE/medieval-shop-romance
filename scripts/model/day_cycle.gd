class_name DayCycle
extends Node

signal progress_changed(day: int, progress: float)
signal day_completed(day: int)
signal day_started(day: int)

@export_range(1.0, 3600.0, 1.0) var seconds_per_day := 120.0
var day := 1
var elapsed := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	var duration := maxf(seconds_per_day, 0.1)
	elapsed += delta
	while elapsed >= duration:
		elapsed -= duration
		day_completed.emit(day)
		day += 1
		day_started.emit(day)
	progress_changed.emit(day, progress())


func progress() -> float:
	return clampf(elapsed / maxf(seconds_per_day, 0.1), 0.0, 1.0)
