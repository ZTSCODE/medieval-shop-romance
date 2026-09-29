class_name ModuleBundle
extends RefCounted

const Registry = preload("res://scripts/content/module_registry.gd")
const StorySession = preload("res://scripts/content/module_story_session.gd")
const BASE_CONTENT := "res://data/content.json"
const BASE_TRANSLATIONS := "res://localization/game.csv"
const LOCALES := ["en", "zh_CN"]
const MAX_FILE_BYTES := 8 * 1024 * 1024

var _installed: Array[Translation] = []


func read_bundle(manifest_path: String) -> Dictionary:
	var manifest_file := _read_json(manifest_path)
	if not manifest_file.ok:
		return manifest_file
	var manifest: Dictionary = manifest_file.data
	if manifest.get("id") != "chapter_01" or not _version_one(manifest.get("schema_version")) or not manifest.get("enabled_by_default") is bool or manifest.enabled_by_default:
		return _fail("Invalid or automatically enabled module manifest")
	if not manifest.get("translations") is Array or manifest.translations.is_empty() or manifest.translations.size() > 32:
		return _fail("Manifest translations must be a nonempty path array")
	var root := ProjectSettings.globalize_path(manifest_path).replace("\\", "/").simplify_path().get_base_dir()
	var content_path := _resolve_path(root, manifest.get("content"))
	var stories_path := _resolve_path(root, manifest.get("stories"))
	if not content_path.ok:
		return content_path
	if not stories_path.ok:
		return stories_path
	var content_file := _read_json(content_path.path)
	if not content_file.ok:
		return content_file
	var graph_file := _read_json(stories_path.path)
	if not graph_file.ok:
		return graph_file
	var content: Dictionary = content_file.data
	var graph: Dictionary = graph_file.data
	if content.get("module_id") != manifest.id or not graph.get("stories") is Dictionary or not graph.get("exclusive_fact_groups", []) is Array:
		return _fail("Content ownership or story document is invalid")
	var base_file := _read_json(BASE_CONTENT)
	if not base_file.ok:
		return base_file
	var registry = Registry.new()
	var base_result: Dictionary = registry.configure_base(base_file.data)
	if not base_result.ok:
		return _fail("Base catalog validation failed: " + String(base_result.error))
	var combined := content.duplicate(true)
	if combined.has("stories") and not combined.stories is Dictionary:
		return _fail("Content story section is invalid")
	combined["stories"] = combined.get("stories", {}).duplicate(true)
	for id: Variant in graph.stories:
		if combined.stories.has(id):
			return _fail("Duplicate story ID between content and graph: " + str(id))
		combined.stories[id] = graph.stories[id]
	var registered: Dictionary = registry.register_module(String(manifest.id), combined)
	if not registered.ok:
		return _fail("Module catalog validation failed: " + String(registered.error))
	var session = StorySession.new()
	var validated: Dictionary = session.configure(graph.stories, graph.get("exclusive_fact_groups", []))
	if not validated.ok:
		return _fail("Story graph validation failed: " + String(validated.error))
	var joined: Dictionary = registry.catalog()
	for id: String in graph.stories:
		var definition: Dictionary = graph.stories[id]
		if base_file.data.get("events", {}).has(definition.completion_event):
			return _fail("Module story reuses a base completion event: " + id)
		for node: Dictionary in definition.nodes.values():
			if node.type == "line" and String(node.speaker).begins_with("npc.") and not joined.npcs.has(node.speaker):
				return _fail("Story references an unknown NPC: " + String(node.speaker))
	var base_text := _read_csv(BASE_TRANSLATIONS)
	if not base_text.ok:
		return base_text
	var translations := {"en": {}, "zh_CN": {}}
	var seen_files := {}
	for relative: Variant in manifest.translations:
		var resolved := _resolve_path(root, relative)
		if not resolved.ok:
			return resolved
		var identity: String = String(resolved.path).to_lower()
		if seen_files.has(identity):
			return _fail("Translation file is listed more than once")
		seen_files[identity] = true
		var parsed := _read_csv(resolved.path)
		if not parsed.ok:
			return parsed
		for key: String in parsed.translations.en:
			if translations.en.has(key) or base_text.translations.en.has(key):
				return _fail("Duplicate or base-owned translation key: " + key)
			for locale: String in LOCALES:
				translations[locale][key] = parsed.translations[locale][key]
	var keys: Dictionary = {}
	var text_error := _collect_keys(combined, keys)
	if not text_error.is_empty():
		return _fail(text_error)
	for key: String in keys:
		for locale: String in LOCALES:
			if not translations[locale].has(key) and not base_text.translations[locale].has(key):
				return _fail("Missing translation " + locale + ": " + key)
	var missing_art: Array[Dictionary] = []
	for id: String in content.cards:
		var art_result := _check_art(id, "art_path", content.cards[id].get("art_path", ""), missing_art)
		if not art_result.ok:
			return art_result
	for id: String in content.npcs:
		var art_result := _check_art(id, "portrait_path", content.npcs[id].get("portrait_path", ""), missing_art)
		if not art_result.ok:
			return art_result
	return {"ok": true, "error": "", "content": content.duplicate(true), "stories": graph.stories.duplicate(true), "exclusive_fact_groups": graph.get("exclusive_fact_groups", []).duplicate(true), "translations_by_locale": translations, "manifest": manifest.duplicate(true), "missing_art": missing_art}


