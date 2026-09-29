extends RefCounted

static var _font: SystemFont

static func regular() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["SimSun", "NSimSun", "Georgia"])
		_font.font_weight = 400
		_font.oversampling = 4.0
	return _font
