extends SceneTree

var checks := 0
var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var card := TableCardView.new()
	root.add_child(card)
	card.set_content("Messenger", "", "", Color("bf7055"))
	_check("logical card remains save compatible", card.CARD_SIZE == Vector2(112, 184))
	_check("title inside card", card.FACE_RECT.encloses(card.get_title_rect()))
	_check("art below title", card.ART_RECT.position.y >= card.get_title_rect().end.y)
	_check("portrait stays inside opaque card", card.FACE_RECT.encloses(card.ART_RECT))
	card.play_unfold()
	_check("retired paper sequence absent", card.get_child_count() == 0)
	var image := Image.load_from_file(ProjectSettings.globalize_path(CrayonCardStyle.EDGE_PATH))
	_check("generated perimeter has transparent center", image.get_pixel(image.get_width() / 2, image.get_height() / 2).a == 0)
	for size in [Vector2(112, 184), Vector2(224, 368), Vector2(140, 280)]:
		var rect := Rect2(Vector2.ZERO, size)
		for patch in CrayonCardStyle.edge_patches(rect):
			var ratio: Vector2 = patch.destination.size / patch.source.size
			_check("fixed texel density and proportional patch", is_equal_approx(ratio.x, CrayonCardStyle.EDGE_SCALE) and is_equal_approx(ratio.y, CrayonCardStyle.EDGE_SCALE))
			_check("patch inside card", rect.grow(0.01).encloses(patch.destination))
	for accent in [Color("a890af"), Color("879995"), Color("bf7055"), Color("679488"), Color("6488ac")]:
		var palette := CrayonCardStyle.palette(accent)
		_check("opaque body", palette.body.a == 1.0)
		_check("no purple edge", not (palette.edge.b > palette.edge.g * 1.035 and palette.edge.r > palette.edge.g * 1.035))
	card.dragging = true
	card.drag_velocity = Vector2(250, 0)
	card._process(0.02)
	_check("drag still lifts card", card._current_lift() > 0.0)
	_check("drag still tilts card", card._tilt > 0.0)
	card.reduced_motion = true
	card._process(0.02)
	_check("reduced motion removes tilt", card._tilt == 0.0)
	print("CRAYON_CARD_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(label)
