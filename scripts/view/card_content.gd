class_name CardContent
extends RefCounted

static var _definitions: Dictionary = {}
static var _art_specs: Dictionary = {}
static var _catalog_revision := -1


static func apply(view: TableCardView, kind: StringName, open: bool, title_override: String = "") -> void:
	_sync_catalog_revision()
	if not _definitions.has(kind):
		_definitions[kind] = ContentCatalog.card_definition(ContentCatalog.card_id_for_kind(kind))
	var definition: Dictionary = _definitions[kind]
	view.category_id = StringName(definition.get("category", "item"))
	view.content_kind = kind
	var title_key: String = definition.get("name_key", "")
	var detail_key: String = definition.get("detail_key", "")
	if kind == &"shop" and open:
		title_key = definition.get("open_name_key", title_key)
		detail_key = definition.get("open_detail_key", detail_key)
	var accent := Color(String(definition.get("accent", "a7aaa1")))
	var display_palette := {
		&"hero": Color("879995"),
		&"messenger": Color("bf7055"),
		&"forest": Color("679488"),
		&"tree": Color("679488"),
		&"town_gate": Color("6488ac"),
	}
	accent = display_palette.get(kind, accent)
	if kind == &"shop" and open:
		accent = Color("7eaa91")
	view.set_content(title_override if not title_override.is_empty() else _text(title_key), _text(String(definition.get("category_key", ""))), _text(detail_key), accent)
	apply_art(view, kind)
	view.set_meter(0.0, false)


static func apply_art(view: TableCardView, kind: StringName) -> void:
	_sync_catalog_revision()
	if not _art_specs.has(kind):
		if not _definitions.has(kind):
			_definitions[kind] = ContentCatalog.card_definition(ContentCatalog.card_id_for_kind(kind))
		var definition: Dictionary = _definitions[kind]
		var region := Rect2(0.0, 0.0, 1.0, 1.0)
		var values: Array = definition.get("art_region", [])
		if values.size() == 4:
			region = Rect2(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
		_art_specs[kind] = {
			"texture": GameArt.texture(String(definition.get("art_path", ""))),
			"region": region,
			"portrait": definition.get("art_is_portrait", definition.get("category", "") == "character"),
			"currency": kind == &"coin",
			"fit": StringName(definition.get("art_fit", "cover")),
		}
	var art: Dictionary = _art_specs[kind]
	view.set_art(art.texture, art.region, art.portrait, art.currency, art.fit)


static func _sync_catalog_revision() -> void:
	var revision := ContentCatalog.content_revision()
	if revision != _catalog_revision:
		_catalog_revision = revision
		_definitions.clear()
		_art_specs.clear()


static func _text(key: String) -> String:
	return String(TranslationServer.translate(key)) if not key.is_empty() else ""
