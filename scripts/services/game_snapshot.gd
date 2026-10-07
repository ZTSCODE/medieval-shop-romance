class_name GameSnapshot
extends RefCounted

const ChapterSnapshotCodec = preload("res://scripts/content/chapter_snapshot.gd")

const STATE_VERSION := 8
const MAX_COUNTER := 1000000000
const LEGACY_CARD_SIZE := Vector2(128.0, 180.0)
const COMPACT_CARD_SIZE := Vector2(112.0, 184.0)
const LEGACY_WORLD_BOUNDS := Rect2(-1600.0, -1100.0, 3200.0, 2200.0)
const LEGACY_MIN_ZOOM := 0.25


static func capture(state: TableState, shop: ShopSession, day: DayCycle, camera: TableCamera, progress: PlayerProgress, opening: OpeningFlow = null, dialogue: DialogueFlow = null, identity: PlayerIdentity = null) -> Dictionary:
	var card_data := {}
	for id: String in state.cards:
		var entry: Dictionary = state.cards[id]
		card_data[id] = {
			"definition_id": ContentCatalog.card_id_for_kind(StringName(entry.kind)),
			"zone": String(entry.zone),
			"metadata": _plain(entry.metadata),
		}
	var stack_data := {}
	for id: String in state.stacks:
		var entry: Dictionary = state.stacks[id]
		var at: Vector2 = entry.position
		stack_data[id] = {"cards": entry.cards.duplicate(), "position": [at.x, at.y], "z": entry.z}
	# 存档保存逻辑镜头，不保存叙事取景或透视投影后的屏幕中心。
	var center := (camera.bounds.get_center() - camera.offset) / camera.zoom
	return {
		"state_version": STATE_VERSION,
		"content_generation": ContentCatalog.content_generation(),
		"table": {"cards": card_data, "stacks": stack_data, "next_card_id": state.next_card_id, "next_stack_id": state.next_stack_id, "next_z": state.next_z},
		"shop": {"is_open": shop.is_open, "customers": shop.customers.duplicate(), "arrival_remaining": shop.arrival_remaining, "arrivals_today": shop.arrivals_today, "sales_count": shop.sales_count, "next_ticket": shop.next_ticket},
		"day": {"day": day.day, "elapsed": day.elapsed, "seconds_per_day": day.seconds_per_day},
		"camera": {"zoom": camera.zoom, "center": [center.x, center.y]},
		"progress": progress.to_data(),
		"opening": opening.to_data() if opening != null else _inactive_opening(),
		"dialogue": dialogue.to_data() if dialogue != null else _inactive_dialogue(),
		"identity": identity.to_data() if identity != null else {"name": ""},
	}


