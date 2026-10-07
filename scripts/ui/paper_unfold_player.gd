class_name PaperUnfoldPlayer
extends Node2D

signal finished

const ASSET_ROOT := "res://assets/art/ui/rose_modular/"
const FRAME_TOTAL := 9
const CENTER_REPEAT_SOURCE_HEIGHT := 32.0
const OPAQUE_PAPER_SHADER := preload("res://scripts/ui/paper_unfold.gdshader")
static var _clips: Dictionary = {}

var paper_rect := Rect2(0, 0, 964, 275)
var drawing_bounds: Rect2:
	get:
		return get_drawing_bounds()
var frame_index := 0
var elapsed := 0.0
var playing := false
var menu_paused := false
var kind: StringName = &"dialogue"
var _clip: Dictionary = {}


func _init() -> void:
	var paper_material := ShaderMaterial.new()
	paper_material.shader = OPAQUE_PAPER_SHADER
	material = paper_material
	hide()


func configure(value: StringName) -> void:
	kind = value
	_clip = clip_for(kind)


static func clip_for(value: StringName) -> Dictionary:
	if _clips.has(value):
		return _clips[value]
	var directory := ASSET_ROOT + "unfold_" + String(value) + "/"
	var data: Dictionary = {}
	if FileAccess.file_exists(directory + "manifest.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory + "manifest.json"))
		if parsed is Dictionary:
			data = parsed
	var default_bounds := [104, 282, 1569, 325] if value == &"dialogue" else [105, 65, 821, 1358]
	var values: Array = data.get("final_bounds", default_bounds)
	var final_rect := Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	var frames: Array[Texture2D] = []
	for index in FRAME_TOTAL:
		var texture := GameArt.texture(directory + "frame_%02d.png" % index)
		if texture != null:
			frames.append(texture)
	var frame_bounds: Array[Rect2] = []
	var entries: Array = data.get("frames", [])
	for index in FRAME_TOTAL:
		var region := final_rect
		for entry: Variant in entries:
			if entry is Dictionary and int(entry.get("index", -1)) == index:
				var raw: Variant = entry.get("bounds", entry.get("alpha_bounds", []))
				if raw is Array and raw.size() == 4:
					region = Rect2(float(raw[0]), float(raw[1]), float(raw[2]), float(raw[3]))
				break
		frame_bounds.append(region)
	var result := {"frames": frames, "bounds": final_rect, "frame_bounds": frame_bounds, "fps": float(data.get("fps", 14.0))}
	if frames.size() == FRAME_TOTAL:
		_clips[value] = result
	return result


static func final_aspect(value: StringName) -> float:
	var bounds: Rect2 = clip_for(value).bounds
	return bounds.size.x / maxf(bounds.size.y, 1.0)


func play() -> void:
	AudioEvents.play_event("animation.paper_unfold")
	if _clip.is_empty():
		configure(kind)
	frame_index = 0
	elapsed = 0.0
	playing = _clip.frames.size() == FRAME_TOTAL
	visible = playing
	queue_redraw()
	if not playing:
		finished.emit()


func finish() -> void:
	var was_playing := playing
	playing = false
	frame_index = FRAME_TOTAL - 1
	hide()
	if was_playing:
		finished.emit()


func stop() -> void:
	playing = false
	hide()


func _process(delta: float) -> void:
	if not playing or menu_paused:
		return
	elapsed += maxf(delta, 0.0)
	var next := int(elapsed * _clip.fps)
	if next >= FRAME_TOTAL:
		finish()
		return
	if next != frame_index:
		frame_index = next
		queue_redraw()


func get_frame_placement() -> Dictionary:
	if _clip.is_empty() or _clip.frames.size() != FRAME_TOTAL or not paper_rect.has_area():
		return {"source": Rect2(), "destination": Rect2(), "extra_height": 0.0}
	var texture: Texture2D = _clip.frames[clampi(frame_index, 0, FRAME_TOTAL - 1)]
	var bounds: Rect2 = _clip.bounds
	var factor := minf(paper_rect.size.x / bounds.size.x, paper_rect.size.y / bounds.size.y)
	var extra_height := maxf(0.0, paper_rect.size.y - bounds.size.y * factor) if kind == &"dialogue" else 0.0
	var origin := paper_rect.get_center() - bounds.get_center() * factor - Vector2(0.0, extra_height * 0.5)
	return {
		"source": Rect2(Vector2.ZERO, texture.get_size()),
		"destination": Rect2(origin, texture.get_size() * factor),
		"extra_height": extra_height,
		"scale": factor,
		"split_y": bounds.get_center().y,
	}


func get_frame_patches() -> Array[Dictionary]:
	var patches: Array[Dictionary] = []
	var placement := get_frame_placement()
	var source: Rect2 = placement.source
	if not source.has_area():
		return patches
	var destination: Rect2 = placement.destination
	var factor: float = placement.scale
	var extra: float = placement.extra_height
	if extra <= 0.001:
		patches.append({"kind": &"whole", "source": source, "destination": destination, "scale": factor})
		return patches
	var split := clampf(float(placement.split_y), CENTER_REPEAT_SOURCE_HEIGHT, source.size.y - CENTER_REPEAT_SOURCE_HEIGHT)
	var top := Rect2(source.position, Vector2(source.size.x, split))
	patches.append({"kind": &"top", "source": top, "destination": Rect2(destination.position, top.size * factor), "scale": factor})
	var cursor := destination.position.y + split * factor
	var remaining := extra
	while remaining > 0.001:
		var source_height := minf(CENTER_REPEAT_SOURCE_HEIGHT, remaining / factor)
		var strip := Rect2(0.0, split - CENTER_REPEAT_SOURCE_HEIGHT * 0.5, source.size.x, source_height)
		var target := Rect2(Vector2(destination.position.x, cursor), strip.size * factor)
		patches.append({"kind": &"middle_repeat", "source": strip, "destination": target, "scale": factor})
		cursor += target.size.y
		remaining -= target.size.y
	var bottom := Rect2(0.0, split, source.size.x, source.size.y - split)
	patches.append({"kind": &"bottom", "source": bottom, "destination": Rect2(Vector2(destination.position.x, cursor), bottom.size * factor), "scale": factor})
	return patches


func get_drawing_bounds() -> Rect2:
	if _clip.is_empty():
		return Rect2()
	var frame_bounds: Array = _clip.get("frame_bounds", [])
	var body: Rect2 = frame_bounds[clampi(frame_index, 0, frame_bounds.size() - 1)] if not frame_bounds.is_empty() else _clip.bounds
	var result := Rect2()
	var has_result := false
	for patch: Dictionary in get_frame_patches():
		var source: Rect2 = patch.source
		var clipped := source.intersection(body)
		if not clipped.has_area():
			continue
		var factor: float = patch.scale
		var destination: Rect2 = patch.destination
		var area := Rect2(destination.position + (clipped.position - source.position) * factor, clipped.size * factor)
		result = result.merge(area) if has_result else area
		has_result = true
	return result


func _draw() -> void:
	if not playing or _clip.is_empty() or _clip.frames.size() != FRAME_TOTAL:
		return
	var texture: Texture2D = _clip.frames[frame_index]
	for patch: Dictionary in get_frame_patches():
		texture.draw_rect_region(get_canvas_item(), patch.destination, patch.source)
