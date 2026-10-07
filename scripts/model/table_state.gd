class_name TableState
extends RefCounted

const CARD_SIZE := Vector2(168.0, 236.0)
const STACK_STEP := 26.0
const MAX_STACK := 20
const MAX_CARDS := 160
const SIGIL_LOCK_META := &"module_recipe_runtime_locks"
const CONTEXT_REGISTRY := preload("res://scripts/content/module_registry.gd")
const BOARD_SCALE := 0.6454972243679028
const WORLD_BOUNDS := Rect2(Vector2(-1600.0, -1100.0) * BOARD_SCALE, Vector2(3200.0, 2200.0) * BOARD_SCALE)
const CATEGORIES := {&"hero": &"character", &"shop": &"location", &"supply": &"source", &"goods": &"item", &"coin": &"currency", &"customer": &"character", &"blank": &"placeholder", &"forest": &"location", &"messenger": &"character", &"tree": &"resource", &"town_gate": &"location"}

var stacks: Dictionary = {}
var cards: Dictionary = {}
var transaction_receipts: Dictionary = {}
var next_card_id := 1
var next_stack_id := 1
var next_z := 1
var _has_catalog_context := false
var _catalog_context: Dictionary = {}
var _catalog_modules: Array[String] = []
var _catalog_kinds: Dictionary = {}


func configure_catalog(catalog: Dictionary, module_ids: Array[String]) -> Dictionary:
	if not cards.is_empty() or not stacks.is_empty() or not transaction_receipts.is_empty() or next_card_id != 1 or next_stack_id != 1 or next_z != 1:
		return {"ok": false, "error": "Catalog configuration requires an unused empty table"}
	var registry := CONTEXT_REGISTRY.new()
	var checked: Dictionary = registry.validate_context(catalog, module_ids)
	if not checked.ok:
		return checked
	var kinds := {}
	for id: String in checked.data.cards:
		kinds[String(checked.data.cards[id].kind)] = id
	_catalog_context = checked.data.duplicate(true)
	_catalog_modules.assign(module_ids)
	_catalog_modules.sort()
	_catalog_kinds = kinds
	_has_catalog_context = true
	return {"ok": true, "error": ""}


func content_card_definition(id: String) -> Dictionary:
	if not _has_catalog_context:
		return ContentCatalog.card_definition(id)
	return _catalog_context.cards.get(id, {}).duplicate(true)


func content_id_for_kind(kind: StringName) -> String:
	if not _has_catalog_context:
		return ContentCatalog.card_id_for_kind(kind)
	return String(_catalog_kinds.get(String(kind), ""))


func content_module_ids() -> Array[String]:
	var result: Array[String] = []
	result.assign(_catalog_modules if _has_catalog_context else ContentCatalog.enabled_module_ids())
	result.sort()
	return result


func content_card_ids() -> Array[String]:
	if not _has_catalog_context:
		return ContentCatalog.card_ids()
	var result: Array[String] = []
	result.assign(_catalog_context.cards.keys())
	return result


func content_npc_definition(id: String) -> Dictionary:
	if not _has_catalog_context:
		return ContentCatalog.npc_definition(id)
	return _catalog_context.npcs.get(id, {}).duplicate(true)


func content_npc_ids() -> Array[String]:
	if not _has_catalog_context:
		return ContentCatalog.npc_ids()
	var result: Array[String] = []
	result.assign(_catalog_context.npcs.keys())
	return result


func fork_empty() -> TableState:
	var result := TableState.new()
	if _has_catalog_context:
		result._has_catalog_context = true
		result._catalog_context = _catalog_context.duplicate(true)
		result._catalog_modules.assign(_catalog_modules)
		result._catalog_kinds = _catalog_kinds.duplicate()
	return result


func seed() -> void:
	stacks.clear()
	cards.clear()
	create_blank(Vector2(-370, -115), 1)
	create_blank(Vector2(-165, -155), 3)
	create_blank(Vector2(55, -90), 2)
	create_blank(Vector2(270, -160), 1)
	create_blank(Vector2(-270, 100), 2)


