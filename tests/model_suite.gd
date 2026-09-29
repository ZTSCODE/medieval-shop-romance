extends SceneTree

var checks := 0
var failures := 0


func _initialize() -> void:
	ContentCatalog.card_ids()
	var fixture := {"version": 1, "cards": {"card.blank": {"id": "card.blank", "kind": "blank", "category": "placeholder", "name_key": "TEST_NAME", "detail_key": "TEST_DETAIL", "art_path": ""}}, "recipes": {}, "npcs": {}, "stories": {}, "events": {}}
	var registry := ModuleRegistry.new()
	assert(registry.configure_base(fixture).ok)
	ContentCatalog._registry = registry
	ContentCatalog._data = registry.catalog()
	var state := TableState.new()
	state.seed()
	var original := state.snapshot()
	_check("initial table", state.card_count() == 9 and state.stacks.size() == 5 and state.validate().is_empty())
	var stacks := state.sorted_stacks()
	var source: String = stacks[1]
	var target: String = stacks[0]
	var cards: Array = state.stacks[source].cards.duplicate()
	var moved := state.take_from(cards[1], false)
	_check("partial pickup order", state.stacks[moved].cards == cards.slice(1) and state.stacks[source].cards == cards.slice(0, 1))
	_check("partial pickup anchor", state.stacks[moved].position == original.stacks[source].position + Vector2(0, TableState.STACK_STEP))
	_check("merge preserves order", state.merge(moved, target) and state.stacks[target].cards.slice(1) == cards.slice(1))
	_check("merge preserves identities", state.card_count() == 9 and state.validate().is_empty())
	var before_whole: Array = state.stacks[target].cards.duplicate()
	_check("whole pickup keeps stack", state.take_from(before_whole.back(), true) == target and state.stacks[target].cards == before_whole)
	state.move_stack(target, Vector2(99999, -99999))
	_check("whole stack remains bounded", TableState.WORLD_BOUNDS.encloses(state.stack_rect(target)))
	var max_state := TableState.new()
	var full := max_state.create_blank(Vector2.ZERO, TableState.MAX_STACK)
	var extra := max_state.create_blank(Vector2(200, 0))
	var before_full := max_state.snapshot()
	_check("full stack rejects another card", not max_state.merge(extra, full) and max_state.stacks == before_full.stacks)
	_check("self merge rejected", not max_state.merge(full, full))
	state.restore(original)
	var random := RandomNumberGenerator.new()
	random.seed = 20260915
	for step in 150:
		var ids := state.sorted_stacks()
		var id: String = ids[random.randi_range(0, ids.size() - 1)]
		match step % 3:
			0:
				var group: Array = state.stacks[id].cards
				state.take_from(group[random.randi_range(0, group.size() - 1)], false)
			1:
				if ids.size() > 1:
					state.merge(id, ids[(ids.find(id) + 1) % ids.size()])
			2:
				state.move_stack(id, Vector2(random.randf_range(-5000, 5000), random.randf_range(-5000, 5000)))
		_check("random state invariants %d" % step, state.validate().is_empty() and state.card_count() == 9)
	print("MODEL_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL " + label)
