extends "res://tests/dialogue_asset_runtime_capture.gd"

func _shot(filename: String) -> void:
	if not filename.begins_with("01"):
		return
	app.opening_overlay.hide_all()
	app.opening_overlay.hide()
	var ui: DialogueOverlay = app.dialogue_overlay
	var button: Button = ui.continue_button
	var paper: Control = button.get_node("DialogueHoverPaper")
	await create_timer(0.2).timeout
	_check("continue idle background hidden", paper.modulate.a == 0.0)
	button.mouse_entered.emit()
	await create_timer(0.16).timeout
	_check("continue hover background shown", paper.modulate.a > 0.99)
	await _save_hover("continue-hover")
	button.button_down.emit()
	await create_timer(0.09).timeout
	await process_frame
	await process_frame
	_check("continue press contracts", paper.scale.x < 0.98)
	await _save_hover("continue-pressed")
	button.button_up.emit()
	button.mouse_exited.emit()
	await create_timer(0.3).timeout
	_check("continue release restores size and hides background", is_equal_approx(paper.scale.x, 1.0) and paper.modulate.a == 0.0)
	ui._sync_choices({"choices": [{"id": "preview", "text_key": "PREVIEW_DIALOGUE_SHORT"}, {"id": "preview_long", "text_key": "PREVIEW_DIALOGUE_LONG"}]})
	button.hide()
	ui._layout()
	var reply: Button = ui._choice_buttons[0]
	var reply_paper: Control = reply.get_node("DialogueHoverPaper")
	_check("reply idle background hidden", reply_paper.modulate.a == 0.0)
	reply.mouse_entered.emit()
	await create_timer(0.2).timeout
	_check("reply hover background shown", reply_paper.modulate.a > 0.99)
	await _save_hover("reply-hover")
	reply.button_down.emit()
	await create_timer(0.09).timeout
	await process_frame
	await process_frame
	_check("reply press contracts", reply_paper.scale.x < 0.98)
	reply.button_up.emit()
	reply.mouse_exited.emit()
	await create_timer(0.3).timeout
	_check("reply release hides background", reply_paper.modulate.a == 0.0)
	reply.mouse_entered.emit()
	await create_timer(0.2).timeout
	reply.disabled = true
	await create_timer(0.2).timeout
	_check("disabled reply clears hover", reply_paper.modulate.a == 0.0)
	ui._sync_choices({})
	button.show()
	ui._layout()

func _save_hover(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var display := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var color := img.get_pixel(x, y)
			if img.get_format() not in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]:
				color = color.linear_to_srgb()
			display.set_pixel(x, y, color)
	display.save_png("res://outputs/dialogue-hover-distinct-20261004/" + label + ".png")
