extends SceneTree

const BookSkin = preload("res://scripts/ui/settings_book_skin.gd")
var failures := 0
var requested_factor := 1.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1672, 941)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var background := ColorRect.new()
	background.color = Color("43667e")
	background.size = Vector2(root.size)
	root.add_child(background)
	var option := OptionButton.new()
	option.position = Vector2(480, 120)
	option.size = Vector2(360, 50)
	for index in range(40):
		option.add_item("Resolution %02d" % index)
	BookSkin.apply_option(option)
	root.add_child(option)
	await process_frame
	var popup := option.get_popup()
	popup.about_to_popup.connect(func(): popup.content_scale_factor = requested_factor)
	for factor: float in [0.375, 0.625, 0.75, 1.0]:
		requested_factor = factor
		option.scale = Vector2.ONE * factor
		option.show_popup()
		await create_timer(0.3).timeout
		var logical := popup.get_visible_rect().size
		var paper: Vector2 = popup.get_theme_stylebox("panel").popup_full_size
		_check(is_equal_approx(popup.content_scale_factor, factor), "native inherited scale %.3f" % factor)
		_check(paper.is_equal_approx(logical), "paper matches content coordinates %.3f" % factor)
		_check(absf(paper.x - option.size.x) < 3, "popup matches scaled button width %.3f" % factor)
		popup.set_focused_item(1)
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		shot.save_png("res://outputs/settings-book-20260929/popup-scaled-%s.png" % str(factor))
		var sample := popup.position + Vector2i(popup.size.x - 35, popup.size.y - 35)
		var color := shot.get_pixelv(sample)
		_check(absf(color.r - background.color.r) + absf(color.b - background.color.b) > 0.1, "paper covers lower right content %.3f" % factor)
		print("POPUP_SCALED " + JSON.stringify({"factor": factor, "window": popup.size, "logical": logical, "paper": paper}))
		popup.hide()
		await create_timer(0.2).timeout
	print("POPUP_SCALED_SUITE failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
