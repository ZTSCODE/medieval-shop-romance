extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

var failures := 0
const OUTPUT := "res://outputs/journal-book-20260929/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var translation := Translation.new()
	translation.locale = "zh_CN"
	var csv := FileAccess.open("res://tests/fixtures/journal_style_preview.csv", FileAccess.READ)
	csv.get_csv_line()
	while not csv.eof_reached():
		var row := csv.get_csv_line()
		if row.size() >= 2:
			translation.add_message(row[0], row[1])
	TranslationServer.add_translation(translation)
	TranslationServer.set_locale("zh_CN")
	root.size = Vector2i(1672, 941)
	var app := PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	await create_timer(1.2).timeout
	app._commit_new_journey("Preview")
	await create_timer(1.2).timeout
	var journal: GameJournal = app.journal
	journal.toggle("recipes")
	await create_timer(0.85).timeout
	_check(journal.recipes_panel._details.get_node_or_null("JournalEmpty") != null, "empty catalog remains supported")
	var module := {"version": 1, "module_id": "journal_preview", "cards": {}, "recipes": {}, "npcs": {}}
	for kind: String in ["herb", "cup", "tea", "person"]:
		var id := "card.journal_preview." + kind
		module.cards[id] = {"id": id, "module_id": "journal_preview", "kind": "journal_preview_" + kind, "category": "character" if kind == "person" else "item", "name_key": "JOURNAL_PREVIEW_" + kind.to_upper(), "detail_key": "JOURNAL_PREVIEW_STORY", "unique": false, "protected": false, "sellable": true, "art_path": "res://assets/art/forest_rebuild/wooden-mug.png"}
	module.cards["card.journal_preview.herb"].art_path = "res://assets/art/vegetation/white_flowers.png"
	module.recipes["recipe.journal_preview.tea"] = {"id": "recipe.journal_preview.tea", "name_key": "JOURNAL_PREVIEW_RECIPE", "description_key": "JOURNAL_PREVIEW_RECIPE", "action": "craft", "duration": 2.0, "inputs": [{"card_id": "card.journal_preview.herb", "count": 2}], "reusable": [{"card_id": "card.journal_preview.cup", "count": 1}], "outputs": [{"card_id": "card.journal_preview.tea", "count": 1}], "requires_facts": [], "grants_facts": []}
	var crowded: Dictionary = module.recipes["recipe.journal_preview.tea"].duplicate(true)
	crowded.id = "recipe.journal_preview.crowded"
	crowded.inputs.append({"card_id": "card.journal_preview.tea", "count": 1})
	crowded.outputs.append({"card_id": "card.journal_preview.herb", "count": 1})
	module.recipes[crowded.id] = crowded
	module.npcs["npc.journal_preview.person"] = {"id": "npc.journal_preview.person", "card_id": "card.journal_preview.person", "name_key": "JOURNAL_PREVIEW_PERSON", "description_key": "JOURNAL_PREVIEW_STORY", "encounter_name_key": "JOURNAL_PREVIEW_PLACE", "portrait_path": "res://tests/fixtures/journal-preview-portrait"}
	var portrait := AtlasTexture.new()
	portrait.atlas = GameArt.texture("res://assets/art/ui/hud_20260929/player-preview-reference.png")
	portrait.region = Rect2(1544, 563, 95, 120)
	GameArt._textures["res://tests/fixtures/journal-preview-portrait"] = portrait
	var registered := ContentCatalog.enable_module("journal_preview", module)
	_check(registered.ok, "isolated fixture registered " + str(registered.error))
	app.progress.discover_recipe("recipe.journal_preview.tea")
	app.progress.meet_npc("npc.journal_preview.person", 1)
	app.progress.npcs["npc.journal_preview.person"].affection = 35
	journal.refresh()
	await create_timer(0.4).timeout
	await _shot("recipes.png")
	app.progress.discover_recipe("recipe.journal_preview.crowded")
	await process_frame
	await _click(journal.recipes_panel.entry_controls["recipe.journal_preview.crowded"].root)
	await create_timer(0.2).timeout
	var detail: Control = journal.recipes_panel.entry_controls["recipe.journal_preview.crowded"].detail
	_check(journal.recipes_panel.selected_id == "recipe.journal_preview.crowded" and detail.find_child("RecipeIngredients", true, false) != null, "multi ingredient recipe switches to wrapped layout")
	await _shot("recipes-wrapped.png")
	app.progress.discovered_recipes.erase("recipe.journal_preview.crowded")
	journal.refresh()
	await _click(journal.tabs["npcs"])
	await create_timer(0.85).timeout
	_check(journal.current_page == "npcs" and journal.npcs_panel.visible and not journal.recipes_panel.visible, "tabs switch content")
	_check(journal.npcs_panel.entry_controls["npc.journal_preview.person"].affection_bar.value == 35, "relationship state preserved")
	await _shot("relationships.png")
	journal.close()
	journal.toggle("recipes")
	await create_timer(0.85).timeout
	_check(journal.panel.visible and is_equal_approx(journal.panel.modulate.a, 1.0), "close reopen cancels old animation")
	root.size = Vector2i(960, 640)
	await create_timer(0.5).timeout
	_check(journal._root.get_global_rect().encloses(journal.panel.get_global_rect()), "small window contains whole page")
	await _shot("small-recipes.png")
	journal.close()
	await create_timer(0.25).timeout
	_check(not journal.panel.visible and not journal.is_open(), "close finishes")
	print("JOURNAL_BOOK_SUITE failures=%d" % failures)
	if "--preview-hold" in OS.get_cmdline_user_args():
		root.size = Vector2i(1672, 941)
		journal.toggle("npcs")
		return
	quit(0 if failures == 0 else 1)

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + filename)

func _click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
