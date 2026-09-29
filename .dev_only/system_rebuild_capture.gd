extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func shot(file: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://outputs/ui-rebuild-20260923/system/"+file)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/ui-rebuild-20260923/system"))
	root.size = Vector2i(1920,1080)
	TranslationServer.set_locale("zh_CN")
	var overlay := SessionOverlay.new()
	root.add_child(overlay)
	overlay.set_hud_visible(false)
	overlay.set_paused(true)
	overlay.open_page("settings")
	await shot("settings.png")
	overlay.open_page("saves")
	await shot("saves.png")
	overlay.set_paused(false)
	var entry := NameEntry.new()
	root.add_child(entry)
	entry.open()
	await shot("name.png")
	quit()
