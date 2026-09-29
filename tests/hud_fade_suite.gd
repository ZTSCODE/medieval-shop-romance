extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	var overlay := SessionOverlay.new()
	root.add_child(overlay)
	await create_timer(0.35).timeout
	overlay.set_hud_visible(false)
	_check("hide disables portrait input immediately", not overlay.player_hud.focus_enabled and overlay.player_hud.portrait.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("fade does not instantly hide controls", overlay.day_root.visible and overlay.day_progress.visible and overlay.day_label.visible)
	await create_timer(0.07).timeout
	_check("fade has an intermediate alpha", overlay.day_root.modulate.a > 0 and overlay.day_root.modulate.a < 1)
	var fade := overlay._hud_fade
	overlay.set_hud_visible(false)
	_check("repeated target does not restart fade", overlay._hud_fade == fade)
	await create_timer(0.18).timeout
	_check("all HUD layers hide only after fade", not overlay.day_root.visible and not overlay.day_progress.visible and not overlay.day_label.visible and not overlay.hud_shade.visible)
	paused = true
	overlay.set_paused(true)
	overlay.set_hud_visible(true)
	await create_timer(0.25).timeout
	_check("fade in completes while game paused", is_equal_approx(overlay.day_root.modulate.a, 1) and overlay.day_root.visible and overlay.day_progress.visible)
	_check("pause still prevents portrait action", not overlay.player_hud.focus_enabled)
	overlay.set_paused(false)
	_check("resume enables visible portrait", overlay.player_hud.focus_enabled)
	print("HUD_FADE_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
