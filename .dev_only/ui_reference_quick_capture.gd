extends "res://tests/ui_reference_visual_capture.gd"


func _revision_scenario() -> void:
	TranslationServer.set_locale("zh_CN")
	root.size = Vector2i(1920, 1080)
	await _wait(0.4)
	app._commit_new_journey("Traveller")
	await _wait(1.6)
	for index in 4:
		app.opening.advance_intro()
	await _wait(0.3)
	await _drag(_card(&"hero"), _card_center(_card(&"forest")))
	await _wait(8.5)
	app.board.camera.zoom = 1.0
	app.board.camera.target_zoom = 1.0
	app.board.camera.offset = app.board.camera.bounds.get_center() - Vector2(0, -350) * app.board.camera.zoom
	app.board.camera.target_offset = app.board.camera.offset
	await _wait(0.5)
	await _shot("board-1920-auto.png")
	await _click(app.journal.buttons.recipes)
	await _move(Vector2(12, 12))
	_check_recipe_hierarchy("1920-auto")
	await _shot("recipes-1920-auto.png")
	_check("recipe page opens 1920-auto", app.journal.current_page == "recipes")
	await _click(app.journal.buttons.npcs)
	await _move(Vector2(12, 12))
	_check_relationship_hierarchy("1920-auto")
	await _shot("relations-1920-auto.png")
	_check("relationship page opens 1920-auto", app.journal.current_page == "npcs")
