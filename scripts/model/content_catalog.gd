class_name ContentCatalog
extends RefCounted

const DATA_PATH := "res://data/content.json"
const AFFECTION_MAX := 100
const AFFECTION_PER_ORDER := 1
const MODULE_REGISTRY_SCRIPT := preload("res://scripts/content/module_registry.gd")

static var _loaded := false
static var _data: Dictionary = {}
static var _base_data: Dictionary = {}
static var _registry: RefCounted
static var _revision := 0


static func content_generation() -> String:
	_ensure_loaded()
	return String(_base_data.get("content_generation", ""))


static func opening_definition() -> Dictionary:
	_ensure_loaded()
	return _base_data.get("opening", {}).duplicate(true)


static func runtime_rules() -> Dictionary:
	_ensure_loaded()
	return _base_data.get("runtime_rules", {}).duplicate(true)


static func initial_cards() -> Array:
	_ensure_loaded()
	return _base_data.get("initial_cards", []).duplicate(true)


static func card_id_for_kind(kind: StringName) -> String:
	_ensure_loaded()
	return String(_registry.id_for_kind(kind)) if _registry != null else ""


static func enable_module(module_id: String, content: Dictionary) -> Dictionary:
	_ensure_loaded()
	if _registry == null:
		return {"ok": false, "error": "Base catalog is unavailable"}
	var result: Dictionary = _registry.register_module(module_id, content)
	if result.ok:
		_data = _registry.catalog()
		_revision += 1
	return result


static func disable_module(module_id: String, live_definition_ids: Array = []) -> Dictionary:
	_ensure_loaded()
	if _registry == null:
		return {"ok": false, "error": "Base catalog is unavailable"}
	var result: Dictionary = _registry.unregister_module(module_id, live_definition_ids)
	if result.ok:
		_data = _registry.catalog()
		_revision += 1
	return result


static func enabled_module_ids() -> Array:
	_ensure_loaded()
	return _registry.module_ids() if _registry != null else []


static func snapshot_context() -> Dictionary:
	_ensure_loaded()
	var modules: Array[String] = []
	if _registry != null:
		modules.assign(_registry.module_ids())
	modules.sort()
	return {"catalog": _data.duplicate(true), "module_ids": modules}


static func base_snapshot_context() -> Dictionary:
	_ensure_loaded()
	return {"catalog": _base_data.duplicate(true), "module_ids": []}


static func content_revision() -> int:
	_ensure_loaded()
	return _revision


static func card_ids() -> Array[String]:
	return _ids("cards")


static func category_for_kind(kind: StringName) -> StringName:
	var definition := card_definition(card_id_for_kind(kind))
	return StringName(definition.get("category", ""))


static func card_definition(id: String) -> Dictionary:
	return _definition("cards", id)


static func recipe_definition(id: String) -> Dictionary:
	return _definition("recipes", id)


static func recipe_is_repeatable(id: String) -> bool:
	_ensure_loaded()
	var recipe: Dictionary = _data.get("recipes", {}).get(id, {})
	if recipe.is_empty():
		return false
	if recipe.has("repeatable"):
		return bool(recipe.repeatable)
	for output: Dictionary in recipe.get("outputs", []):
		var card: Dictionary = _data.get("cards", {}).get(output.card_id, {})
		if card.get("unique", false) or card.get("category", "") == "character":
			return false
	return true


static func npc_definition(id: String) -> Dictionary:
	return _definition("npcs", id)


static func story_definition(id: String) -> Dictionary:
	return _definition("stories", id)


static func event_definition(id: String) -> Dictionary:
	return _definition("events", id)


static func recipe_ids() -> Array[String]:
	return _ids("recipes")


static func npc_ids() -> Array[String]:
	return _ids("npcs")


static func shop_npc_ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in npc_ids():
		if npc_definition(id).get("card_id", "") == "card.customer":
			result.append(id)
	return result


static func recipe_for_action(action: StringName) -> String:
	_ensure_loaded()
	for id: String in _data.get("recipes", {}):
		if _data.recipes[id].get("action", "") == String(action):
			return id
	return ""


static func combination_recipe_for_cards(card_definition_ids: Array[String]) -> String:
	return _combination_recipe_for_cards(card_definition_ids,recipe_ids())


static func discovered_combination_recipe_for_cards(card_definition_ids: Array[String],discovered_recipe_ids: Array[String]) -> String:
	return _combination_recipe_for_cards(card_definition_ids,discovered_recipe_ids,true)


static func _combination_recipe_for_cards(card_definition_ids: Array[String],candidate_recipe_ids: Array[String], repeatable_only: bool = false) -> String:
	_ensure_loaded()
	if card_definition_ids.size()<2:
		return ""
	var actual := {}
	for card_id in card_definition_ids:
		actual[card_id] = int(actual.get(card_id,0))+1
	for recipe_id: String in candidate_recipe_ids:
		if not _data.get("recipes",{}).has(recipe_id):
			continue
		var recipe: Dictionary = _data.recipes[recipe_id]
		if repeatable_only and not recipe_is_repeatable(recipe_id):
			continue
		var required := {}
		for section in ["inputs","reusable"]:
			for entry: Dictionary in recipe.get(section,[]):
				var card_id := String(entry.get("card_id",""))
				if not card_id.is_empty():
					required[card_id] = int(required.get(card_id,0))+int(entry.get("count",1))
		var required_count := 0
		for amount: int in required.values():
			required_count += amount
		if required_count < 2:
			continue
		var compatible := true
		for card_id: String in actual:
			if int(actual[card_id])>int(required.get(card_id,0)):
				compatible = false
				break
		if compatible:
			return recipe_id
	return ""


static func _definition(section: String, id: String) -> Dictionary:
	_ensure_loaded()
	var definitions: Dictionary = _data.get(section, {})
	var definition: Dictionary = definitions.get(id, {})
	return definition.duplicate(true)


static func _ids(section: String) -> Array[String]:
	_ensure_loaded()
	var result: Array[String] = []
	for id: String in _data.get(section, {}):
		result.append(id)
	return result


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		push_error("Content catalog file is missing.")
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(DATA_PATH)) != OK:
		push_error("Content catalog JSON is invalid.")
		return
	if not json.data is Dictionary:
		push_error("Content catalog root must be a dictionary.")
		return
	for section: String in ["cards", "recipes", "npcs"]:
		if not json.data.get(section) is Dictionary:
			push_error("Content catalog section is missing: " + section)
			return
	var candidate: RefCounted = MODULE_REGISTRY_SCRIPT.new()
	var result: Dictionary = candidate.configure_base(json.data)
	if not result.ok:
		push_error("Content catalog validation failed: " + String(result.error))
		return
	_base_data = json.data.duplicate(true)
	_registry = candidate
	_data = candidate.catalog()
	_revision += 1
