extends SceneTree

const OUTPUT_DIR := "res://outputs/cursor-hand-set-20260920/runtime-verified"
const NAMES := ["normal", "hover", "pressed", "drag"]

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures += 1


func _stats(image: Image) -> Dictionary:
	var count := 0
	var total := 0.0
	var total_squared := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a < 0.99:
				continue
			var luma := color.r * 54.213 + color.g * 182.376 + color.b * 18.411
			count += 1
			total += luma
			total_squared += luma * luma
	var mean := total / maxf(1.0, count)
	var variance := total_squared / maxf(1.0, count) - mean * mean
	return {"count": count, "mean": mean, "std": sqrt(maxf(0.0, variance))}


func _run() -> void:
	root.size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var cursor = root.get_node("GameCursor")
	var runtime_textures: Array[Texture2D] = cursor.current_textures()
	var sources: Array[Texture2D] = [cursor.NORMAL_SOURCE, cursor.HOVER_SOURCE, cursor.PRESSED_SOURCE, cursor.DRAG_SOURCE]
	for index in NAMES.size():
		var source_image := sources[index].get_image()
		var runtime_image := runtime_textures[index].get_image()
		var source_stats := _stats(source_image)
		var runtime_stats := _stats(runtime_image)
		_check(NAMES[index] + " runtime size", runtime_image.get_size() == Vector2i(128, 128))
		_check(NAMES[index] + " luma preserved", absf(source_stats.mean - runtime_stats.mean) <= 2.0)
		_check(NAMES[index] + " contrast preserved", absf(source_stats.std - runtime_stats.std) <= 2.0)
		_check(NAMES[index] + " opaque subject retained", runtime_stats.count > 4000)
		runtime_image.save_png(OUTPUT_DIR.path_join(NAMES[index] + "-128.png"))
		print("METRIC %s source_mean=%.2f runtime_mean=%.2f source_std=%.2f runtime_std=%.2f" % [NAMES[index], source_stats.mean, runtime_stats.mean, source_stats.std, runtime_stats.std])
	print("CURSOR_RUNTIME_CAPTURE_FAILURES=" + str(failures))
	quit(1 if failures else 0)
