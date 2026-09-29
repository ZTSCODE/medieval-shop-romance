extends SceneTree

var failures := 0
var last_save := ""
var saved_occupied := false
var last_load := ""
var returned := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.size = Vector2i(1100, 800)
	TranslationServer.set_locale("zh_CN")
	var panel := SaveSlotsPanel.new()
	panel.theme = preload("res://scripts/ui/game_theme.gd").make_theme()
	root.add_child(panel)
	panel.position = Vector2(50, 30)
	panel.size = Vector2(1000, 738)
	var store := SaveStore.new("res://outputs/settings-book-20260929/save-style-fixture")
	store.write_save("slot_1", {"day": 3})
	panel.configure(store)
	panel.save_clicked.connect(func(slot, occupied): last_save = slot; saved_occupied = occupied)
	panel.load_clicked.connect(func(slot): last_load = slot)
	panel.back_requested.connect(func(): returned = true)
	panel.hide()
	panel.show()
	await create_timer(0.8).timeout
	_check("spring rests at exact identity", is_equal_approx(panel._entry_scale, 1.0) and is_zero_approx(panel._entry_offset))
	_check("all four slots visible", panel.slot_controls.size() == 4)
	_check("auto slot has no save", not panel.slot_controls.auto.has("save_button"))
	_click(panel.slot_controls.slot_1.save_button)
	_check("occupied save signal preserved", last_save == "slot_1" and saved_occupied)
	_click(panel.slot_controls.slot_1.load_button)
	_check("load signal preserved", last_load == "slot_1")
	panel.set_read_only(true)
	_check("read only hides saving", not panel.slot_controls.slot_1.save_button.visible)
	panel.set_slots_enabled(false)
	_check("auto only filtering preserved", panel.slot_controls.auto.root.visible and not panel.slot_controls.slot_1.root.visible)
	panel.set_slots_enabled(true)
	panel.set_read_only(false)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://outputs/settings-book-20260929/save-page.png")
	_click(panel._back)
	_check("return signal", returned)
	panel.size = Vector2(540, 394)
	await process_frame
	_check("small page keeps uniform scale", is_equal_approx(panel._layout.scale.x, panel._layout.scale.y))
	_check("small page fits", Rect2(Vector2.ZERO, panel.size).encloses(Rect2(panel._layout.position, panel.DESIGN_SIZE * panel._layout.scale)))
	print("SAVE_PAGE_STYLE failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func _click(control: Control) -> void:
	var at := control.get_global_transform_with_canvas() * (control.size * 0.5)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
