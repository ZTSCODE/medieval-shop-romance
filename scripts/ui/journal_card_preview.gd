extends Control

var view: TableCardView
var content_id := ""

func configure(id: String, width: float, highlighted: bool, title: String = "") -> void:
	content_id = id
	custom_minimum_size = Vector2(width, width * TableCardView.CARD_SIZE.y / TableCardView.CARD_SIZE.x + width * 0.10)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	view = TableCardView.new()
	view.name = "ActualGameCard"
	view.card_id = id
	view.selected = highlighted
	view._selected_mix = float(highlighted)
	view.reduced_motion = true
	add_child(view)
	var definition := ContentCatalog.card_definition(id)
	CardContent.apply(view, StringName(definition.get("kind", "")), false, title)
	resized.connect(_layout_card)
	_layout_card()

func _layout_card() -> void:
	if not is_instance_valid(view):
		return
	var factor := minf(size.x / TableCardView.CARD_SIZE.x, size.y / (TableCardView.CARD_SIZE.y + 17.0))
	view.scale = Vector2.ONE * factor
	view.snap_to((size - TableCardView.CARD_SIZE * factor) * 0.5 + Vector2(0, 4.0 * factor))
