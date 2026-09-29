class_name ModuleRegistry
extends RefCounted

const SECTIONS := ["cards", "recipes", "npcs", "stories", "events"]
const CATEGORIES := ["character", "location", "source", "item", "currency", "placeholder", "resource"]
const BASE_PROTECTED := ["card.hero", "card.messenger", "card.forest", "card.tree", "card.town_gate", "card.shop"]

var _base: Dictionary = {}
var _modules: Dictionary = {}
var _catalog: Dictionary = {}
var _kind_index: Dictionary = {}


func configure_base(data: Dictionary) -> Dictionary:
	var candidate := _merge(data, {})
	if not candidate.ok:
		return candidate
	_base = data.duplicate(true)
	_modules.clear()
	_commit(candidate.data)
	return {"ok": true, "error": ""}


func register_module(module_id: String, data: Dictionary) -> Dictionary:
	if _base.is_empty():
		return _fail("Base catalog is not configured")
	if not _matches(module_id, "^[a-z][a-z0-9_]*$") or data.get("module_id") != module_id:
		return _fail("Module ID is invalid")
	if _modules.has(module_id):
		return _fail("Module is already registered")
	if not _integer(data.get("version"), 1, 1):
		return _fail("Module version is unsupported")
	for section: String in ["cards", "recipes", "npcs"]:
		if not data.get(section) is Dictionary:
			return _fail("Missing module section: " + section)
	for id: Variant in data.cards:
		var definition: Variant = data.cards[id]
		if not definition is Dictionary or definition.get("module_id") != module_id:
			return _fail("Card ownership is invalid")
		for flag: String in ["unique", "protected", "sellable"]:
			if not definition.get(flag) is bool:
				return _fail("Card flag is invalid: " + flag)
		if definition.unique and not definition.protected:
			return _fail("Unique cards must be protected")
		if definition.protected and definition.sellable:
			return _fail("Protected cards cannot be sold")
	var next_modules := _modules.duplicate(true)
	next_modules[module_id] = data.duplicate(true)
	var candidate := _merge(_base, next_modules)
	if not candidate.ok:
		return candidate
	_modules = next_modules
	_commit(candidate.data)
	return {"ok": true, "error": ""}


func unregister_module(module_id: String, live_definition_ids: Array = []) -> Dictionary:
	if not _modules.has(module_id):
		return _fail("Module is not registered")
	var owned: Dictionary = _modules[module_id].get("cards", {})
	for id: Variant in live_definition_ids:
		if owned.has(id):
			return _fail("Module still owns live card instances")
	var next_modules := _modules.duplicate(true)
	next_modules.erase(module_id)
	var candidate := _merge(_base, next_modules)
	if not candidate.ok:
		return candidate
	_modules = next_modules
	_commit(candidate.data)
	return {"ok": true, "error": ""}


func catalog() -> Dictionary:
	return _catalog.duplicate(true)


# 验证已经合并的目录快照，不更改当前注册表，也不注册到全局目录。
func validate_context(data: Dictionary, module_ids: Array[String]) -> Dictionary:
	if not _plain_context(data) or not _integer(data.get("version"), 1, 1):
		return _fail("Invalid context catalog structure")
	for section: String in ["cards", "recipes", "npcs"]:
		if not data.get(section) is Dictionary:
			return _fail("Missing context section: " + section)
	var modules := {}
	for id: String in module_ids:
		if not _matches(id, "^[a-z][a-z0-9_]*$") or modules.has(id):
			return _fail("Invalid or duplicate context module ID")
		modules[id] = true
	for value: Variant in data.cards.values():
		if not value is Dictionary:
			return _fail("Invalid context card")
		if value.has("module_id"):
			if not value.module_id is String or not modules.has(value.module_id):
				return _fail("Context card has undeclared module ownership")
			for flag: String in ["unique", "protected", "sellable"]:
				if not value.get(flag) is bool:
					return _fail("Invalid context card flag: " + flag)
			if (value.unique and not value.protected) or (value.protected and value.sellable):
				return _fail("Inconsistent context card protection")
	return _merge(data, {})


static func _plain_context(value: Variant, depth: int = 0) -> bool:
	if depth > 40:
		return false
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _plain_context(value[key], depth + 1):
				return false
		return true
	if value is Array:
		for item: Variant in value:
			if not _plain_context(item, depth + 1):
				return false
		return true
	if value is float:
		return is_finite(value)
	return value == null or value is bool or value is int or value is String


func module_ids() -> Array:
	return _modules.keys()


