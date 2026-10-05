extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--flow-qa" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var output := "res://outputs/hdr-pipeline-20261001/before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			output = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	var app := PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	await create_timer(2.0).timeout
	app._commit_new_journey("Traveller")
	await create_timer(3.0).timeout
	if "--baseline" in OS.get_cmdline_user_args():
		root.use_hdr_2d = false
		app.table_stage.card_canvas.use_hdr_2d = false
		app.table_stage.viewport_3d.use_hdr_2d = false
	var preview := TableCardView.new()
	preview.selected = true
	preview._selected_mix = 1.0
	preview._title = "HDR"
	app.table_stage._world.add_child(preview)
	preview.snap_to(Vector2(0, -550))
	await create_timer(0.5).timeout
	paused = true
	var records: Array = []
	for enabled in [false, true]:
		DisplayServer.window_request_hdr_output(enabled)
		preview.queue_redraw()
		await create_timer(1.0, true).timeout
		await RenderingServer.frame_post_draw
		var label := "hdr" if enabled else "sdr"
		var img := root.get_texture().get_image()
		img.save_exr(output.path_join(label + ".exr"))
		var display := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var color := img.get_pixel(x, y)
				if img.get_format() in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]:
					color = color.srgb_to_linear()
				color.r = color.r / (1.0 + color.r)
				color.g = color.g / (1.0 + color.g)
				color.b = color.b / (1.0 + color.b)
				display.set_pixel(x, y, color.linear_to_srgb())
		display.save_png(output.path_join(label + ".png"))
		var peak := 0.0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				var c := img.get_pixel(x, y)
				peak = maxf(peak, maxf(c.r, maxf(c.g, c.b)))
		records.append({"requested": enabled, "supported": DisplayServer.window_is_hdr_output_supported(), "active": DisplayServer.window_is_hdr_output_enabled(), "output_max": root.get_output_max_linear_value(), "format": img.get_format(), "sampled_peak": peak, "root_hdr_2d": root.use_hdr_2d, "cards_hdr_2d": app.table_stage.card_canvas.use_hdr_2d, "stage_hdr_2d": app.table_stage.viewport_3d.use_hdr_2d})
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	file.close()
	print("HDR_PIPELINE_CAPTURE ", JSON.stringify(records))
	quit()
