extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_use_empty_catalog()
	var flow := OpeningFlow.new()
	var table := TableState.new()
	flow.start(table)
	_check(flow.stage == &"inactive" and table.cards.is_empty())
	_check(OpeningFlow.validate_data(flow.to_data(), table).is_empty())
	var catalog := {"version": 1, "cards": {}, "recipes": {}, "npcs": {}, "stories": {}, "events": {}}
	for kind: String in ["fixture_a", "fixture_b", "fixture_c"]:
		var id := "card." + kind
		catalog.cards[id] = {"id": id, "kind": kind, "category": "item", "name_key": "TEST_NAME", "detail_key": "TEST_DETAIL", "tags": []}
	_check(ContentCatalog._registry.configure_base(catalog).ok)
	ContentCatalog._data = ContentCatalog._registry.catalog()
	ContentCatalog._base_data.opening = {"pages": ["TEST_PAGE"], "initial_cards": [{"kind": "fixture_a", "offset": [-180, 0]}, {"kind": "fixture_b", "offset": [180, 0]}], "explore": {"required_kinds": ["fixture_a", "fixture_b"], "consumed_kinds": ["fixture_b"], "outputs": [{"kind": "fixture_c"}], "duration": 2.0}}
	flow.start(table)
	_check(flow.stage == &"intro" and table.cards.size() == 2)
	flow.advance_intro()
	var stacks := table.stacks.keys()
	_check(table.merge(stacks[0], stacks[1]))
	flow.advance(0.5)
	_check(flow.elapsed == 0.5)
	flow.advance(0.5, true)
	_check(flow.elapsed == 0.5)
	var restored := OpeningFlow.new()
	_check(restored.restore(flow.to_data(), table))
	var stack := flow.work_stack_id()
	var member := String(table.stacks[stack].cards[1])
	var split := table.take_from(member, false)
	flow.advance(0.1)
	_check(flow.elapsed == 0.0)
	_check(table.merge(split, stack))
	flow.advance(0.5)
	split = table.take_from(member, false)
	_check(table.merge(split, stack))
	_check(flow.to_data().elapsed == 0.0)
	flow.advance(0.1)
	_check(flow.elapsed == 0.1)
	flow.advance(2.0)
	_check(flow.stage == &"complete" and table.cards.size() == 2)
	_check(OpeningFlow.validate_data(flow.to_data(), table).is_empty())
	_check(table.validate().is_empty())
	var kinds: Array = []
	for id: String in table.cards:
		kinds.append(String(table.card_kind(id)))
	_check("fixture_a" in kinds and "fixture_c" in kinds and not "fixture_b" in kinds)
	var invalid := flow.to_data()
	invalid.elapsed = -1.0
	_check(not restored.restore(invalid, table))
	_test_portrait_region()
	print("CONTENT_RESET_OPENING_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_portrait_region() -> void:
	var badge := PortraitBadge.new()
	badge.subject_id = "npc.fixture"
	_check(badge.get_portrait_region() == Rect2(0, 0, 1, 1))
	ContentCatalog._data.npcs["npc.fixture"] = {"portrait_region": [0.1, 0.2, 0.3, 0.4]}
	_check(badge.get_portrait_region().is_equal_approx(Rect2(0.1, 0.2, 0.3, 0.4)))
	ContentCatalog._data.npcs["npc.fixture"].portrait_region = [-0.5, 0.0, 1.0, 1.0]
	_check(badge.get_portrait_region() == Rect2(0, 0, 0.5, 1))
	ContentCatalog._data.npcs["npc.fixture"].portrait_region = [0.0, 0.0, -1.0, 1.0]
	_check(badge.get_portrait_region() == Rect2(0, 0, 1, 1))
	badge.free()


func _check(passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("Content reset opening check %d failed" % checks)


# 本测试审计“空内容基座”的行为：先换成空目录，不受正式内容影响。
func _use_empty_catalog() -> void:
	var base := {"version": 1, "content_generation": ContentCatalog.content_generation(), "cards": {}, "recipes": {}, "npcs": {}, "stories": {}, "events": {}, "opening": {}, "initial_cards": []}
	ContentCatalog._registry.configure_base(base)
	ContentCatalog._base_data = base
	ContentCatalog._data = ContentCatalog._registry.catalog()