func id_for_kind(kind: StringName) -> String:
	return String(_kind_index.get(String(kind), ""))


func definition(section: String, id: String) -> Dictionary:
	var values: Dictionary = _catalog.get(section, {})
	var value: Dictionary = values.get(id, {})
	return value.duplicate(true)


func _commit(data: Dictionary) -> void:
	_catalog = data.duplicate(true)
	_kind_index.clear()
	for id: String in _catalog.cards:
		_kind_index[String(_catalog.cards[id].kind)] = id


func _merge(base: Dictionary, modules: Dictionary) -> Dictionary:
	var joined: Dictionary = {"version": 1}
	for section: String in SECTIONS:
		if base.has(section) and not base[section] is Dictionary:
			return _fail("Base section is invalid: " + section)
		joined[section] = base.get(section, {}).duplicate(true)
	for module_id: String in modules:
		var module: Dictionary = modules[module_id]
		for section: String in SECTIONS:
			if module.has(section) and not module[section] is Dictionary:
				return _fail("Module section is invalid: " + section)
			for id: Variant in module.get(section, {}):
				if joined[section].has(id):
					return _fail("Duplicate content ID: " + str(id))
				joined[section][id] = module[section][id].duplicate(true) if module[section][id] is Dictionary else module[section][id]
	var error := _validate_catalog(joined, modules)
	if not error.is_empty():
		return _fail(error)
	return {"ok": true, "data": joined, "error": ""}


