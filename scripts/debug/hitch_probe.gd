class_name HitchProbe
extends RefCounted

const MAX_SAMPLES := 4096
const MAX_EVENTS := 128
const HITCH_US := 16000

static var enabled := false
static var _samples: Dictionary = {}
static var _events: Array[Dictionary] = []
static var _last_frame_usec := 0
static var _mutex := Mutex.new()


static func reset() -> void:
	_mutex.lock()
	_samples.clear()
	_events.clear()
	_last_frame_usec = 0
	_mutex.unlock()


static func stamp() -> int:
	return Time.get_ticks_usec() if enabled else 0


static func record(label: String, started_usec: int) -> void:
	if not enabled or started_usec <= 0:
		return
	sample(label, Time.get_ticks_usec() - started_usec)


static func sample(label: String, duration_usec: int) -> void:
	if not enabled:
		return
	_mutex.lock()
	if not _samples.has(label):
		_samples[label] = []
	var values: Array = _samples[label]
	if values.size() >= MAX_SAMPLES:
		values.pop_front()
	values.append(maxi(duration_usec, 0))
	if duration_usec >= HITCH_US:
		if _events.size() >= MAX_EVENTS:
			_events.pop_front()
		_events.append({"label": label, "ms": snappedf(float(duration_usec) / 1000.0, 0.01), "at_usec": Time.get_ticks_usec()})
	_mutex.unlock()


static func frame(_delta: float) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	if _last_frame_usec > 0:
		sample("frame_interval", now - _last_frame_usec)
	_last_frame_usec = now


static func report() -> Dictionary:
	_mutex.lock()
	var sections := {}
	for label: String in _samples:
		var values: Array = _samples[label].duplicate()
		values.sort()
		if values.is_empty():
			continue
		var total := 0
		for value: int in values:
			total += value
		sections[label] = {"count": values.size(), "mean_ms": snappedf(float(total) / float(values.size()) / 1000.0, 0.01),
			"p95_ms": snappedf(float(values[mini(values.size() - 1, int(ceil(float(values.size()) * 0.95)) - 1)]) / 1000.0, 0.01),
			"max_ms": snappedf(float(values.back()) / 1000.0, 0.01)}
	var result := {"enabled": enabled, "hitch_threshold_ms": float(HITCH_US) / 1000.0, "sections": sections, "recent_hitches": _events.duplicate(true)}
	_mutex.unlock()
	return result


static func save(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report(), "\t", true, true))
	file.close()
	return true
