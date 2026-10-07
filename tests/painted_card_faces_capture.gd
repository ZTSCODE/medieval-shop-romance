extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

const OUTPUT := "res://outputs/painted-card-faces-20261004/"
var app: Node
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures += 1

func _run() -> void:
	if DisplayServer.get_name() == "headless" or "--flow-qa" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.size = Vector2i(1672, 941)
	TranslationServer.set_locale("zh_CN")
	app = PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	await create_timer(1.0).timeout
	app._commit_new_journey(TranslationServer.translate("PLAYER_DEFAULT_NAME"))
	await create_timer(1.8).timeout
	app.opening_overlay.hide_all()
	app.opening_overlay.hide()
	_check("isolated preview save profile", app.qa_mode)
	_check("hero full portrait retained", GameArt.portrait("hero").resource_path == "res://assets/art/opening/hero.png")
	_check("NPC full portrait retained", GameArt.portrait("npc.messenger").resource_path == "res://assets/art/opening/messenger.png")
	_check("hero card differs from portrait", GameArt.card_face("hero") != GameArt.portrait("hero"))
	_check("NPC card differs from portrait", GameArt.card_face("npc.messenger") != GameArt.portrait("npc.messenger"))
	var gallery := CanvasLayer.new()
	gallery.layer = 14
	root.add_child(gallery)
	var screen := root.get_visible_rect().size
	var width := screen.x * 0.11
	var ids := ContentCatalog.card_ids()
	for index in ids.size():
		var id: String = ids[index]
		var definition := ContentCatalog.card_definition(id)
		var view := TableCardView.new()
		view.reduced_motion = true
		gallery.add_child(view)
		CardContent.apply(view, StringName(definition.kind), false)
		view.scale = Vector2.ONE * (width / TableCardView.CARD_SIZE.x)
		view.snap_to(Vector2(screen.x * 0.07 + index * (width + screen.x * 0.018), screen.y * 0.20))
		_check("painted card loaded " + id, view._art_texture != null and view._art_texture.resource_path.contains("painted_20261004"))
		_check("whole card face used " + id, view._art_region == Rect2(0, 0, 1, 1))
		var mini := preload("res://scripts/ui/journal_card_preview.gd").new()
		gallery.add_child(mini)
		mini.configure(id, width * 0.65, false)
		mini.position = Vector2(screen.x * 0.07 + index * (width + screen.x * 0.018), screen.y * 0.59)
		_check("recipe preview shares card art " + id, mini.view._art_texture == view._art_texture)
	await create_timer(0.4).timeout
	await _shot("01-cards-and-recipe-previews")
	gallery.hide()
	app.progress.meet_npc("npc.messenger", 1)
	app.journal.toggle("npcs")
	await create_timer(0.6).timeout
	var journal: JournalPanel = app.journal.npcs_panel
	_check("relationship list uses card face", journal._entry_texture("npc.messenger") == GameArt.card_face("npc.messenger"))
	var detail: Control = journal.entry_controls["npc.messenger"].detail
	var full := detail.get_node("FullRelationshipPortrait") as TextureRect
	_check("relationship right uses full portrait", full.texture == GameArt.portrait("npc.messenger"))
	await _shot("02-relationship")
	app.journal.close()
	var flow := DialogueFlow.new()
	flow.active_npc_id = "npc.messenger"
	flow.story_id = "story.messenger.edge"
	flow.line_index = 7
	app._replace_dialogue(flow)
	app._apply_pause_state()
	await create_timer(0.5).timeout
	app.opening_overlay.hide_all()
	app.opening_overlay.hide()
	app.dialogue_overlay.story_label.visible_characters = -1
	app.dialogue_overlay._characters = 100000.0
	_check("dialogue hero uses original portrait", app.dialogue_overlay.hero_portrait.texture is AtlasTexture and app.dialogue_overlay.hero_portrait.texture.atlas == GameArt.portrait("hero"))
	_check("dialogue NPC uses original portrait", app.dialogue_overlay.npc_portrait.texture is AtlasTexture and app.dialogue_overlay.npc_portrait.texture.atlas == GameArt.portrait("npc.messenger"))
	await _shot("03-dialogue-original-portraits")
	print("PAINTED_CARD_FACES failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var source := root.get_texture().get_image()
	var display := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGB8)
	for y in source.get_height():
		for x in source.get_width():
			var color := source.get_pixel(x, y)
			if source.get_format() not in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]:
				color = color.linear_to_srgb()
			display.set_pixel(x, y, color)
	display.save_png(OUTPUT + label + ".png")
