extends StyleBox

const PAPER_PATH := "res://assets/art/ui/dialogue_20260929/dialogue-panel-v3.png"
const PAPER_REGION := Rect2(0, 0, 2170, 725)
const ASPECT := 2170.0 / 725.0
const SCREEN_WIDTH_RATIO := 568.0 / 1672.0
const SHADOW_OFFSETS := [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2.ZERO, Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]
static var _paper: Texture2D

static func create() -> StyleBox:
	return new()

func _draw(canvas: RID, rect: Rect2) -> void:
	if _paper == null:
		_paper = load(PAPER_PATH) as Texture2D
	if _paper != null:
		var factor := rect.size.x / 568.0
		for offset: Vector2 in SHADOW_OFFSETS:
			var shadow := Rect2(rect.position + (Vector2(0, 8) + offset * 3.0) * factor, rect.size)
			ImagePlacement.draw(canvas, _paper, shadow, &"contain", Color(0, 0, 0, 0.075), PAPER_REGION)
		ImagePlacement.draw(canvas, _paper, rect, &"contain", Color.WHITE, PAPER_REGION)

static func material() -> CanvasItemMaterial:
	return CanvasItemMaterial.new()

static func body_top(rect: Rect2, scale: float) -> float:
	return maxf(34.0 * scale, rect.size.y * 0.40)

static func fit_text(rect: Rect2, _text_height: float, _scale: float, _available: Vector2) -> Rect2:
	return rect

static func metrics(screen: Vector2) -> Rect2:
	var factor := minf(screen.y / 941.0, screen.x / 1250.0)
	var width := minf(screen.x - 64.0 * factor, maxf(screen.x * SCREEN_WIDTH_RATIO, 500.0 * factor))
	var height := width / ASPECT
	return Rect2(Vector2((screen.x - width) * 0.5, screen.y - height - 43.0 * factor), Vector2(width, height))
