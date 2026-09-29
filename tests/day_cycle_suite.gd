extends SceneTree

var checks := 0
var failures := 0
var ended: Array[int] = []
var started: Array[int] = []


func _initialize() -> void:
	var cycle := DayCycle.new()
	cycle.seconds_per_day = 2.0
	cycle.day_completed.connect(func(day: int) -> void: ended.append(day))
	cycle.day_started.connect(func(day: int) -> void: started.append(day))
	_check("initial day and progress", cycle.day == 1 and cycle.progress() == 0.0)
	cycle.advance(0.5)
	_check("partial day progress", cycle.day == 1 and is_equal_approx(cycle.progress(), 0.25))
	cycle.advance(1.5)
	_check("exact day rollover", cycle.day == 2 and cycle.elapsed == 0.0 and cycle.progress() == 0.0)
	_check("one completion per boundary", ended == [1] and started == [2])
	cycle.advance(5.25)
	_check("large step preserves remainder", cycle.day == 4 and is_equal_approx(cycle.elapsed, 1.25))
	_check("multiple crossed days signal in order", ended == [1, 2, 3] and started == [2, 3, 4])
	cycle.advance(0.0)
	cycle.advance(-20.0)
	cycle.advance(INF)
	cycle.advance(NAN)
	_check("invalid deltas cannot reverse or corrupt time", cycle.day == 4 and is_equal_approx(cycle.elapsed, 1.25))
	_check("progress remains normalized", is_equal_approx(cycle.progress(), 0.625))
	cycle.free()
	for fps in [30, 60, 144]:
		var sample := DayCycle.new()
		sample.seconds_per_day = 120.0
		for frame in fps * 10:
			sample.advance(1.0 / float(fps))
		_check("time is frame-rate independent at %d FPS" % fps, absf(sample.elapsed - 10.0) < 0.00001 and sample.day == 1)
		sample.free()
	print("DAY_CYCLE_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL " + label)
