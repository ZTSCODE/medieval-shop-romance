extends SceneTree

const OUTPUT_PATH := "res://outputs/cursor-hand-set-20260920/click-particles-80ms.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(800, 600)
	var background := ColorRect.new()
	background.color = Color("241f1c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	await process_frame
	var cursor = root.get_node("GameCursor")
	var logical_center: Vector2 = root.get_final_transform().affine_inverse() * Vector2(root.size) * 0.5
	cursor.spawn_click_particles(logical_center)
	await create_timer(0.08).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT_PATH)
	print("CURSOR_PARTICLE_CAPTURE=1")
	quit(0)
