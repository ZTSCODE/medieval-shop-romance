class_name PlayerProgress
extends RefCounted

signal changed

const COUNTER_MAX := 2147483647
const NPC_FIELDS := ["affection", "visits", "orders_served", "first_seen_day", "last_seen_day"]

var discovered_recipes: Array[String] = []
var npcs: Dictionary = {}
var chapter_relationships: Dictionary = {}


func discover_recipe(id: String) -> bool:
	if ContentCatalog.recipe_definition(id).is_empty() or id in discovered_recipes:
		return false
	discovered_recipes.append(id)
	changed.emit()
	return true


func meet_npc(id: String, day: int) -> void:
	if ContentCatalog.npc_definition(id).is_empty() or day < 1 or day > COUNTER_MAX:
		return
	if not npcs.has(id):
		npcs[id] = _new_npc_data(day)
	else:
		var entry: Dictionary = npcs[id]
		entry.visits = mini(int(entry.visits) + 1, COUNTER_MAX)
		entry.first_seen_day = mini(int(entry.first_seen_day), day)
		entry.last_seen_day = maxi(int(entry.last_seen_day), day)
	changed.emit()


func complete_order(id: String, day: int) -> void:
	if ContentCatalog.npc_definition(id).is_empty() or day < 1 or day > COUNTER_MAX:
		return
	if not npcs.has(id):
		npcs[id] = _new_npc_data(day)
	var entry: Dictionary = npcs[id]
	if int(entry.orders_served) >= int(entry.visits):
		return
	entry.orders_served = mini(int(entry.orders_served) + 1, COUNTER_MAX)
	entry.affection = mini(int(entry.affection) + ContentCatalog.AFFECTION_PER_ORDER, ContentCatalog.AFFECTION_MAX)
	entry.first_seen_day = mini(int(entry.first_seen_day), day)
	entry.last_seen_day = maxi(int(entry.last_seen_day), day)
	changed.emit()


func apply_chapter_relationships(projection: Dictionary) -> bool:
	if projection.get("ok") != true or not projection.get("npcs") is Dictionary:
		return false
	var visible: Dictionary = chapter_relationships.duplicate()
	var altered := false
	for id: String in npcs:
		if not projection.npcs.has(id):
			if visible.has(id):
				visible.erase(id)
				altered = true
			continue
		var projected: Dictionary = projection.npcs[id]
		if not projected.get("affection") is int:
			return false
		var record: Dictionary = npcs[id]
		var value := clampi(int(projected.affection), 0, ContentCatalog.AFFECTION_MAX)
		if int(record.affection) != value:
			record.affection = value
			altered = true
		if not visible.has(id) or visible[id] != projected:
			visible[id] = projected.duplicate(true)
			altered = true
	for id: String in visible.keys():
		if not npcs.has(id):
			visible.erase(id)
			altered = true
	if altered:
		chapter_relationships = visible
		changed.emit()
	return true


func to_data() -> Dictionary:
	return {"recipes": discovered_recipes.duplicate(), "npcs": npcs.duplicate(true)}


static func validate_data(data: Variant) -> String:
	if not data is Dictionary:
		return "Progress data must be a dictionary."
	if data.size() != 2 or not data.has("recipes") or not data.has("npcs"):
		return "Progress data fields are invalid."
	if not data.recipes is Array:
		return "Discovered recipes must be an array."
	if not data.npcs is Dictionary:
		return "NPC progress must be a dictionary."
	var seen: Dictionary = {}
	for id: Variant in data.recipes:
		if not id is String or ContentCatalog.recipe_definition(id).is_empty():
			return "Discovered recipe ID is unknown."
		if seen.has(id):
			return "Discovered recipe ID is duplicated."
		seen[id] = true
	for id: Variant in data.npcs:
		if not id is String or ContentCatalog.npc_definition(id).is_empty():
			return "NPC progress ID is unknown."
		var entry: Variant = data.npcs[id]
		if not entry is Dictionary or entry.size() != NPC_FIELDS.size():
			return "NPC progress fields are invalid."
		for field: String in NPC_FIELDS:
			if not entry.has(field) or not _is_integer(entry[field], 0, COUNTER_MAX):
				return "NPC progress value is invalid: " + field
		if not _is_integer(entry.affection, 0, ContentCatalog.AFFECTION_MAX):
			return "NPC affection is outside the allowed range."
		if int(entry.visits) < 1 or int(entry.orders_served) > int(entry.visits):
			return "NPC visit and order counts are inconsistent."
		if int(entry.first_seen_day) < 1 or int(entry.last_seen_day) < int(entry.first_seen_day):
			return "NPC visit dates are inconsistent."
	return ""


func restore(data: Variant) -> bool:
	if not validate_data(data).is_empty():
		return false
	var restored_recipes: Array[String] = []
	for id: String in data.recipes:
		restored_recipes.append(id)
	var restored_npcs: Dictionary = {}
	for id: String in data.npcs:
		var entry: Dictionary = {}
		for field: String in NPC_FIELDS:
			entry[field] = int(data.npcs[id][field])
		restored_npcs[id] = entry
	discovered_recipes = restored_recipes
	npcs = restored_npcs
	chapter_relationships.clear()
	changed.emit()
	return true


static func _new_npc_data(day: int) -> Dictionary:
	return {
		"affection": 0,
		"visits": 1,
		"orders_served": 0,
		"first_seen_day": day,
		"last_seen_day": day,
	}


static func _is_integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) and number >= minimum and number <= maximum