func create_blank(at: Vector2, count: int = 1) -> String:
	return create_typed(&"blank", at, count)


func create_typed(kind: StringName, at: Vector2, count: int = 1) -> String:
	return create_defined(content_id_for_kind(kind), at, count)


func create_defined(definition_id: String, at: Vector2, count: int = 1) -> String:
	var definition := content_card_definition(definition_id)
	if definition.is_empty() or count < 1 or count > MAX_STACK or card_count() + count > MAX_CARDS:
		return ""
	if definition.get("unique", false) or definition_id in ["card.hero", "card.messenger"]:
		if count != 1:
			return ""
		for existing: String in cards:
			if definition_id_for_card(existing) == definition_id:
				return ""
	var ids: Array[String] = []
	for index in count:
		var id := _register_card(StringName(definition.kind), &"board")
		cards[id].metadata.definition_id = definition_id
		if not String(definition.get("module_id", "")).is_empty():
			cards[id].metadata.module_id = String(definition.module_id)
		ids.append(id)
	return _create_stack(ids, at)


func materialize_reserved_npc(instance_id: String, definition_id: String, npc_id: String, at: Vector2) -> bool:
	var definition := content_card_definition(definition_id)
	if card_count() >= MAX_CARDS:
		return false
	if cards.has(instance_id) or not instance_id.begins_with("card_") or not instance_id.trim_prefix("card_").is_valid_int():
		return false
	var serial := int(instance_id.trim_prefix("card_"))
	if serial <= 0 or serial >= next_card_id or definition.get("category", "") != "character":
		return false
	var reserved := false
	for receipt: Dictionary in transaction_receipts.values():
		if instance_id in receipt.get("removed_ids", []) or instance_id in receipt.get("input_instance_ids", []):
			return false
		reserved = reserved or instance_id in receipt.get("created_ids", [])
	if not reserved:
		return false
	if content_npc_definition(npc_id).get("card_id", "") != definition_id or not WORLD_BOUNDS.encloses(Rect2(at, CARD_SIZE)):
		return false
	for card_id: String in cards:
		if cards[card_id].metadata.get("npc_id", "") == npc_id:
			return false
	cards[instance_id] = {"kind": StringName(definition.kind), "category": &"character", "zone": &"board",
		"metadata": {"definition_id": definition_id, "module_id": definition.get("module_id", ""), "npc_id": npc_id}}
	if String(definition.get("module_id", "")).is_empty():
		cards[instance_id].metadata.erase("module_id")
	var stack_id := _create_stack([instance_id], at)
	settle_overlaps(stack_id)
	return true


func definition_id_for_card(instance_id: String) -> String:
	if not cards.has(instance_id):
		return ""
	var stored := String(cards[instance_id].metadata.get("definition_id", ""))
	return stored if not stored.is_empty() else content_id_for_kind(StringName(cards[instance_id].kind))


func replace_definition(instance_id: String, definition_id: String) -> bool:
	var definition := content_card_definition(definition_id)
	if not cards.has(instance_id) or definition.is_empty():
		return false
	var original_definition := definition_id_for_card(instance_id)
	if (cards[instance_id].get("zone") == &"bound" or "sigil" in content_card_definition(original_definition).get("tags", [])) and definition_id != original_definition:
		return false
	var bound: String = String(cards[instance_id].metadata.get("bound_sigil", ""))
	if not bound.is_empty() and (not cards.has(bound) or not sigil_definition_compatible(definition_id_for_card(bound), definition_id, self)):
		return false
	if definition.get("unique", false) or definition_id in ["card.hero", "card.messenger"]:
		for other: String in cards:
			if other != instance_id and definition_id_for_card(other) == definition_id:
				return false
	cards[instance_id].kind = StringName(definition.kind)
	cards[instance_id].category = StringName(definition.category)
	cards[instance_id].metadata.definition_id = definition_id
	if String(definition.get("module_id", "")).is_empty():
		cards[instance_id].metadata.erase("module_id")
	else:
		cards[instance_id].metadata.module_id = String(definition.module_id)
	return true


