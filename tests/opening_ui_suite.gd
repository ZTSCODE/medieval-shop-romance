extends SceneTree

const Opening = preload("res://scripts/ui/opening_overlay.gd")
const Menu = preload("res://scripts/ui/session_overlay.gd")

var checks := 0
var failures := 0
var signals := {"advance": 0, "new_journey": 0, "save": 0, "load": 0, "quit_without_save": 0, "resume": 0}
var opening: CanvasLayer
var menu: CanvasLayer


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_root := "res://work/opening-ui-%d" % OS.get_process_id()
	var settings := GameSettings.new(test_root.path_join("settings.cfg"))
	var store := SaveStore.new(test_root.path_join("saves"))
	opening = Opening.new()
	opening.advance_requested.connect(func() -> void: signals.advance += 1)
	root.add_child(opening)
	menu = Menu.new()
	menu.configure(settings, store)
	menu.new_journey_requested.connect(func() -> void: signals.new_journey += 1)
	menu.save_requested.connect(func(_slot: String) -> void: signals.save += 1)
	menu.load_requested.connect(func(_slot: String) -> void: signals.load += 1)
	menu.quit_without_save_requested.connect(func() -> void: signals.quit_without_save += 1)
	menu.resume_requested.connect(func() -> void: signals.resume += 1)
	root.add_child(menu)
	await _settle()
	_check("opening starts hidden", not opening.intro_visible and not opening._intro_root.visible and not opening.tutorial_label.visible)
	_check("opening is independently processed below the system menu", opening.process_mode == Node.PROCESS_MODE_ALWAYS and opening.layer < menu.layer)
	opening.advance()
	_check("hidden opening cannot advance", signals.advance == 0)
	opening.show_intro(0, 4)
	await _settle()
	_check("intro does not own simulation pause", not paused)
	_check("first page uses its localized story key", opening.intro_index == 0 and opening.story_label.text == opening.tr("OPENING_PAGE_1"))
	_check("continue is available during the fade", not opening.continue_button.disabled)
	_check("intro blocks the table pointer", opening.blocks_pointer(root.get_visible_rect().get_center()))
	_check("first page has a continue caption", opening.continue_button.text == opening.tr("OPENING_CONTINUE"))
	_check("intro uses a bottom text window without a full screen shade", opening.find_child("OpeningShade", true, false) == null and opening.text_panel.get_global_rect().position.y >= root.get_visible_rect().size.y * 0.5)
	await _click(Vector2(20.0, 200.0))
	_check("clicking the visible table does not skip a story page", signals.advance == 0)
	await _click(opening.text_panel.get_global_rect().position + Vector2(12.0, 12.0))
	_check("text window space requests exactly one advance per click", signals.advance == 1)
	await _click(opening.continue_button.get_global_rect().get_center())
	_check("continue button requests exactly one advance", signals.advance == 2)
	opening.set_menu_paused(true)
	opening.advance()
	await _click(opening.text_panel.get_global_rect().position + Vector2(12.0, 12.0))
	_check("system menu disables all intro advance routes", signals.advance == 2 and opening.continue_button.disabled)
	opening.show_intro(1, 4)
	var paused_alpha: float = opening._content.modulate.a
	await create_timer(0.3, true).timeout
	_check("intro reveal stays frozen under the system menu", is_equal_approx(opening._content.modulate.a, paused_alpha))
	opening.set_menu_paused(false)
	await create_timer(0.3, true).timeout
	_check("intro reveal resumes after closing the system menu", is_equal_approx(opening._content.modulate.a, 1.0))
	opening.show_intro(3, 4)
	_check("last page uses the enter caption", opening.continue_button.text == opening.tr("OPENING_ENTER"))
	opening.show_intro(99, 4)
	_check("out of range page input is clamped", opening.intro_index == 3)
	opening.show_intro(-1, 4)
	_check("negative page input is clamped", opening.intro_index == 0)
	for locale: String in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		await _settle()
		_check(locale + " intro text is translated", opening.story_label.text == opening.tr("OPENING_PAGE_1") and opening.story_label.text != "OPENING_PAGE_1")
		_check(locale + " page count is translated", opening._page_label.text == opening.tr("OPENING_PAGE_FORMAT") % [1, 4])
		for dimensions: Vector2i in [Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1680, 720)]:
			root.size = dimensions
			await _settle()
			_check(locale + " intro text remains inside resized viewport", _contains(root.get_visible_rect(), opening._content.get_global_rect()))
			_check(locale + " text panel remains at the viewport bottom", _contains(root.get_visible_rect(), opening.text_panel.get_global_rect()) and absf(root.get_visible_rect().end.y - opening.text_panel.get_global_rect().end.y - 30.0) <= 1.0)
			_check(locale + " text window leaves most of the table visible", opening.text_panel.size.y < root.get_visible_rect().size.y * 0.5)
			_check(locale + " story text has enough height", opening.story_label.size.y + 1.0 >= opening.story_label.get_minimum_size().y)
	opening.show_tutorial("OPENING_TUTORIAL_DRAG")
	_check("tutorial replaces the bottom intro window", not opening.intro_visible and not opening._intro_root.visible and opening.tutorial_label.visible)
	_check("tutorial does not block table interaction", not opening.blocks_pointer(root.get_visible_rect().get_center()) and opening.tutorial_label.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("tutorial uses the requested localized text", opening.tutorial_label.text == opening.tr("OPENING_TUTORIAL_DRAG"))
	_check("tutorial remains inside the viewport", _contains(root.get_visible_rect(), opening.tutorial_label.get_global_rect()))
	opening.advance()
	_check("tutorial cannot accidentally advance a story page", signals.advance == 2)
	opening.show_tutorial("OPENING_TUTORIAL_WORK")
	_check("tutorial can reflect exploration progress", opening.tutorial_label.text == opening.tr("OPENING_TUTORIAL_WORK"))
	opening.hide_all()
	_check("hide clears both story and tutorial", not opening._intro_root.visible and not opening.tutorial_label.visible)
	menu.set_paused(true)
	await _settle()
	_check("system menu contains a localized new journey entry", menu.new_journey_button.visible and menu.new_journey_button.text == menu.tr("MENU_NEW_JOURNEY"))
	_check("system menu is a closable floating panel", menu._window.close_button.is_visible_in_tree() and _contains(root.get_visible_rect(), menu.page_root.get_global_rect()) and menu.page_root.get_global_rect().get_area() < root.get_visible_rect().get_area() * 0.6)
	await _click(menu._window.close_button.get_global_rect().get_center())
	_check("floating menu close requests resume", signals.resume == 1)
	_check("system menu keeps game journals outside its pages", not menu.PAGE_KEYS.has("recipes") and not menu.PAGE_KEYS.has("npcs"))
	menu.new_journey_button.pressed.emit()
	_check("starting a new journey first opens confirmation", menu.confirmation_dialog.visible and menu._pending_action == "new_journey" and signals.new_journey == 0)
	_check("new journey confirmation has its own localized copy", menu.confirmation_dialog.title == menu.tr("NEW_JOURNEY_CONFIRM_TITLE") and menu.confirmation_dialog.dialog_text == menu.tr("NEW_JOURNEY_CONFIRM_BODY"))
	_check("back dismisses the confirmation before the menu", menu.back() and not menu.confirmation_dialog.visible and menu.current_page == "main" and signals.new_journey == 0)
	menu.new_journey_button.pressed.emit()
	menu.confirmation_dialog.confirmed.emit()
	_check("confirmed new journey emits exactly one system action", signals.new_journey == 1 and signals.save == 0 and signals.load == 0 and not menu.confirmation_dialog.visible)
	menu._on_save_clicked("slot_1", true)
	menu.confirmation_dialog.confirmed.emit()
	_check("overwrite confirmation still routes to saving", signals.save == 1 and signals.new_journey == 1)
	menu._on_load_clicked("slot_1")
	menu.confirmation_dialog.confirmed.emit()
	_check("load confirmation still routes to loading", signals.load == 1 and signals.new_journey == 1)
	menu.confirm_quit_without_save()
	menu.confirmation_dialog.confirmed.emit()
	_check("failed-save quit confirmation still routes correctly", signals.quit_without_save == 1 and signals.new_journey == 1)
	menu.new_journey_button.pressed.emit()
	menu.set_paused(false)
	_check("leaving the menu clears stale pending actions", not menu.confirmation_dialog.visible and menu._pending_action.is_empty())
	opening.queue_free()
	menu.queue_free()
	await process_frame
	print("OPENING_UI_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * at
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = root.get_final_transform() * at
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _contains(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(1.0).encloses(inner)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL " + label)