func install_translations(bundle: Dictionary) -> Dictionary:
	if not _installed.is_empty():
		return _fail("This bundle instance already owns installed translations")
	if bundle.get("ok") != true or not bundle.get("manifest") is Dictionary or bundle.manifest.get("id") != "chapter_01":
		return _fail("A validated module bundle is required")
	var values: Variant = bundle.get("translations_by_locale")
	if not values is Dictionary or values.size() != LOCALES.size():
		return _fail("Invalid translations by locale")
	var base := _read_csv(BASE_TRANSLATIONS)
	if not base.ok:
		return base
	for locale: String in LOCALES:
		if not values.get(locale) is Dictionary:
			return _fail("Missing translation locale: " + locale)
	if values.en.size() != values.zh_CN.size() or values.en.is_empty():
		return _fail("Locale message sets do not match")
	for key: Variant in values.en:
		if not _key_valid(key) or base.translations.en.has(key):
			return _fail("Invalid or base-owned installation key")
		for locale: String in LOCALES:
			if not values[locale].get(key) is String or String(values[locale][key]).strip_edges().is_empty():
				return _fail("Installation has an empty or missing translation")
	var candidates: Array[Translation] = []
	for locale: String in LOCALES:
		var translation := Translation.new()
		translation.locale = locale
		for key: String in values[locale]:
			translation.add_message(StringName(key), StringName(values[locale][key]))
		candidates.append(translation)
	for translation: Translation in candidates:
		TranslationServer.add_translation(translation)
	_installed = candidates
	return {"ok": true, "error": "", "installed": _installed.size()}


func uninstall_translations() -> Dictionary:
	var count := _installed.size()
	for translation: Translation in _installed:
		TranslationServer.remove_translation(translation)
	_installed.clear()
	return {"ok": true, "error": "", "removed": count}


static func _resolve_path(root: String, value: Variant) -> Dictionary:
	if not value is String or value.is_empty() or value != value.strip_edges() or value.length() > 1024:
		return _fail("Invalid module-relative path")
	var relative: String = value.replace("\\", "/")
	if relative.is_absolute_path() or relative.begins_with("/") or ":" in relative:
		return _fail("Absolute paths are not permitted inside a module manifest")
	var parts := relative.split("/", true)
	var cursor := root
	for part: String in parts:
		if part.is_empty() or part in [".", ".."] or part != part.strip_edges() or part.ends_with("."):
			return _fail("Module path traversal or ambiguous path component")
		for character: String in part:
			if character in ["*", "?", "\"", "<", ">", "|"] or character.unicode_at(0) < 32:
				return _fail("Module path contains an invalid character")
		var folder := DirAccess.open(cursor)
		if folder == null:
			return _fail("Module path parent cannot be opened")
		if folder.is_link(part):
			return _fail("Module paths cannot follow filesystem links")
		cursor = cursor.path_join(part)
	var absolute := cursor.simplify_path().replace("\\", "/")
	if not absolute.to_lower().begins_with(root.to_lower().trim_suffix("/") + "/"):
		return _fail("Module path is outside its manifest directory")
	return {"ok": true, "path": absolute, "error": ""}