func membership_revision_for_card(instance_id: String) -> int:
	return int(cards[instance_id].metadata.get("membership_revision", 0)) if cards.has(instance_id) else -1


func _revise_membership(ids: Array) -> void:
	for id: String in ids:
		if cards.has(id):
			cards[id].metadata.membership_revision = membership_revision_for_card(id) + 1


func create_queue_card(kind: StringName) -> String:
	if card_count() >= MAX_CARDS or kind.is_empty():
		return ""
	if _has_catalog_context and content_id_for_kind(kind).is_empty():
		return ""
	return _register_card(kind, &"queue")


func _register_card(kind: StringName, zone: StringName) -> String:
	var id := "card_%04d" % next_card_id
	next_card_id += 1
	var definition_id := content_id_for_kind(kind)
	var definition := content_card_definition(definition_id)
	var category := StringName(definition.get("category", ""))
	if category.is_empty():
		category = CATEGORIES.get(kind, &"item")
	var metadata := {}
	if not String(definition.get("module_id", "")).is_empty():
		metadata = {"definition_id": definition_id, "module_id": String(definition.module_id)}
	cards[id] = {"kind": kind, "category": category, "zone": zone, "metadata": metadata}
	return id


func card_kind(card_id: String) -> StringName:
	if not cards.has(card_id):
		return &""
	return StringName(cards[card_id].kind)


func remove_card(card_id: String) -> bool:
	if not cards.has(card_id):
		return false
	if cards[card_id].get("zone") == &"bound" or cards[card_id].metadata.has("bound_sigil"):
		return false
	if "sigil" in content_card_definition(definition_id_for_card(card_id)).get("tags", []):
		return false
	var stack := stack_for(card_id)
	if not stack.is_empty():
		_revise_membership(stacks[stack].cards)
		stacks[stack].cards.erase(card_id)
		if stacks[stack].cards.is_empty():
			stacks.erase(stack)
	cards.erase(card_id)
	return true


func _create_stack(ids: Array[String], at: Vector2) -> String:
	var id := "stack_%04d" % next_stack_id
	next_stack_id += 1
	stacks[id] = {"id": id, "cards": ids, "position": at, "z": next_z}
	next_z += 1
	move_stack(id, at)
	return id


func stack_for(card_id: String) -> String:
	for id: String in stacks:
		if card_id in stacks[id].cards:
			return id
	return ""


func card_position(card_id: String) -> Vector2:
	if cards.has(card_id) and cards[card_id].get("zone") == &"bound":
		var host := String(cards[card_id].metadata.get("bound_to", ""))
		var host_stack := stack_for(host)
		if not host_stack.is_empty():
			return stacks[host_stack].position + Vector2(0, stacks[host_stack].cards.find(host) * STACK_STEP)
	var id := stack_for(card_id)
	if id.is_empty():
		return Vector2.ZERO
	var entry: Dictionary = stacks[id]
	return entry.position + Vector2(0, entry.cards.find(card_id) * STACK_STEP)


func sorted_stacks() -> Array:
	var ordered := stacks.keys()
	ordered.sort_custom(func(a: String, b: String) -> bool: return stacks[a].z < stacks[b].z)
	return ordered


func raise_stack(id: String) -> void:
	if stacks.has(id):
		stacks[id].z = next_z
		next_z += 1


func take_from(card_id: String, whole: bool) -> String:
	var source := stack_for(card_id)
	if source.is_empty():
		return ""
	var entry: Dictionary = stacks[source]
	var index: int = entry.cards.find(card_id)
	if whole or index == 0:
		raise_stack(source)
		return source
	var moved: Array[String] = []
	_revise_membership(entry.cards)
	moved.assign(entry.cards.slice(index))
	entry.cards.resize(index)
	return _create_stack(moved, entry.position + Vector2(0, index * STACK_STEP))


