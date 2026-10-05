extends SceneTree

# 截取真棋盘（BoardThickness + 四条 WoodRim）在默认、最远、边缘特写下的木纹，供人工比对；不写入玩家存档。
class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass
	func save_game(_slot: String, _notify: bool = true) -> Dictionary:
		return {"ok": true, "error_key": ""}

const OUTPUT := "res://outputs/board-wood/"
var app: Node
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var prefix := "after" if "--after" in OS.get_cmdline_user_args() else "before"
	root.size = Vector2i(1672, 941)
	app = PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	await create_timer(0.5).timeout
	app._commit_new_journey("QA")
	await create_timer(7.0).timeout
	app.onboarding_panel.set_available(false)
	await _shot(prefix + "-01-default.png")
	var camera: TableCamera = app.board.camera
	for view: Array in [["02-far", TableCamera.MIN_ZOOM, Vector2.ZERO], ["03-left-edge", TableCamera.MAX_ZOOM, Vector2(-1000, 0)], ["04-bottom-edge", TableCamera.MAX_ZOOM, Vector2(0, 680)], ["05-top-edge", TableCamera.MAX_ZOOM, Vector2(0, -680)]]:
		camera.zoom = view[1]
		camera.target_zoom = view[1]
		camera.offset = camera.bounds.get_center() - (view[2] as Vector2) * camera.zoom
		camera.target_offset = camera.offset
		await create_timer(0.6).timeout
		await _shot(prefix + "-" + view[0] + ".png")
	print("BOARD_WOOD_CAPTURE failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	print("capture format=%d hdr=%s" % [image.get_format(), root.use_hdr_2d])
	if root.use_hdr_2d:
		# HDR 视口回读为线性数值，直接存 PNG 会异常偏黑；按显示管线转回 sRGB。
		image.convert(Image.FORMAT_RGBAF)
		for y: int in image.get_height():
			for x: int in image.get_width():
				var color := image.get_pixel(x, y)
				image.set_pixel(x, y, Color(color.clamp().linear_to_srgb(), 1.0))
		image.convert(Image.FORMAT_RGBA8)
	_check("capture " + filename, image.save_png(OUTPUT + filename) == OK)
