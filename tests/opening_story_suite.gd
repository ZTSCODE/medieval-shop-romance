extends SceneTree

# 开场剧情（docs/story/opening-script-draft.md）的数据与流程检查：使用真实 data/content.json，不读写玩家存档。
# 流程：文字页 → 林边遇到信使（场景剧情，自动开始）→ 探索黑刺李林 → 信使追上来讲规矩 → 信使跑开留下獾道。

const EDGE := "story.messenger.edge"
const RULES := "story.messenger.thorn_rules"
const MESSENGER := "npc.messenger"

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_catalog()
	_test_opening_and_prologue()
	_test_rules_and_departure()
	_test_save_formats()
	_test_save_roundtrip()
	print("OPENING_STORY_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_catalog() -> void:
	for id: String in ["card.hero", "card.loc.first_forest", "card.npc.messenger", "card.res.sloes", "card.loc.badger_track", "card.loc.the_stones"]:
		_check(not ContentCatalog.card_definition(id).is_empty(), "card %s registered" % id)
	for id: String in [EDGE, RULES]:
		_check(not DialogueFlow._dialogue_definition(id).is_empty(), "story %s valid" % id)
	var definition := ContentCatalog.opening_definition()
	_check(OpeningFlow._definition_valid(definition), "opening definition valid")
	_check(OpeningFlow.intro_page_count() == 5 and definition.name_entry_page == 5, "five chronicle pages, then naming")
	_check(definition.page_layouts.size() == 5, "every chronicle page has a plate")
	_check(definition.prologue_story_id == EDGE, "prologue is the messenger at the edge")
	var missing: Array[String] = []
	var keys := _csv_keys()
	for key: String in _text_keys():
		if not keys.has(key):
			missing.append(key)
	_check(missing.is_empty(), "all text keys localized, missing: %s" % [missing])


func _start_opening(table: TableState) -> OpeningFlow:
	var flow := OpeningFlow.new()
	flow.start(table)
	for i in OpeningFlow.intro_page_count():
		flow.advance_intro()
	return flow


func _play(dialogue: DialogueFlow, choice: String) -> void:
	var guard := 0
	while dialogue.is_active() and guard < 300:
		guard += 1
		if dialogue.awaiting_choice():
			if not dialogue.choose(choice).ok:
				dialogue.choose(String(dialogue.presentation_info().choices[0].id))
		else:
			dialogue.advance()


func _test_opening_and_prologue() -> void:
	var table := TableState.new()
	var flow := OpeningFlow.new()
	flow.start(table)
	_check(flow.stage == &"intro" and table.cards.size() == 2, "intro with two cards")
	for i in OpeningFlow.intro_page_count():
		flow.advance_intro()
	_check(flow.stage == &"explore", "pages lead to exploration")
	var dialogue := DialogueFlow.new()
	_check(dialogue.next_story(MESSENGER) == EDGE, "edge scene comes first")
	_check(dialogue.start_for_npc(MESSENGER) and dialogue.story_id == EDGE, "edge scene starts without a card")
	_check(dialogue.presentation_info().narrator, "edge opens with narration")
	var choices_seen := 0
	var guard := 0
	while dialogue.is_active() and guard < 200:
		guard += 1
		if dialogue.awaiting_choice():
			choices_seen += 1
			var info := dialogue.presentation_info()
			_check(info.choices.size() == 3, "three options offered")
			dialogue.advance()
			_check(dialogue.awaiting_choice(), "advance cannot skip a choice")
			_check(not dialogue.choose("ghost").ok, "unknown option refused")
			var option := String(info.choices[1].id)
			_check(dialogue.choose(option).ok and dialogue.branch_choice == option, "branch reply plays")
			var copy := DialogueFlow.new()
			copy.restore(dialogue.to_data())
			_check(copy.branch_choice == option and copy.line_index == dialogue.line_index, "branch survives save")
			_check(DialogueFlow.validate_data(dialogue.to_data(), table).is_empty(), "scene dialogue validates without the messenger on the table")
			continue
		dialogue.advance()
	_check(choices_seen == 2 and not dialogue.is_active(), "edge scene has two choices and completes")
	_check(EDGE in dialogue.completed and dialogue.next_story(MESSENGER) == RULES, "rules wait for the messenger card")
	var stacks := table.stacks.keys()
	_check(table.merge(stacks[1], stacks[0]), "hero joins the wood")
	flow.advance(OpeningFlow.explore_seconds() + 1.0)
	_check(flow.stage == &"complete" and _kinds(table) == ["hero", "messenger", "sloes"], "exploration yields messenger and sloes: %s" % [_kinds(table)])


func _test_rules_and_departure() -> void:
	var table := TableState.new()
	var flow := _start_opening(table)
	var dialogue := DialogueFlow.new()
	dialogue.start_for_npc(MESSENGER)
	_play(dialogue, "ask")
	var stacks := table.stacks.keys()
	table.merge(stacks[1], stacks[0])
	flow.advance(OpeningFlow.explore_seconds() + 1.0)
	var hero := _card_of(table, &"hero")
	var messenger := _card_of(table, &"messenger")
	_check(table.cards[messenger].metadata.get("npc_id", "") == MESSENGER, "messenger card carries npc id")
	_check(table.merge(table.stack_for(hero), table.stack_for(messenger)), "hero sits with messenger")
	_check(dialogue.start_for_npc(MESSENGER) and dialogue.story_id == RULES, "rules talk starts on the card")
	_play(dialogue, "")
	_check(RULES in dialogue.completed, "rules talk completes")
	var result := dialogue.resolve_story_consequences(RULES, MESSENGER, table)
	_check(result.ok and result.departed == [messenger] and result.created.size() == 1, "messenger leaves one card: %s" % [result])
	_check(not table.cards.has(messenger) and table.card_kind(result.created[0]) == &"badger_track", "badger track left behind")
	_check(table.validate().is_empty(), "table valid after departure")
	_check(not table.stack_rect(table.stack_for(hero)).intersects(table.stack_rect(table.stack_for(result.created[0]))), "track does not overlap hero")
	var again := dialogue.resolve_story_consequences(RULES, MESSENGER, table)
	_check(again.ok and again.created.is_empty(), "consequence settles once")
	_check(dialogue.next_story(MESSENGER).is_empty() and not dialogue.start_for_npc(MESSENGER), "nothing replays afterwards")
	# 通用地点探索：“你”走上獾道，到时獾道变成立石。
	var walk := LocationExploration.new()
	walk.state = table
	var explored: Array[String] = []
	walk.explored.connect(func(id: String) -> void: explored.append(id))
	var track: String = result.created[0]
	_check(table.merge(table.stack_for(track), table.stack_for(hero)), "hero steps onto the track")
	walk.advance(3.0)
	_check(walk.work_progress().size() == 1 and is_equal_approx(walk.work_progress()[0].progress, 0.5), "track progress shows halfway")
	walk.advance(3.0, true)
	_check(is_equal_approx(walk.work_progress()[0].progress, 0.5), "suspended walking does not advance")
	walk.advance(3.5)
	_check(_kinds(table) == ["hero", "sloes", "the_stones"] and explored == ["card.loc.badger_track"], "track leads to the stones: %s" % [_kinds(table)])
	_check(table.validate().is_empty() and walk.work_progress().is_empty(), "table valid and nothing left to walk")
	_check(not table.stack_rect(table.stack_for(hero)).intersects(table.stack_rect(table.stack_for(_card_of(table, &"the_stones")))), "stones do not land on the hero")


func _test_save_formats() -> void:
	var legacy := {"story_id": "", "line_index": 0, "active_npc_id": "", "completed": [], "settled_consequences": []}
	_check(DialogueFlow.validate_data(legacy).is_empty(), "five-field save still accepted")
	var bad := legacy.duplicate(true)
	bad["branch"] = ["ghost", 0]
	_check(not DialogueFlow.validate_data(bad).is_empty(), "branch outside a dialogue rejected")


# 真实存档编解码：林边选项分支中、探索后与信使交谈中、信使离开后都必须能读回。
func _test_save_roundtrip() -> void:
	var table := TableState.new()
	var flow := _start_opening(table)
	var progress := PlayerProgress.new()
	var dialogue := DialogueFlow.new()
	progress.meet_npc(MESSENGER, 1)
	dialogue.start_for_npc(MESSENGER)
	while not dialogue.awaiting_choice():
		dialogue.advance()
	dialogue.choose("stone")
	var decoded := _roundtrip(table, flow, dialogue, progress)
	_check(decoded.ok and String(decoded.dialogue.branch[0]) == "stone", "save inside edge choice: %s" % [decoded.get("reason", "")])
	_play(dialogue, "pull_away")
	var stacks := table.stacks.keys()
	table.merge(stacks[1], stacks[0])
	flow.advance(OpeningFlow.explore_seconds() + 1.0)
	var hero := _card_of(table, &"hero")
	table.merge(table.stack_for(_card_of(table, &"messenger")), table.stack_for(hero))
	dialogue.start_for_npc(MESSENGER)
	for i in 5:
		dialogue.advance()
	decoded = _roundtrip(table, flow, dialogue, progress)
	_check(decoded.ok and decoded.state.card_count() == 3, "save during rules talk: %s" % [decoded.get("reason", "")])
	_play(dialogue, "")
	dialogue.resolve_story_consequences(RULES, MESSENGER, table)
	decoded = _roundtrip(table, flow, dialogue, progress)
	_check(decoded.ok and decoded.state.card_count() == 3, "save after messenger leaves: %s" % [decoded.get("reason", "")])


func _roundtrip(table: TableState, flow: OpeningFlow, dialogue: DialogueFlow, progress: PlayerProgress) -> Dictionary:
	var shop := ShopSession.new()
	shop.state = table  # setup() 会清空牌桌，这里只需要一个关店状态。
	var identity := PlayerIdentity.new()
	identity.set_name("Rowan")
	var snapshot := GameSnapshot.capture(table, shop, DayCycle.new(), TableCamera.new(), progress, flow, dialogue, identity)
	return GameSnapshot.decode(JSON.parse_string(JSON.stringify(snapshot)))


func _card_of(table: TableState, kind: StringName) -> String:
	for id: String in table.cards:
		if table.card_kind(id) == kind:
			return id
	return ""


func _kinds(table: TableState) -> Array[String]:
	var kinds: Array[String] = []
	for id: String in table.cards:
		kinds.append(String(table.card_kind(id)))
	kinds.sort()
	return kinds


func _text_keys() -> Array[String]:
	var keys: Array[String] = []
	var definition := ContentCatalog.opening_definition()
	keys.append_array(definition.pages)
	for hint: Dictionary in definition.tutorials:
		keys.append(hint.key)
	for id: String in ContentCatalog.card_ids():
		var card := ContentCatalog.card_definition(id)
		for field: String in ["name_key", "detail_key", "category_key"]:
			if card.has(field):
				keys.append(card[field])
	for id: String in ContentCatalog.npc_ids():
		var npc := ContentCatalog.npc_definition(id)
		keys.append(npc.name_key)
		keys.append(npc.description_key)
	for story_id: String in [EDGE, RULES]:
		for line: Dictionary in ContentCatalog.story_definition(story_id).lines:
			keys.append(line.text_key)
			for option: Dictionary in line.get("choices", []):
				keys.append(option.text_key)
				for reply: Dictionary in option.lines:
					keys.append(reply.text_key)
	return keys


func _csv_keys() -> Dictionary:
	var result := {}
	var file := FileAccess.open("res://localization/game.csv", FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 3 and not row[1].is_empty() and not row[2].is_empty():
			result[row[0]] = true
	return result


func _check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("Opening story check %d failed: %s" % [checks, label])