func stack_size(id: String) -> Vector2:
	if not stacks.has(id):
		return CARD_SIZE
	return CARD_SIZE + Vector2(0, (stacks[id].cards.size() - 1) * STACK_STEP)


func stack_rect(id: String) -> Rect2:
	return Rect2(stacks[id].position, stack_size(id))


func clamp_position(at: Vector2, size: Vector2) -> Vector2:
	return at.clamp(WORLD_BOUNDS.position + Vector2.ONE * 20.0, WORLD_BOUNDS.end - size - Vector2.ONE * 20.0)


func move_stack(id: String, at: Vector2) -> void:
	if stacks.has(id):
		stacks[id].position = clamp_position(at, stack_size(id))


func can_merge(source: String, target: String) -> bool:
	return source != target and stacks.has(source) and stacks.has(target) and stacks[source].cards.size() + stacks[target].cards.size() <= MAX_STACK


func merge(source: String, target: String) -> bool:
	if not can_merge(source, target):
		return false
	_revise_membership(stacks[source].cards)
	_revise_membership(stacks[target].cards)
	stacks[target].cards.append_array(stacks[source].cards)
	stacks.erase(source)
	move_stack(target, stacks[target].position)
	raise_stack(target)
	return true


func settle_overlaps(fixed_id: String) -> void:
	if not stacks.has(fixed_id):
		return
	var probe_started := HitchProbe.stamp()
	var rectangles := {}
	for id: String in stacks:
		rectangles[id] = stack_rect(id).grow(9.0)
	var placed: Array[String] = [fixed_id]
	for id: String in sorted_stacks():
		if id == fixed_id:
			continue
		for attempt in 12:
			var overlap := false
			var a: Rect2 = rectangles[id]
			for obstacle: String in placed:
				var b: Rect2 = rectangles[obstacle]
				if not a.intersects(b):
					continue
				var shifts: Array[Vector2] = [Vector2(b.end.x - a.position.x, 0), Vector2(b.position.x - a.end.x, 0), Vector2(0, b.end.y - a.position.y), Vector2(0, b.position.y - a.end.y)]
				shifts.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.length_squared() < y.length_squared())
				for shift in shifts:
					var desired: Vector2 = stacks[id].position + shift
					if clamp_position(desired, stack_size(id)).is_equal_approx(desired):
						move_stack(id, desired)
						a = stack_rect(id).grow(9.0)
						rectangles[id] = a
						break
				overlap = true
			if not overlap:
				break
		placed.append(id)
	HitchProbe.record("table_settle_overlaps", probe_started)


func card_count() -> int:
	return cards.size()


func bind_sigil(sigil_id: String, host_id: String) -> bool:
	if not validate().is_empty() or not cards.has(sigil_id) or not cards.has(host_id) or sigil_id == host_id:
		return false
	if cards[sigil_id].zone != &"board" or cards[host_id].zone != &"board" or cards[host_id].metadata.has("bound_sigil"):
		return false
	if cards[host_id].metadata.has("npc_id"):
		return false
	if sigil_instance_locked(sigil_id) or sigil_instance_locked(host_id):
		return false
	if not sigil_definition_compatible(definition_id_for_card(sigil_id), definition_id_for_card(host_id), self):
		return false
	var source := stack_for(sigil_id)
	_revise_membership(stacks[source].cards)
	stacks[source].cards.erase(sigil_id)
	if stacks[source].cards.is_empty():
		stacks.erase(source)
	cards[sigil_id].zone = &"bound"
	cards[sigil_id].metadata.bound_to = host_id
	cards[host_id].metadata.bound_sigil = sigil_id
	_revise_membership([host_id])
	return true


func unbind_sigil(sigil_id: String) -> bool:
	if not validate().is_empty() or not cards.has(sigil_id) or cards[sigil_id].zone != &"bound":
		return false
	var host_id := String(cards[sigil_id].metadata.bound_to)
	if sigil_instance_locked(sigil_id) or sigil_instance_locked(host_id):
		return false
	var at := card_position(host_id)
	cards[host_id].metadata.erase("bound_sigil")
	cards[sigil_id].metadata.erase("bound_to")
	cards[sigil_id].zone = &"board"
	_revise_membership([sigil_id, host_id])
	var ids: Array[String] = [sigil_id]
	_create_stack(ids, at)
	return true


