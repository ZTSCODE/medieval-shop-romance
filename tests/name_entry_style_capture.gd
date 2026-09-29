extends SceneTree

class PreviewApp extends "res://scripts/table_app.gd":
	func _run_qa(_path: String) -> void:
		pass
	func _on_focus_lost() -> void:
		pass

var failures := 0
var app: Node
const OUTPUT := "res://outputs/settings-book-20260929/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if "--flow-qa" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1672, 941)
	TranslationServer.set_locale("zh_CN")
	app = PreviewApp.new()
	root.add_child(app)
	app.autosave_enabled = false
	app.board.sound.enabled = false
	await create_timer(1.5).timeout
	app.main_menu.buttons.new.pressed.emit()
	await create_timer(0.5).timeout
	var entry: NameEntry = app.name_entry
	_check("name dialog opens focused", entry.visible and entry.name_input.has_focus())
	_check("name input has no context menu or placeholder", not entry.name_input.context_menu_enabled and entry.name_input.placeholder_text.is_empty())
	await _shot("name-entry.png")
	entry.submit()
	_check("empty name rejected", entry._error_key == "NAME_ENTRY_REQUIRED")
	var han := String.chr(0x6797)
	entry.name_input.text = han.repeat(7)
	entry.name_input.text_changed.emit(entry.name_input.text)
	_check("input keeps composition without truncation", entry.name_input.max_length == 0 and entry.name_input.text.length() == 7)
	_check("weighted count reflects Han text", entry._count.text.begins_with("14 / 12"))
	entry.submit()
	_check("over budget rejected at commit", entry._error_key == "NAME_ENTRY_TOO_LONG")
	entry.name_input.text = "Journey Test"
	entry.name_input.text_changed.emit(entry.name_input.text)
	_check("typing clears error", entry._error_key.is_empty())
	root.size = Vector2i(960, 640)
	TranslationServer.set_locale("en")
	await create_timer(0.5).timeout
	_check("small layout fits", entry.panel.get_global_rect().size.x < 960 and entry.panel.get_global_rect().size.y < 640)
	await _shot("name-entry-small-en.png")
	entry.canceled.emit()
	_check("cancel leaves main menu", not entry.visible and app._at_main_menu)
	app.main_menu.buttons.new.pressed.emit()
	await create_timer(0.1).timeout
	entry.close()
	entry.open("Journey Test")
	await create_timer(0.45).timeout
	_check("reopen animation finishes", entry.panel.modulate.a == 1.0 and is_equal_approx(entry._entry_amount, 1.0))
	entry.submit()
	await create_timer(1.5).timeout
	_check("identity accepted and journey starts", app.identity.name == "Journey Test" and app._has_session and not app._at_main_menu)
	print("NAME_ENTRY_STYLE failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	_check("capture " + filename, root.get_texture().get_image().save_png(OUTPUT + filename) == OK)