static func decode(payload: Variant) -> Dictionary:
	if not payload is Dictionary:
		return _failure("Missing payload")
	if not payload.get("content_generation") is String or payload.content_generation != ContentCatalog.content_generation():
		return _failure("Save belongs to a different content generation", "SAVE_UNSUPPORTED_VERSION")
	if _integer(payload.get("state_version"), 9, 9):
		if payload.get("session_mode") != "chapter_01":
			return _failure("Unsupported session mode", "SAVE_UNSUPPORTED_VERSION")
		return ChapterSnapshotCodec.decode(payload)
	if not _integer(payload.get("state_version"), 1, STATE_VERSION):
		return _failure("Unsupported state version", "SAVE_UNSUPPORTED_VERSION")
	for field: String in ["table", "shop", "day", "camera", "progress"]:
		if not payload.get(field) is Dictionary:
			return _failure("Missing section: " + field)
	var day: Dictionary = payload.day
	if not _integer(day.get("day"), 1, MAX_COUNTER) or not _number(day.get("seconds_per_day"), 1.0, 3600.0):
		return _failure("Invalid day settings")
	if not _number(day.get("elapsed"), 0.0, float(day.seconds_per_day)) or float(day.elapsed) >= float(day.seconds_per_day):
		return _failure("Invalid day progress")
	var table_result := _decode_table(payload.table, int(payload.state_version))
	if not table_result.ok:
		return table_result
	var state: TableState = table_result.state
	var opening_data: Variant = payload.get("opening") if int(payload.state_version) >= 2 else _inactive_opening()
	var opening_error := OpeningFlow.validate_data(opening_data, state)
	if not opening_error.is_empty():
		return _failure("Invalid opening: " + opening_error)
	if opening_data.stage == "inactive" and not ContentCatalog.card_id_for_kind(&"shop").is_empty() and _count_kind(state, &"shop") != 1:
		return _failure("Missing required shop location")
	var shop_result := _validate_shop(payload.shop, state)
	if not shop_result.ok:
		return shop_result
	if ContentCatalog.card_ids().is_empty() and payload.shop.is_open:
		return _failure("Empty content cannot contain an active shop")
	if opening_data.stage != "inactive" and (payload.shop.is_open or not payload.shop.customers.is_empty()):
		return _failure("Opening cannot contain an active shop")
	var progress_error := PlayerProgress.validate_data(payload.progress)
	if not progress_error.is_empty():
		return _failure("Invalid journal: " + progress_error)
	for npc_id: String in payload.progress.npcs:
		var record: Dictionary = payload.progress.npcs[npc_id]
		if int(record.last_seen_day) > int(day.day):
			return _failure("NPC encounter is in the future")
	for customer: String in payload.shop.customers:
		var npc_id: String = String(state.cards[customer].metadata.npc_id)
		if not payload.progress.npcs.has(npc_id):
			return _failure("Waiting NPC is absent from journal")
	var dialogue_data: Variant = payload.get("dialogue") if int(payload.state_version) >= 3 else _inactive_dialogue()
	if int(payload.state_version) >= 3 and int(payload.state_version) < 5:
		dialogue_data = DialogueFlow.migrate_legacy_data(dialogue_data)
	var dialogue_error := DialogueFlow.validate_data(dialogue_data, state)
	if not dialogue_error.is_empty():
		return _failure("Invalid dialogue: " + dialogue_error)
	if not dialogue_data.active_npc_id.is_empty() and not payload.progress.npcs.has(dialogue_data.active_npc_id):
		return _failure("Dialogue NPC is absent from journal")
	var identity_data: Variant = payload.get("identity") if int(payload.state_version) >= 4 else {"name": ""}
	var identity_error := PlayerIdentity.validate_data(identity_data)
	if not identity_error.is_empty():
		return _failure("Invalid identity: " + identity_error)
	var camera: Dictionary = payload.camera.duplicate(true)
	var old_camera := int(payload.state_version) < 6
	if not _number(camera.get("zoom"), LEGACY_MIN_ZOOM if old_camera else TableCamera.MIN_ZOOM, TableCamera.MAX_ZOOM) or not _vector_array(camera.get("center")):
		return _failure("Invalid camera state")
	if old_camera:
		camera.zoom = clampf(float(camera.zoom), TableCamera.MIN_ZOOM, TableCamera.MAX_ZOOM)
		var old_center := Vector2(float(camera.center[0]), float(camera.center[1]))
		var limit := TableState.WORLD_BOUNDS.size * 0.225
		var migrated_center := old_center.clamp(-limit, limit)
		camera.center = [migrated_center.x, migrated_center.y]
	return {"ok": true, "session_mode": "legacy", "state": state, "shop": payload.shop.duplicate(true), "day": day.duplicate(true), "camera": camera.duplicate(true), "progress": payload.progress.duplicate(true), "opening": opening_data.duplicate(true), "dialogue": dialogue_data.duplicate(true), "identity": identity_data.duplicate(true), "onboarding": OnboardingGoals.sanitize(payload.get("onboarding")), "error_key": ""}


static func capture_chapter(state: TableState, day_data: Dictionary, camera_data: Dictionary, progress_data: Dictionary, opening_data: Dictionary, identity_data: Dictionary, checkpoint: Dictionary, director: Dictionary) -> Dictionary:
	return ChapterSnapshotCodec.capture(state, day_data, camera_data, progress_data, opening_data, identity_data, checkpoint, director)


