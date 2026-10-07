extends StyleBox

const PAPER_PATH := "res://assets/art/ui/dialogue_20261003/dialogue-wide.png"
const PAPER_REGION := Rect2(30, 150, 2080, 436)
const ASPECT := 2080.0 / 436.0
const SCREEN_WIDTH_RATIO := 1340.0 / 1672.0
# 轻微减弱紫调；保留原纸张笔触与明暗，不重新着色文字。
const PAPER_TINT := Color(1.0, 0.985, 0.955, 1.0)
const SHADOW_OFFSETS := [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2.ZERO, Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]
static var _paper: Texture2D

static func create() -> StyleBox:
	return new()

func _draw(canvas: RID, rect: Rect2) -> void:
	if _paper == null:
		_paper = load(PAPER_PATH) as Texture2D
	if _paper != null:
		var factor := rect.size.y / 223.0
		for offset: Vector2 in SHADOW_OFFSETS:
			var shadow := Rect2(rect.position + (Vector2(0, 8) + offset * 3.0) * factor, rect.size)
			ImagePlacement.draw(canvas, _paper, shadow, &"contain", Color(0, 0, 0, 0.075), PAPER_REGION)
		ImagePlacement.draw(canvas, _paper, rect, &"contain", PAPER_TINT, PAPER_REGION)

static func material() -> CanvasItemMaterial:
	return CanvasItemMaterial.new()

static func body_top(rect: Rect2, scale: float) -> float:
	return maxf(34.0 * scale, rect.size.y * 0.40)

static func fit_text(rect: Rect2, text_height: float, scale: float, available: Vector2) -> Rect2:
	# 保持纸张比例；长对白适度扩展，超过安全范围由正文滚动承接。
	var height := maxf(rect.size.y, (text_height + 60.0 * scale) / 0.60)
	var width := minf(height * ASPECT, available.x - 48.0 * scale)
	width = maxf(width, rect.size.x)
	return Rect2(Vector2((available.x - width) * 0.5, rect.end.y - width / ASPECT), Vector2(width, width / ASPECT))

static func metrics(screen: Vector2) -> Rect2:
	var factor := minf(screen.y / 941.0, screen.x / 1250.0)
	var width := minf(screen.x - 64.0 * factor, maxf(screen.x * SCREEN_WIDTH_RATIO, 1180.0 * factor))
	var height := width / ASPECT
	return Rect2(Vector2((screen.x - width) * 0.5, screen.y - height - 43.0 * factor), Vector2(width, height))