func sigil_instance_locked(instance_id: String) -> bool:
	var locks: Variant = get_meta(SIGIL_LOCK_META, {})
	if not locks is Dictionary:
		return true
	if not locks.has(instance_id):
		return false
	var lock: Variant = locks[instance_id]
	if not lock is Dictionary or not lock.get("owner") is WeakRef:
		return true
	return lock.owner.get_ref() != null


static func sigil_definition_compatible(sigil_definition_id: String, host_definition_id: String, context_table: TableState = null) -> bool:
	var sigil := context_table.content_card_definition(sigil_definition_id) if context_table != null else ContentCatalog.card_definition(sigil_definition_id)
	var host := context_table.content_card_definition(host_definition_id) if context_table != null else ContentCatalog.card_definition(host_definition_id)
	if sigil.is_empty() or host.is_empty():
		return false
	var sigil_tags: Array = sigil.get("tags", [])
	var host_tags: Array = host.get("tags", [])
	if "sigil" not in sigil_tags or not sigil.get("unique", false) or not sigil.get("protected", false) or sigil.get("sellable", true):
		return false
	if sigil.get("category") != "item" or "sigil" in host_tags or host_definition_id == "card.hero":
		return false
	if host.get("category") == "location":
		if "facility" not in host_tags:
			return false
	elif host.get("category") not in ["item", "resource"]:
		return false
	var npcs := context_table.content_npc_ids() if context_table != null else ContentCatalog.npc_ids()
	for npc_id: String in npcs:
		var npc := context_table.content_npc_definition(npc_id) if context_table != null else ContentCatalog.npc_definition(npc_id)
		if npc.get("card_id") == host_definition_id:
			return false
	for tag: String in sigil_tags:
		if tag not in ["sigil", "conserved"] and (tag + "_compatible") in host_tags:
			return true
	return false


func binding_error() -> String:
	var definitions := {}
	for id: String in cards:
		var entry: Variant = cards[id]
		if not entry is Dictionary or not entry.get("metadata") is Dictionary:
			return "Invalid binding card metadata: " + id
		var metadata: Dictionary = entry.metadata
		for field: String in ["definition_id", "bound_to", "bound_sigil"]:
			if metadata.has(field) and not metadata[field] is String:
				return "Invalid binding reference type: " + id
		var definition_id := definition_id_for_card(id)
		var definition := content_card_definition(definition_id)
		var kind_definition := content_card_definition(content_id_for_kind(StringName(entry.get("kind", ""))))
		if "sigil" in kind_definition.get("tags", []) and kind_definition.get("id") != definition_id:
			return "Sigil identity hidden by metadata: " + id
		var is_sigil: bool = "sigil" in definition.get("tags", [])
		if is_sigil:
			if definitions.has(definition_id):
				return "Duplicate sigil instance: " + definition_id
			definitions[definition_id] = id
			if not definition.get("unique", false) or not definition.get("protected", false) or definition.get("sellable", true):
				return "Sigil definition lacks conservation: " + id
			if entry.get("zone") not in [&"board", &"bound"]:
				return "Sigil outside board or binding zone: " + id
		if is_sigil or metadata.has("bound_sigil"):
			if String(entry.get("kind", "")) != String(definition.get("kind", "")) or String(entry.get("category", "")) != String(definition.get("category", "")):
				return "Binding instance identity mismatch: " + id
		if entry.get("zone") == &"bound":
			if not is_sigil or metadata.has("bound_sigil") or not metadata.get("bound_to") is String:
				return "Invalid bound sigil: " + id
			var host_id: String = metadata.bound_to
			if host_id == id or not cards.has(host_id) or not cards[host_id] is Dictionary or not cards[host_id].get("metadata") is Dictionary:
				return "Missing sigil host: " + id
			var host: Dictionary = cards[host_id]
			if host.get("zone") != &"board" or not host.metadata.get("bound_sigil") is String or host.metadata.bound_sigil != id or host.metadata.has("bound_to") or host.metadata.has("npc_id"):
				return "Sigil host reverse reference mismatch: " + id
			if not sigil_definition_compatible(definition_id, definition_id_for_card(host_id), self):
				return "Incompatible sigil host: " + id
		elif metadata.has("bound_to"):
			return "Unbound card has a host reference: " + id
		if metadata.has("bound_sigil"):
			if entry.get("zone") != &"board" or not metadata.bound_sigil is String or not cards.has(metadata.bound_sigil):
				return "Invalid host sigil reference: " + id
			var bound: Variant = cards[metadata.bound_sigil]
			if not bound is Dictionary or not bound.get("metadata") is Dictionary or bound.get("zone") != &"bound" or not bound.metadata.get("bound_to") is String or bound.metadata.bound_to != id:
				return "Host sigil reverse reference mismatch: " + id
	return ""


