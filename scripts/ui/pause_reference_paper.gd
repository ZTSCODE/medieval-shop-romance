extends StyleBox

const ROOT := "res://assets/art/ui/pause_20260929/"
static var _textures: Dictionary = {}
const REGIONS := {"panel": Rect2(36, 49, 982, 1389), "button": Rect2(83, 190, 1765, 433), "title": Rect2(86, 82, 1923, 593)}
var role := "panel"

static func make(part: String, margin: float = 0.0) -> StyleBox:
	var style := new()
	style.role = part
	style.set_content_margin_all(margin)
	return style

static func texture(part: String) -> Texture2D:
	if not _textures.has(part):
		_textures[part] = load(ROOT + "pause-" + part + ".png")
	return _textures[part]

static func region(part: String) -> Rect2:
	return REGIONS[part]

static func atlas(part: String) -> AtlasTexture:
	var result := AtlasTexture.new()
	result.atlas = texture(part)
	result.region = region(part)
	return result

func _draw(canvas: RID, rect: Rect2) -> void:
	var paper := texture(role)
	var source := region(role)
	var factor := rect.size.x / (460.0 if role == "panel" else 190.0)
	var offsets: Array = [Vector2(-1, 3), Vector2(1, 3), Vector2(0, 2)] if role == "title" else [Vector2(-2, 5), Vector2(0, 7), Vector2(2, 5)]
	var opacity := 0.10 if role == "title" else 0.16
	for offset: Vector2 in offsets:
		ImagePlacement.draw(canvas, paper, Rect2(rect.position + offset * factor, rect.size), &"contain", Color(0, 0, 0, opacity), source)
	ImagePlacement.draw(canvas, paper, rect, &"contain", Color.WHITE, source)
