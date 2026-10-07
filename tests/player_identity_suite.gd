extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	_use_empty_catalog()
	_test_names()
	_test_identity_data()
	_test_snapshots_and_migration()
	print("PLAYER_IDENTITY_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_names() -> void:
	var identity := PlayerIdentity.new()
	_check("new identity stores no translated default name", identity.name.is_empty() and identity.to_data() == {"name": ""})
	for value: String in ["", " ", String.chr(0x3000), String.chr(0xA0) + " " + String.chr(0x2002)]:
		_check("whitespace-only name is rejected", PlayerIdentity.name_error(value) == "NAME_ENTRY_REQUIRED" and not identity.set_name(value))
	for code: int in [9, 10, 13, 31, 127, 133, 159, 0xAD, 0x61C, 0x180E, 0x200B, 0x200E, 0x2028, 0x202E, 0x2066, 0xFEFF, 0xE0001]:
		_check("control code is rejected %d" % code, PlayerIdentity.name_error("A" + String.chr(code) + "B") == "NAME_ENTRY_INVALID")
	_check("twelve ASCII units are allowed", identity.set_name("A".repeat(12)) and identity.name.length() == 12)
	var before := identity.name
	_check("overlong name rejects atomically", not identity.set_name("A".repeat(13)) and identity.name == before)
	var han := String.chr(0x6797)
	_check("six Han characters fit twelve units", identity.set_name(han.repeat(6)) and PlayerIdentity.name_units(identity.name) == 12)
	_check("seven Han characters exceed limit", PlayerIdentity.name_error(han.repeat(7)) == "NAME_ENTRY_TOO_LONG")
	_check("mixed text shares one budget", identity.set_name("ABCD" + han.repeat(4)) and PlayerIdentity.name_units(identity.name) == 12)
	_check("mixed overflow is rejected", PlayerIdentity.name_error("ABCDE" + han.repeat(4)) == "NAME_ENTRY_TOO_LONG")
	_check("normalized padding consumes no budget", PlayerIdentity.name_units(" " + han.repeat(6) + " ") == 12)
	var chinese_name := String.chr(0x6797) + String.chr(0x95F4)
	_check("non-Latin player name is preserved", identity.set_name(chinese_name) and identity.name == chinese_name)
	_check("Unicode outer spaces are normalized", identity.set_name(String.chr(0x3000) + " Rowan Vale " + String.chr(0xA0)) and identity.name == "Rowan Vale")
	_check("internal spaces and punctuation remain user data", identity.set_name("A-B [C]") and identity.name == "A-B [C]")
	var data := identity.to_data()
	data.name = "Changed"
	_check("serialized name does not alias the model", identity.name == "A-B [C]")


func _test_identity_data() -> void:
	var identity := PlayerIdentity.new()
	identity.set_name("Rowan")
	for value: Variant in [null, [], {}, {"name": 12}, {"name": true}, {"name": "Rowan", "other": "x"}, {"name": " Rowan "}, {"name": "A".repeat(21)}, {"name": "A\nB"}, {"name": " "}]:
		_check("invalid identity payload is rejected", not PlayerIdentity.validate_data(value).is_empty())
		_check("invalid identity restore preserves current name", not identity.restore(value) and identity.name == "Rowan")
	_check("unnamed legacy identity can restore", identity.restore({"name": ""}) and identity.name.is_empty())
	var parsed: Variant = JSON.parse_string(JSON.stringify({"name": "Birch"}))
	_check("name survives a plain JSON roundtrip", identity.restore(parsed) and identity.name == "Birch")
	for historical: String in ["A".repeat(20), String.chr(0x6797).repeat(20)]:
		_check("legacy twenty character name still restores", identity.restore({"name": historical}) and identity.name == historical)
		_check("legacy name cannot be newly created", PlayerIdentity.name_error(historical) == "NAME_ENTRY_TOO_LONG")


func _test_snapshots_and_migration() -> void:
	var state := TableState.new()
	var shop := ShopSession.new()
	shop.setup(state)
	var day := DayCycle.new()
	day.elapsed = 42.5
	var camera := TableCamera.new()
	var progress := PlayerProgress.new()
	var identity := PlayerIdentity.new()
	identity.set_name("Rowan")
	var baseline := GameSnapshot.capture(state, shop, day, camera, progress, null, null, identity)
	_check("current snapshot uses the active schema version", baseline.state_version == GameSnapshot.STATE_VERSION)
	var decoded := GameSnapshot.decode(JSON.parse_string(JSON.stringify(baseline)))
	_check("named snapshot restores", decoded.ok and decoded.identity.name == "Rowan" and decoded.day.elapsed == 42.5)
	for historical: String in ["A".repeat(20), String.chr(0x6797).repeat(20)]:
		var historical_snapshot := baseline.duplicate(true)
		historical_snapshot.identity.name = historical
		var restored := GameSnapshot.decode(historical_snapshot)
		_check("legacy long name snapshot decodes", restored.ok and restored.identity.name == historical)
	_check("card identity never contains the player name", baseline.table.cards.values().all(func(entry: Dictionary) -> bool: return String(entry.definition_id).begins_with("card.") and entry.definition_id != "Rowan"))
	for version in [1, 2, 3]:
		var old := baseline.duplicate(true)
		old.state_version = version
		old.erase("identity")
		if version == 1:
			old.erase("opening")
		if version < 3:
			old.erase("dialogue")
		else:
			old.dialogue.erase("settled_consequences")
		decoded = GameSnapshot.decode(old)
		_check("legacy version keeps progress while adding unnamed identity %d" % version, decoded.ok and decoded.identity.name.is_empty() and decoded.state.card_count() == state.card_count() and decoded.day.elapsed == 42.5)
	var bad := baseline.duplicate(true)
	bad.erase("identity")
	_check("current snapshot requires identity", not GameSnapshot.decode(bad).ok)
	for value: Variant in [{"name": 1}, {"name": "A\nB"}, {"name": "A".repeat(21)}, {"name": " Rowan "}, {"name": ""}, {"name": "Birch"}]:
		bad = baseline.duplicate(true)
		bad.identity = value
		var expected: bool = value.name is String and value.name in ["", "Birch"]
		_check("snapshot enforces identity constraints", GameSnapshot.decode(bad).ok == expected)
	if state.stacks.is_empty():
		print("SKIP legacy card geometry: production content catalog is empty")
		shop.free()
		day.free()
		return
	var stack_id: String = state.stacks.keys()[0]
	var old_at := GameSnapshot.LEGACY_WORLD_BOUNDS.end - GameSnapshot.LEGACY_CARD_SIZE
	var old_edge := baseline.duplicate(true)
	old_edge.state_version = 3
	old_edge.erase("identity")
	old_edge.dialogue.erase("settled_consequences")
	old_edge.table.stacks[stack_id].position = [old_at.x, old_at.y]
	decoded = GameSnapshot.decode(old_edge)
	_check("old edge geometry is validated then migrated", decoded.ok and decoded.state.validate().is_empty())
	if decoded.ok:
		var expected_at := state.clamp_position(old_at, state.stack_size(stack_id))
		_check("legacy edge moves only to the new legal placement", decoded.state.stacks[stack_id].position == expected_at)
	bad = old_edge.duplicate(true)
	bad.table.stacks[stack_id].position[0] += 1.0
	_check("legacy corrupt width cannot be rescued by a narrower new card", not GameSnapshot.decode(bad).ok)
	bad = old_edge.duplicate(true)
	bad.table.stacks[stack_id].position[1] += 1.0
	_check("legacy corrupt height is still rejected", not GameSnapshot.decode(bad).ok)
	var current_edge := baseline.duplicate(true)
	var current_at := TableState.WORLD_BOUNDS.end - TableState.CARD_SIZE
	current_edge.table.stacks[stack_id].position = [current_at.x, current_at.y]
	decoded = GameSnapshot.decode(current_edge)
	_check("current valid geometry is not migrated", decoded.ok and decoded.state.stacks[stack_id].position == current_at)
	current_edge.table.stacks[stack_id].position[1] += 0.25
	_check("current invalid geometry is strictly rejected", not GameSnapshot.decode(current_edge).ok)
	shop.free()
	day.free()


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL " + label)


# 本测试的存档样本是“空牌桌 + 空内容基座”：先换成空目录，不受正式内容影响。
func _use_empty_catalog() -> void:
	var base := {"version": 1, "content_generation": ContentCatalog.content_generation(), "cards": {}, "recipes": {}, "npcs": {}, "stories": {}, "events": {}, "opening": {}, "initial_cards": []}
	ContentCatalog._registry.configure_base(base)
	ContentCatalog._base_data = base
	ContentCatalog._data = ContentCatalog._registry.catalog()