func snapshot() -> Dictionary:
	return {"stacks": stacks.duplicate(true), "cards": cards.duplicate(true), "transaction_receipts": transaction_receipts.duplicate(true), "next_card_id": next_card_id, "next_stack_id": next_stack_id, "next_z": next_z}


func restore(data: Dictionary) -> void:
	stacks = data.stacks.duplicate(true)
	cards = data.cards.duplicate(true)
	transaction_receipts = data.get("transaction_receipts", {}).duplicate(true)
	next_card_id = maxi(next_card_id, data.next_card_id)
	next_stack_id = maxi(next_stack_id, data.next_stack_id)
	next_z = maxi(next_z, data.next_z)


func validate() -> String:
	if cards.size() > MAX_CARDS:
		return "Card limit exceeded"
	for id: Variant in cards:
		if not id is String or not cards[id] is Dictionary:
			return "Invalid card entry"
		var card: Dictionary = cards[id]
		for field: String in ["kind", "zone"]:
			if not card.get(field) is String and not card.get(field) is StringName:
				return "Invalid card field type: " + field
		if not card.get("metadata") is Dictionary:
			return "Invalid card metadata: " + id
		if _has_catalog_context:
			if card.metadata.has("definition_id") and not card.metadata.definition_id is String:
				return "Invalid context definition reference: " + id
			var definition := content_card_definition(definition_id_for_card(id))
			if definition.is_empty() or String(card.kind) != String(definition.kind) or str(card.get("category", "")) != String(definition.category):
				return "Card does not match table catalog: " + id
			if str(card.metadata.get("module_id", "")) != String(definition.get("module_id", "")):
				return "Card module does not match table catalog: " + id
	var seen := {}
	for id: String in stacks:
		var entry: Dictionary = stacks[id]
		if entry.cards.is_empty() or entry.cards.size() > MAX_STACK:
			return "Invalid stack size: " + id
		for card: String in entry.cards:
			if seen.has(card):
				return "Duplicate card: " + card
			if not cards.has(card):
				return "Unregistered card: " + card
			if cards[card].get("zone", &"") != &"board":
				return "Non-board card in stack: " + card
			seen[card] = true
		if not WORLD_BOUNDS.encloses(stack_rect(id)):
			return "Stack outside bounds: " + id
	for card: String in cards:
		var entry: Dictionary = cards[card]
		if not entry.has("kind") or StringName(entry.kind).is_empty():
			return "Missing card kind: " + card
		if not entry.get("metadata") is Dictionary:
			return "Invalid card metadata: " + card
		if entry.get("zone", &"") == &"queue":
			if seen.has(card):
				return "Queue card in stack: " + card
		elif entry.get("zone", &"") == &"bound":
			if seen.has(card):
				return "Bound card in stack: " + card
		elif entry.get("zone", &"") != &"board" or not seen.has(card):
			return "Card outside a valid zone: " + card
	return binding_error()
