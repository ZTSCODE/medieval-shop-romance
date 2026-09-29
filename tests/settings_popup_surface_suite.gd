extends SceneTree

const SettingsSkin = preload("res://scripts/ui/settings_book_skin.gd")
const OUTPUT := "res://outputs/settings-book-20260929/"
const BACKGROUND := Color("43667e")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(3840, 2160)
	root.content_scale_size = root.size
	root.gui_embed_subwindows = true
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(root.size)
	backdrop.color = BACKGROUND
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)
	var option := OptionButton.new()
	option.position = Vector2(1100, 300)
	option.size = Vector2(700, 80)
	for index in range(40):
		option.add_item("Resolution %02d" % index)
	SettingsSkin.apply_option(option)
	root.add_child(option)
	await process_frame
	root.grab_focus()
	await create_timer(0.2).timeout
	var popup := option.get_popup()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = option.position + option.size * 0.5
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	var motion := popup.get_node("SettingsPopupMotion")
	if motion._target_size == Vector2i.ZERO:
		motion._start_expansion()
	motion._tween.pause()
	motion._set_expansion(0.70)
	await process_frame
	await RenderingServer.frame_post_draw
	var early := root.get_texture().get_image()
	early.save_png(OUTPUT + "popup-3840-opening.png")
	var origin := popup.position
	var full_size: Vector2i = motion._target_size
	_check(full_size.x >= 600 and full_size.y >= 1000, "long popup expansion target is populated")
	motion._set_expansion(1.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var full := root.get_texture().get_image()
	full.save_png(OUTPUT + "popup-3840-full.png")
	full.get_region(Rect2i(origin + Vector2i(0, full_size.y - 96), Vector2i(120, 96))).save_png(OUTPUT + "popup-3840-bottom-corner.png")
	_check(full.get_size() == Vector2i(3840, 2160), "actual 3840x2160 render captured")
	var maximum_change := 0.0
	for y in range(25, mini(450, roundi(full_size.y * 0.6)), 3):
		for x in range(full_size.x - 110, full_size.x - 60, 3):
			var at := origin + Vector2i(x, y)
			var a := early.get_pixelv(at)
			var b := full.get_pixelv(at)
			maximum_change = maxf(maximum_change, absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b))
	_check(maximum_change < 0.005, "exposed paper texels remain fixed throughout expansion")
	var corner := full.get_pixelv(origin)
	var corner_delta := absf(corner.r - BACKGROUND.r) + absf(corner.g - BACKGROUND.g) + absf(corner.b - BACKGROUND.b)
	_check(popup.transparent_bg and popup.transparent and corner_delta < 0.02, "transparent popup corner shows backdrop without rectangular black clear")
	var scrollbar := _find_scrollbar(popup)
	_check(scrollbar != null, "popup exposes native scrolling control")
	if scrollbar != null:
		for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var style := scrollbar.get_theme_stylebox(state) as StyleBoxFlat
			_check(style != null and style.bg_color.r == 0 and style.bg_color.a > 0 and style.bg_color.a < 1 and style.corner_radius_top_left > 0, "rounded translucent black scrollbar " + state)
		_check(scrollbar.get_theme_icon("increment").get_image().get_used_rect().size == Vector2i.ZERO, "scrollbar arrow is invisible")
	print("POPUP_SURFACE_METRICS " + JSON.stringify({"size": full_size, "fixed_texel_max_delta": maximum_change, "corner_delta": corner_delta}))
	popup.hide()
	await create_timer(0.2).timeout
	print("POPUP_SURFACE_SUITE failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func _find_scrollbar(node: Node) -> VScrollBar:
	for child in node.get_children(true):
		if child is VScrollBar:
			return child
		var result := _find_scrollbar(child)
		if result != null:
			return result
	return null


func _check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value:
		failures += 1