static func _decode_table(raw: Dictionary, state_version: int = STATE_VERSION) -> Dictionary:
	if not raw.get("cards") is Dictionary or not raw.get("stacks") is Dictionary:
		return _failure("Invalid card registry")
	if raw.cards.size() > TableState.MAX_CARDS or raw.stacks.size() > TableState.MAX_CARDS:
		return _failure("Card capacity exceeded")
	for field: String in ["next_card_id", "next_stack_id", "next_z"]:
		if not _integer(raw.get(field), 1, MAX_COUNTER):
			return _failure("Invalid counter: " + field)
	var state := TableState.new()
	var largest_card := 0
	var largest_stack := 0
	var largest_z := 0
	var hero_count := 0
	for id: Variant in raw.cards:
		if not _instance_id(id, "card_"):
			return _failure("Invalid card instance ID")
		largest_card = maxi(largest_card, String(id).trim_prefix("card_").to_int())
		var entry: Variant = raw.cards[id]
		if not entry is Dictionary or not entry.get("definition_id") is String:
			return _failure("Invalid card definition reference")
		var definition := ContentCatalog.card_definition(entry.definition_id)
		if definition.is_empty():
			return _failure("Unknown card definition", "SAVE_UNSUPPORTED_VERSION")
		var kind: StringName = StringName(definition.get("kind", ""))
		# 类别以内容目录中的卡牌定义为准（目录加载时已校验），不依赖旧版写死的种类表。
		var category := StringName(definition.get("category", ""))
		if kind.is_empty() or category.is_empty():
			return _failure("Unsupported card kind")
		if entry.get("zone") not in ["board", "queue"] or not entry.get("metadata") is Dictionary or not _plain_is_valid(entry.metadata):
			return _failure("Invalid card metadata")
		if entry.zone == "queue":
			if kind != &"customer" or not _customer_metadata(entry.metadata):
				return _failure("Invalid waiting customer")
		elif kind == &"customer":
			return _failure("Customer is outside the queue")
		hero_count += int(kind == &"hero")
		state.cards[String(id)] = {"kind": kind, "category": category, "zone": StringName(entry.zone), "metadata": entry.metadata.duplicate(true)}
	if hero_count != (0 if ContentCatalog.card_ids().is_empty() else 1):
		return _failure("Missing required character")
	for id: Variant in raw.stacks:
		if not _instance_id(id, "stack_"):
			return _failure("Invalid stack instance ID")
		largest_stack = maxi(largest_stack, String(id).trim_prefix("stack_").to_int())
		var entry: Variant = raw.stacks[id]
		if not entry is Dictionary or not _vector_array(entry.get("position")) or not _integer(entry.get("z"), 1, MAX_COUNTER):
			return _failure("Invalid stack geometry")
		if not entry.get("cards") is Array or entry.cards.is_empty() or entry.cards.size() > TableState.MAX_STACK:
			return _failure("Invalid stack members")
		var members: Array[String] = []
		for card: Variant in entry.cards:
			if not card is String or not state.cards.has(card):
				return _failure("Stack references unknown card")
			members.append(card)
		largest_z = maxi(largest_z, int(entry.z))
		var position := Vector2(float(entry.position[0]), float(entry.position[1]))
		if state_version < 8:
			var old_card_size := LEGACY_CARD_SIZE if state_version < 4 else COMPACT_CARD_SIZE
			if state_version == 7:
				old_card_size = Vector2(448, 688)
			var legacy_size := old_card_size + Vector2(0.0, (members.size() - 1) * TableState.STACK_STEP)
			var old_bounds := LEGACY_WORLD_BOUNDS if state_version < 6 else TableState.WORLD_BOUNDS
			if not old_bounds.encloses(Rect2(position, legacy_size)):
				return _failure("Legacy stack is outside bounds")
		state.stacks[String(id)] = {"id": String(id), "cards": members, "position": position, "z": int(entry.z)}
		if state_version < 8:
			# 旧档先以当时的牌桌和卡牌尺寸校验，再迁入当前边界；新档不能静默修复越界。
			state.move_stack(String(id), position)
	if int(raw.next_card_id) <= largest_card or int(raw.next_stack_id) <= largest_stack or int(raw.next_z) <= largest_z:
		return _failure("Instance counters would reuse an ID")
	state.next_card_id = int(raw.next_card_id)
	state.next_stack_id = int(raw.next_stack_id)
	state.next_z = int(raw.next_z)
	var validation_error := state.validate()
	if not validation_error.is_empty():
		return _failure(validation_error)
	return {"ok": true, "state": state}


