extends StyleBox

const PAPER_PATH := "res://assets/art/ui/rebuild_20260923/dialogue/dialogue-paper.png"
static var _paper: Texture2D
static var _paper_region := Rect2()

static func create() -> StyleBox:
	_load_paper()
	return new()

static func _load_paper() -> void:
	if _paper == null:
		_paper = load(PAPER_PATH) as Texture2D
		if _paper != null:
			_paper_region = Rect2(25, 143, 2031, 473)

func _draw(canvas: RID, rect: Rect2) -> void:
	_load_paper()
	if _paper != null:
		ImagePlacement.draw(canvas, _paper, rect, &"contain", Color.WHITE, _paper_region)

static func material() -> CanvasItemMaterial:
	return CanvasItemMaterial.new()

static func fit_text(rect: Rect2, text_height: float, scale: float, available: Vector2) -> Rect2:
	_load_paper()
	var aspect := _paper_region.size.x / maxf(_paper_region.size.y, 1.0)
	var height := maxf(rect.size.y, text_height + 94.0 * scale)
	var width := minf(height * aspect, available.x - 64.0 * scale)
	height = width / aspect
	return Rect2(Vector2((available.x-width)*0.5, rect.end.y-height), Vector2(width,height))

static func metrics(screen: Vector2) -> Rect2:
	var factor := minf(screen.y / 941.0, screen.x / 1250.0)
	var width := minf(screen.x - 64.0 * factor, maxf(screen.x * 0.60, 720.0 * factor))
	_load_paper()
	var aspect := _paper_region.size.x / maxf(_paper_region.size.y, 1.0)
	var height := width / maxf(aspect, 1.0)
	return Rect2(Vector2((screen.x - width) * 0.5, screen.y - height - 43.0 * factor), Vector2(width, height))

