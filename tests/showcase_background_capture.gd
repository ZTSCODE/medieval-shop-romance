extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1920, 1080)
	var app := PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	await create_timer(0.8).timeout
	app._commit_new_journey("Showcase")
	await create_timer(2.0).timeout
	app.set_process(false)
	app.table_stage.set_cards_visible(false)
	_hide_ui_layers(app)
	for child: Node in app.get_children():
		if child is CanvasLayer and child.layer >= 0:
			child.visible = false
		if child is CanvasItem and child != app.table_stage and child.name != "TableSurface":
			child.hide()
		if child is Node and child != app.table_stage and child != app.vegetation:
			child.set_process(false)
	var cursor := root.get_node("GameCursor")
	cursor.set_process(false)
	cursor._cursor_layer.visible = false
	if cursor._particle_layer != null:
		cursor._particle_layer.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var path := "C:/Users/ZTCUS/Documents/game/outputs/ui-motion-showcase-20260930/background.png"
	var result := root.get_texture().get_image().save_png(path)
	print("SHOWCASE_BACKGROUND result=%d size=%s" % [result, root.size])
	quit(0 if result == OK else 1)

func _hide_ui_layers(node: Node) -> void:
	if node is CanvasLayer and node.layer >= 0:
		node.visible = false
	for child: Node in node.get_children():
		_hide_ui_layers(child)
