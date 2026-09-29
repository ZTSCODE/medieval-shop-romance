extends "res://tests/flat_ui_runtime_suite.gd"

func _revision_scenario() -> void:
	TranslationServer.set_locale("zh_CN")
	root.size = Vector2i(1920,1080)
	await _wait(0.5)
	app._commit_new_journey("Traveller")
	await _wait(1.6)
	for index in 4:
		app.opening.advance_intro()
	await _wait(0.4)
	await _shot("hud-rebuild-1080.png")
	await _move(app.journal.buttons.recipes.get_global_rect().get_center())
	await _wait(0.25)
	await _shot("hud-rebuild-hover.png")
	root.size = Vector2i(3840,2160)
	await _move(Vector2(12,12))
	await _wait(0.4)
	await _shot("hud-rebuild-4k.png")