static func _read_text(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("Cannot read file: " + path)
	if file.get_length() <= 0 or file.get_length() > MAX_FILE_BYTES:
		file.close()
		return _fail("Empty or oversized module file: " + path)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.size() >= 3 and bytes[0] == 0xef and bytes[1] == 0xbb and bytes[2] == 0xbf:
		bytes = bytes.slice(3)
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		return _fail("File is not valid UTF-8: " + path)
	if text.begins_with(String.chr(0xfeff)):
		text = text.substr(1)
	return {"ok": true, "text": text, "error": ""}


static func _read_json(path: String) -> Dictionary:
	var source := _read_text(path)
	if not source.ok:
		return source
	var parser := JSON.new()
	if parser.parse(source.text) != OK or not parser.data is Dictionary:
		return _fail("Invalid JSON object: " + path)
	var duplicate := _duplicate_json_key(source.text)
	if not duplicate.is_empty():
		return _fail("Duplicate JSON key in " + path + ": " + duplicate)
	return {"ok": true, "data": parser.data, "error": ""}


static func _duplicate_json_key(source: String) -> String:
	var objects: Array[Dictionary] = []
	var index := 0
	while index < source.length():
		var character := source.substr(index, 1)
		if character == "{":
			objects.append({})
		elif character == "}":
			objects.pop_back()
		elif character == "\"":
			var start := index
			index += 1
			while index < source.length():
				character = source.substr(index, 1)
				if character == "\\":
					index += 2
					continue
				if character == "\"":
					break
				index += 1
			var following := index + 1
			while following < source.length() and source.substr(following, 1) in [" ", "\t", "\r", "\n"]:
				following += 1
			if following < source.length() and source.substr(following, 1) == ":":
				var key: String = JSON.parse_string(source.substr(start, index - start + 1))
				if objects.back().has(key):
					return key if not key.is_empty() else "<empty>"
				objects.back()[key] = true
		index += 1
	return ""


static func _read_csv(path: String) -> Dictionary:
	var source := _read_text(path)
	if not source.ok:
		return source
	var parsed := _parse_csv(source.text)
	if not parsed.ok:
		return _fail("Invalid CSV in " + path + ": " + String(parsed.error))
	var rows: Array = parsed.rows
	if rows.is_empty():
		return _fail("Translation CSV has no header")
	var header: Array = rows[0]
	if header.size() != 3 or not header.has("en") or not header.has("zh_CN") or (not header.has("key") and not header.has("keys")):
		return _fail("Translation CSV header must contain key or keys, en, and zh_CN")
	var key_index := header.find("key") if header.has("key") else header.find("keys")
	var values := {"en": {}, "zh_CN": {}}
	for index in range(1, rows.size()):
		var row: Array = rows[index]
		if row.size() != header.size():
			return _fail("Translation CSV column count differs at row " + str(index + 1))
		var key: String = row[key_index]
		if not _key_valid(key) or values.en.has(key):
			return _fail("Invalid or duplicate translation key at row " + str(index + 1))
		for locale: String in LOCALES:
			var text: String = row[header.find(locale)]
			if text.strip_edges().is_empty() or String.chr(0xfeff) in text:
				return _fail("Missing or contaminated translation: " + key + " / " + locale)
			values[locale][key] = text
	return {"ok": true, "translations": values, "error": ""}


static func _parse_csv(source: String) -> Dictionary:
	var rows: Array = []
	var row: Array = []
	var field := ""
	var quoted := false
	var closed := false
	var active := false
	var index := 0
	while index < source.length():
		var character := source.substr(index, 1)
		if quoted:
			if character == "\"":
				if index + 1 < source.length() and source.substr(index + 1, 1) == "\"":
					field += "\""
					index += 1
				else:
					quoted = false
					closed = true
			elif character == "\r":
				field += "\n"
				if index + 1 < source.length() and source.substr(index + 1, 1) == "\n":
					index += 1
			else:
				field += character
		elif character == ",":
			row.append(field)
			field = ""
			closed = false
			active = true
		elif character in ["\n", "\r"]:
			if active:
				row.append(field)
				rows.append(row)
			row = []
			field = ""
			closed = false
			active = false
			if character == "\r" and index + 1 < source.length() and source.substr(index + 1, 1) == "\n":
				index += 1
		elif closed:
			return _fail("Characters occur after a closing quote")
		elif character == "\"":
			if not field.is_empty():
				return _fail("Quote occurs inside an unquoted field")
			quoted = true
			active = true
		else:
			field += character
			active = true
		index += 1
	if quoted:
		return _fail("Quoted field is not terminated")
	if active:
		row.append(field)
		rows.append(row)
	return {"ok": true, "rows": rows, "error": ""}


static func _collect_keys(value: Variant, found: Dictionary, depth: int = 0) -> String:
	if depth > 32:
		return "Content text references exceed nesting limit"
	if value is Dictionary:
		for key: Variant in value:
			if not key is String:
				return "Content field name is not a string"
			if key in ["name_key", "detail_key", "category_key", "description_key", "open_name_key", "open_detail_key", "text_key"]:
				if not _key_valid(value[key]):
					return "Invalid localized content reference: " + key
				found[value[key]] = true
			var error := _collect_keys(value[key], found, depth + 1)
			if not error.is_empty():
				return error
	elif value is Array:
		for item: Variant in value:
			var error := _collect_keys(item, found, depth + 1)
			if not error.is_empty():
				return error
	return ""


static func _check_art(id: String, field: String, value: Variant, missing: Array[Dictionary]) -> Dictionary:
	if not value is String:
		return _fail("Art path is not a string: " + id)
	if value.is_empty():
		missing.append({"definition_id": id, "field": field, "path": "", "reason": "unassigned"})
		return {"ok": true, "error": ""}
	if not value.begins_with("res://assets/") or ".." in value.replace("\\", "/").split("/") or "\\" in value:
		return _fail("Art path is outside the asset namespace: " + id)
	if not ResourceLoader.exists(value) and not FileAccess.file_exists(value):
		missing.append({"definition_id": id, "field": field, "path": value, "reason": "not_found"})
	return {"ok": true, "error": ""}


static func _key_valid(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 240:
		return false
	var regex := RegEx.new()
	return regex.compile("^[A-Z][A-Z0-9_]*$") == OK and regex.search(value) != null


static func _version_one(value: Variant) -> bool:
	return (value is int or value is float) and value == 1


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}
