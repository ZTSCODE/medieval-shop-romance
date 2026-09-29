extends "res://tests/paper_ui_runtime_suite.gd"


func _run() -> void:
	app = ArtApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	await _wait(0.5)
	app._commit_new_journey("TerrainDebug")
	for index in 4:
		app.opening.advance_intro()
	await _wait(1.6)
	var stage: TableStage3D = app.table_stage
	print("USER_TERRAIN_RUNTIME capture=",stage._capture_rect," plane_visible=",stage._card_plane.visible," menu_blend=",stage._menu_blend," transition=",stage.is_camera_transitioning()," plane_aabb=",stage._card_plane.mesh.get_aabb()," canvas_size=",stage.card_canvas.size," cards=",app.board.views.size()," camera=",stage.camera_3d.position)
	for card_id in app.board.views:
		var view: TableCardView = app.board.views[card_id]
		print("USER_TERRAIN_CARD id=",card_id," position=",view.position," target=",view.target_position," screen=",stage.to_screen(view.position))
	quit()
