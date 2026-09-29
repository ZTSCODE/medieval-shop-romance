extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var panel := SettingsPanel.new()
	root.add_child(panel)
	panel.size = Vector2(960, 700)
	await create_timer(0.3).timeout
	var control_motion = panel.window_option.get_node("SettingsControlMotion")
	control_motion._feedback.set_pressed(true)
	await create_timer(0.10).timeout
	_check("caption follows pressed paper", is_equal_approx(control_motion._visual.scale.x, control_motion._paper.press_amount) and control_motion._visual.scale.x < 1.0)
	_check("native text is hidden once", panel.window_option.get_theme_color("font_color").a == 0.0 and control_motion._caption.get_theme_color("font_color").a > 0.0)
	control_motion._feedback.set_pressed(false)
	panel.hide()
	panel.show()
	await create_timer(0.06).timeout
	_check("entry has intermediate opacity", panel.modulate.a > 0.0 and panel.modulate.a < 1.0)
	for category: String in ["audio", "language", "audio", "display", "audio"]:
		panel.select_category(category)
		await create_timer(0.03).timeout
	await create_timer(0.32).timeout
	_check("rapid switch ends on audio", panel.current_category == "audio")
	_check("category title follows audio", panel._category_title.text == panel.tr("SETTINGS_AUDIO"))
	for key: String in panel.category_pages:
		_check("final page visibility " + key, panel.category_pages[key].visible == (key == "audio"))
		for row: Control in panel.category_pages[key].get_children():
			_check("row opacity restored", is_equal_approx(row.modulate.a, 1.0))
	var toggle = panel.mute_check
	toggle._choose(true)
	await create_timer(0.05).timeout
	_check("toggle underline travels", toggle._underline > 0.0 and toggle._underline < 1.0)
	_check("new stroke reveals progressively", toggle._reveals[0] >= 0.0 and toggle._reveals[0] < 1.0)
	_check("stroke texture loaded", toggle._stroke != null)
	toggle._choose(false)
	await create_timer(0.36).timeout
	_check("toggle reversal settles", is_equal_approx(toggle._underline, 1.0))
	_check("old stroke disappears", is_zero_approx(toggle._alphas[0]))
	_check("new stroke fully painted", is_equal_approx(toggle._reveals[1], 1.0))
	panel.select_category("display")
	var peak := 0.0
	for sample: int in 40:
		await create_timer(0.02).timeout
		peak = maxf(peak, panel.category_buttons.display.selection)
	_check("tab spring overshoots before settling", peak > 1.03)
	_check("tab spring settles", is_equal_approx(panel.category_buttons.display.selection, 1.0))
	panel._animate_back()
	panel.hide()
	panel.show()
	await create_timer(0.85).timeout
	_check("reopen cancels old close", not panel._closing and is_equal_approx(panel.modulate.a, 1.0))
	_check("entry finishes at layout origin", is_zero_approx(panel._entry_offset))
	panel.queue_free()
	await process_frame
	print("SETTINGS_MOTION failures=%d" % failures)
	quit(failures)

func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures += 1
