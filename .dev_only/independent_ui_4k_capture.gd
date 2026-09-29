extends "res://tests/independent_ui_visual_suite.gd"


func _revision_scenario() -> void:
	TranslationServer.set_locale("zh_CN")
	root.size = Vector2i(3840,2160)
	app.settings.set_value("ui_scale","auto")
	await _wait(0.5)
	app._commit_new_journey("Traveller")
	await _wait(1.6)
	for index in 4:
		app.opening.advance_intro()
	await _wait(0.3)
	await _drag(_card(&"hero"),_card_center(_card(&"forest")))
	await _wait(8.5)
	_check_hud_layout()
	await _shot("01-independent-hud-4k.png")
	await _click(app.journal.buttons.recipes)
	await _move(Vector2(12,12))
	_check_recipe_layout()
	await _shot("02-independent-recipes-4k.png")
	await _click(app.journal.buttons.npcs)
	await _move(Vector2(12,12))
	_check_relation_layout()
	await _shot("03-independent-relations-4k.png")