func _validate_catalog(data: Dictionary, modules: Dictionary) -> String:
	var kinds: Dictionary = {}
	for id: Variant in data.cards:
		var card: Variant = data.cards[id]
		if not id is String or not _matches(id, "^card\\.[a-z0-9_.]+$") or not card is Dictionary or card.get("id") != id:
			return "Card identity is invalid"
		if not card.get("kind") is String or not _matches(card.kind, "^[a-z][a-z0-9_]*$"):
			return "Card kind is invalid: " + id
		if kinds.has(card.kind):
			return "Duplicate card kind: " + card.kind
		kinds[card.kind] = id
		if card.get("category") not in CATEGORIES or not _text_key(card.get("name_key")) or not _text_key(card.get("detail_key")):
			return "Card presentation reference is invalid: " + id
		if not card.get("art_path", "") is String or (not String(card.get("art_path", "")).is_empty() and not String(card.art_path).begins_with("res://assets/")):
			return "Card art path is invalid: " + id
		if not card.get("tags", []) is Array:
			return "Card tags are invalid: " + id
		for tag: Variant in card.get("tags", []):
			if not tag is String or not _matches(tag, "^[a-z][a-z0-9_]*$"):
				return "Card tag is invalid: " + id
	for id: Variant in data.npcs:
		var npc: Variant = data.npcs[id]
		if not id is String or not _matches(id, "^npc\\.[a-z0-9_.]+$") or not npc is Dictionary or npc.get("id") != id:
			return "NPC identity is invalid"
		if not data.cards.has(npc.get("card_id")) or data.cards[npc.card_id].category != "character":
			return "NPC card is missing or not a character: " + id
		if not _text_key(npc.get("name_key")) or not _text_key(npc.get("description_key")):
			return "NPC text reference is invalid: " + id
	var module_recipes: Dictionary = {}
	for module_id: String in modules:
		for id: Variant in modules[module_id].get("recipes", {}):
			module_recipes[id] = true
	for id: Variant in data.recipes:
		var recipe: Variant = data.recipes[id]
		if not id is String or not _matches(id, "^recipe\\.[a-z0-9_.]+$") or not recipe is Dictionary or recipe.get("id") != id:
			return "Recipe identity is invalid"
		if not _text_key(recipe.get("name_key")) or not _text_key(recipe.get("description_key")):
			return "Recipe text reference is invalid: " + id
		if recipe.has("duration") and not _number(recipe.duration, 0.01, 3600.0):
			return "Recipe duration is invalid: " + id
		for section: String in ["inputs", "reusable", "outputs"]:
			if not recipe.get(section) is Array:
				return "Recipe card section is invalid: " + id
			var seen: Dictionary = {}
			for part: Variant in recipe[section]:
				if not part is Dictionary or not data.cards.has(part.get("card_id")) or not _integer(part.get("count"), 1, 20):
					return "Recipe has invalid card reference or quantity: " + id
				if seen.has(part.card_id):
					return "Recipe repeats a card entry: " + id
				seen[part.card_id] = true
				if module_recipes.has(id):
					var card: Dictionary = data.cards[part.card_id]
					if section == "inputs" and (card.get("protected", false) or part.card_id in BASE_PROTECTED or card.category in ["character", "location"]):
						return "Recipe consumes protected participant: " + id
					if section == "outputs":
						if part.card_id in BASE_PROTECTED or card.category == "character" or "sigil" in card.get("tags", []):
							return "Generic production cannot create protected roles or sigils: " + id
						if card.get("unique", false) and (card.category != "location" or "facility" not in card.get("tags", []) or int(part.count) != 1):
							return "Unique production requires one buildable facility: " + id
		var conditions: Variant = recipe.get("reusable_conditions", [])
		if not conditions is Array:
			return "Recipe reusable conditions must be an array: " + id
		var conditioned := {}
		for condition: Variant in conditions:
			if not condition is Dictionary or condition.size() != 2 or not condition.has("card_id") or not condition.has("bound_sigil"):
				return "Invalid reusable condition fields: " + id
			if not condition.card_id is String or not condition.bound_sigil is String or conditioned.has(condition.card_id):
				return "Invalid or duplicate reusable condition: " + id
			var reusable_count := 0
			for part: Dictionary in recipe.reusable:
				if part.card_id == condition.card_id:
					reusable_count += int(part.count)
			if reusable_count != 1 or not data.cards.has(condition.bound_sigil):
				return "Reusable condition lacks one known carrier or sigil: " + id
			var sigil: Dictionary = data.cards[condition.bound_sigil]
			var host: Dictionary = data.cards[condition.card_id]
			if "sigil" not in sigil.get("tags", []):
				return "Reusable condition target is not a sigil: " + id
			var compatible := false
			for sigil_type: String in ["ember", "flow", "ward"]:
				if sigil_type in sigil.get("tags", []) and (sigil_type + "_compatible") in host.get("tags", []):
					compatible = true
			if not compatible:
				return "Reusable condition sigil is incompatible: " + id
			conditioned[condition.card_id] = true
		if module_recipes.has(id):
			if recipe.get("action") not in ["craft", "transform"] or not recipe.has("duration"):
				return "Module recipe action is unsupported: " + id
			if recipe.inputs.is_empty() and recipe.reusable.is_empty():
				return "Module recipe has no participants: " + id
			for field: String in ["requires_facts", "grants_facts"]:
				if not recipe.get(field) is Array:
					return "Recipe fact section is invalid: " + id
				for fact: Variant in recipe[field]:
					if not fact is String or not _matches(fact, "^fact\\.[a-z0-9_.]+$"):
						return "Recipe fact ID is invalid: " + id
			if recipe.action == "transform":
				var transform: Variant = recipe.get("transform")
				if not transform is Dictionary or not data.cards.has(transform.get("from")) or not data.cards.has(transform.get("to")):
					return "Transform references unknown cards: " + id
				var source_card: Dictionary = data.cards[transform.from]
				var target_card: Dictionary = data.cards[transform.to]
				if transform.from in BASE_PROTECTED or source_card.category in ["character", "location", "currency"]:
					return "Generic transform cannot replace a protected role: " + id
				if bool(source_card.get("unique", false)) != bool(target_card.get("unique", false)) or bool(source_card.get("protected", false)) != bool(target_card.get("protected", false)):
					return "Transform changes identity protection: " + id
				var count := 0
				for part: Dictionary in recipe.reusable:
					if part.card_id == transform.from:
						count += int(part.count)
				if count != 1:
					return "Transform needs one reusable source: " + id
				for field: String in ["require_metadata", "set_metadata"]:
					var values: Variant = transform.get(field, {})
					if not values is Dictionary:
						return "Transform metadata is invalid: " + id
					for key: Variant in values:
						if key != "state" or not values[key] is String or String(values[key]).is_empty():
							return "Transform metadata field is not allowed: " + id
				if transform.from == transform.to and (transform.get("require_metadata", {}).get("state", "") == transform.get("set_metadata", {}).get("state", "") or not transform.get("require_metadata", {}).has("state") or not transform.get("set_metadata", {}).has("state")):
					return "Same-definition transform needs a state change: " + id
	return ""


static func _matches(value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func _text_key(value: Variant) -> bool:
	return value is String and _matches(value, "^[A-Z][A-Z0-9_]*$")


static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return _number(value, lower, upper) and float(value) == floorf(float(value))


static func _number(value: Variant, lower: float, upper: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error}
