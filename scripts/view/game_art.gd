class_name GameArt
extends RefCounted

static var _textures: Dictionary = {}
static var _pending: Array[String] = []


static func queue_card_preloads() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for catalog_path: String in ["res://data/content.json", "res://data/modules/chapter_01/source/content.json"]:
		if not FileAccess.file_exists(catalog_path):
			continue
		var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
		if not catalog is Dictionary:
			continue
		for section: String in ["cards", "npcs"]:
			for definition: Dictionary in catalog.get(section, {}).values():
				for field: String in ["art_path", "portrait_path"]:
					var path: String = definition.get(field, "")
					if path.is_empty() or _textures.has(path) or path in _pending or not ResourceLoader.exists(path):
						continue
					if ResourceLoader.load_threaded_request(path) == OK:
						_pending.append(path)


static func poll_preloads(max_completed: int = 3) -> void:
	var completed := 0
	for index in range(_pending.size() - 1, -1, -1):
		var path: String = _pending[index]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_textures[path] = ResourceLoader.load_threaded_get(path)
			_pending.remove_at(index)
			completed += 1
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending.remove_at(index)
		if completed >= max_completed:
			break


static func texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		if path in _pending and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			_textures[path] = ResourceLoader.load_threaded_get(path)
			_pending.erase(path)
		else:
			_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path] as Texture2D


static func card_texture(kind: StringName) -> Texture2D:
	return texture(String(ContentCatalog.card_definition(ContentCatalog.card_id_for_kind(kind)).get("art_path", "")))


static func portrait(npc_id: String) -> Texture2D:
	if npc_id == "hero":
		return texture(String(ContentCatalog.card_definition(ContentCatalog.card_id_for_kind(&"hero")).get("portrait_path", "")))
	return texture(String(ContentCatalog.npc_definition(npc_id).get("portrait_path", "")))


# 卡面用于棋盘、目录及头像入口；人物立绘由 portrait 单独提供。
static func card_face(subject_id: String) -> Texture2D:
	var npc := ContentCatalog.npc_definition(subject_id)
	var id := String(npc.get("card_id", ""))
	if id.is_empty():
		id = subject_id if not ContentCatalog.card_definition(subject_id).is_empty() else ContentCatalog.card_id_for_kind(StringName(subject_id))
	return texture(String(ContentCatalog.card_definition(id).get("art_path", "")))
