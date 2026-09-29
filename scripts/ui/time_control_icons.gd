extends RefCounted

const REGIONS := {
	"pause": Rect2(401,356,485,511),
	"play": Rect2(377,322,542,621),
	"fast": Rect2(341,271,875,490),
}
static var _icons: Dictionary = {}

static func get_icon(kind: String) -> Texture2D:
	if not _icons.has(kind):
		var atlas := AtlasTexture.new()
		atlas.atlas = load("res://assets/art/ui/hud_20260929/time-" + kind + "-icon.png")
		atlas.region = REGIONS[kind]
		_icons[kind] = atlas
	return _icons[kind]