static func _validate_shop(raw: Dictionary, state: TableState) -> Dictionary:
	if not raw.get("is_open") is bool or not raw.get("customers") is Array or raw.customers.size() > ShopSession.MAX_CUSTOMERS:
		return _failure("Invalid shop state")
	if not _number(raw.get("arrival_remaining"), 0.0, maxf(ShopSession.ARRIVAL_INTERVAL, ShopSession.FIRST_ARRIVAL_SECONDS)):
		return _failure("Invalid arrival timer")
	if not _integer(raw.get("arrivals_today"), 0, ShopSession.MAX_ARRIVALS_PER_DAY) or not _integer(raw.get("sales_count"), 0, MAX_COUNTER) or not _integer(raw.get("next_ticket"), 1, MAX_COUNTER):
		return _failure("Invalid shop counters")
	var seen := {}
	var npc_seen := {}
	var largest_ticket := 0
	for customer: Variant in raw.customers:
		if not customer is String or seen.has(customer) or not state.cards.has(customer) or state.cards[customer].zone != &"queue":
			return _failure("Invalid customer queue membership")
		var metadata: Dictionary = state.cards[customer].metadata
		if npc_seen.has(metadata.npc_id):
			return _failure("Same NPC is waiting twice")
		npc_seen[metadata.npc_id] = true
		seen[customer] = true
		largest_ticket = maxi(largest_ticket, int(metadata.ticket))
	for id: String in state.cards:
		if state.cards[id].zone == &"queue" and not seen.has(id):
			return _failure("Queue card has no waiting slot")
	if int(raw.next_ticket) <= largest_ticket:
		return _failure("Customer ticket would be reused")
	return {"ok": true}


static func _customer_metadata(data: Dictionary) -> bool:
	if not data.get("npc_id") is String or ContentCatalog.npc_definition(data.npc_id).is_empty():
		return false
	if not _integer(data.get("ticket"), 1, MAX_COUNTER) or not _number(data.get("total_wait"), 0.001, 3600.0):
		return false
	if not _number(data.get("remaining"), 0.0, float(data.total_wait)):
		return false
	return data.get("requested_kind") == "goods"


static func _inactive_opening() -> Dictionary:
	return {"stage": "inactive", "intro_index": 0, "elapsed": 0.0}


static func _inactive_dialogue() -> Dictionary:
	return {"story_id": "", "line_index": 0, "active_npc_id": "", "completed": [], "settled_consequences": []}


static func _count_kind(state: TableState, kind: StringName) -> int:
	var result := 0
	for id: String in state.cards:
		result += int(state.card_kind(id) == kind)
	return result


static func _instance_id(value: Variant, prefix: String) -> bool:
	if not value is String or not value.begins_with(prefix):
		return false
	var suffix: String = value.trim_prefix(prefix)
	if suffix.length() < 4 or suffix.length() > 10 or not suffix.is_valid_int() or suffix.to_int() < 1:
		return false
	for character: String in suffix:
		if character < "0" or character > "9":
			return false
	return true


static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, float(minimum), float(maximum)) and floorf(float(value)) == float(value)


static func _vector_array(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0], -1000000.0, 1000000.0) and _number(value[1], -1000000.0, 1000000.0)


static func _plain_is_valid(value: Variant, depth: int = 0) -> bool:
	if depth > 8:
		return false
	if value == null or value is bool or value is String or value is StringName:
		return true
	if value is int or value is float:
		return is_finite(float(value))
	if value is Array:
		for item: Variant in value:
			if not _plain_is_valid(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _plain_is_valid(value[key], depth + 1):
				return false
		return true
	return false


static func _plain(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[String(key)] = _plain(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_plain(item))
		return result
	return value


static func _failure(reason: String, key: String = "SAVE_CORRUPT") -> Dictionary:
	return {"ok": false, "error_key": key, "reason": reason}
