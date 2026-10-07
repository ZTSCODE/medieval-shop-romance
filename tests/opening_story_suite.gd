extends SceneTree

# 开场剧情（docs/story/opening-script-draft.md）的数据与流程检查：使用真实 data/content.json，不读写玩家存档。
# 流程：序幕 → 主角在雪线边的独白（桌上是“你”和那把种子）→ 黑刺李林上桌 → 对林子的犹豫 → 探索黑刺李林
# → 信使和溪边小道上桌 → 与信使相遇，说完他先走 → 沿溪边小道走 → 信使追上来、背风地出现 → 介绍背风地、互通姓名。

const THAW := "story.hero.thaw_edge"
const DOUBT := "story.hero.wood_doubt"
const EDGE := "story.messenger.edge"
const CATCH := "story.messenger.catch_up"
const MESSENGER := "npc.messenger"
const STREAM := "card.loc.stream_path"

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_catalog()
	_test_monologues_and_wood()
	_test_meeting_and_departure()
	_test_stream_and_catch_up()
	_test_save_formats()
	_test_save_roundtrip()
	print("OPENING_STORY_SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_catalog() -> void:
	for id: String in ["card.hero", "card.res.winter_seed", "card.loc.first_forest", "card.npc.messenger", STREAM, "card.loc.the_lee"]:
		var card := ContentCatalog.card_definition(id)
		_check(not card.is_empty() and ResourceLoader.exists(String(card.get("art_path", ""))), "card %s registered with its art" % id)
	for id: String in ["card.res.sloes", "card.loc.badger_track", "card.loc.the_stones"]:
		_check(ContentCatalog.card_definition(id).is_empty(), "card %s is gone" % id)
	for id: String in [THAW, DOUBT, EDGE, CATCH]:
		_check(not DialogueFlow._dialogue_definition(id).is_empty(), "story %s valid" % id)
	var definition := ContentCatalog.opening_definition()
	_check(OpeningFlow._definition_valid(definition), "opening definition valid")
	_check(OpeningFlow.intro_page_count() == 5 and definition.name_entry_page == 5, "five chronicle pages, then naming")
	_check(definition.page_layouts.size() == 5, "every chronicle page has a plate")
	var order: Array[String] = []
	for scene: Dictionary in definition.scenes:
		order.append(scene.story)
	_check(order == [THAW, DOUBT], "only the two monologues start by themselves")
	for id: String in [THAW, DOUBT]:
		var solo := true
		for line: Dictionary in ContentCatalog.story_definition(id).lines:
			solo = solo and line.speaker == "hero"
		_check(solo and ContentCatalog.story_definition(id).get("solo", false), "%s is the hero talking to himself" % id)
	var missing: Array[String] = []
	var keys := _csv_keys()
	for key: String in _text_keys():
		if not keys.has(key):
			missing.append(key)
	_check(missing.is_empty(), "all text keys localized, missing: %s" % [missing])
	# 文案里的 {name} 显示成玩家取的名字；没取名时用默认名。
	PlayerNameText.install()
	PlayerNameText.install()
	var locale := TranslationServer.get_locale()
	for code: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(code)
		PlayerNameText.player_name = "Rowan"
		var told := String(TranslationServer.translate("DLG_MESSENGER_CATCH_CHOICE_TELL_2"))
		_check(told.begins_with("Rowan") and "{name}" not in told, "the messenger repeats the player's name (%s): %s" % [code, told])
		PlayerNameText.player_name = ""
		var fallback := String(TranslationServer.translate("DLG_MESSENGER_CATCH_CHOICE_TELL_1"))
		_check(fallback.begins_with(String(TranslationServer.translate("PLAYER_DEFAULT_NAME"))) and "{name}" not in fallback, "without a name the default name is used (%s): %s" % [code, fallback])
		_check(String(TranslationServer.translate("CARD_YOU_TITLE")) in ["你", "You"], "other text is untouched (%s)" % code)
	TranslationServer.set_locale(locale)
	var goals := OnboardingGoals.new()
	for stage: Dictionary in goals.stages:
		for goal: Dictionary in stage.goals:
			_check(keys.has(goal.text_key), "goal text %s localized" % goal.text_key)


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


func _stack(table: TableState, first: StringName, second: StringName) -> bool:
	return table.merge(table.stack_for(_card_of(table, first)), table.stack_for(_card_of(table, second)))


# 两段独白、林子上桌、走进林子：信使和溪边小道出现。
func _walk_into_wood(table: TableState, flow: OpeningFlow, dialogue: DialogueFlow) -> void:
	dialogue.start_solo(THAW)
	_play(dialogue, "")
	flow.deliver_arrivals(THAW)
	dialogue.start_solo(DOUBT)
	_play(dialogue, "")
	flow.deliver_arrivals(DOUBT)
	_stack(table, &"hero", &"first_forest")
	flow.advance(OpeningFlow.explore_seconds() + 1.0)


# 再和信使说完话，他先走。
func _meet_messenger(table: TableState, flow: OpeningFlow, dialogue: DialogueFlow, choice: String = "") -> void:
	_walk_into_wood(table, flow, dialogue)
	_stack(table, &"hero", &"messenger")
	dialogue.start_for_npc(MESSENGER)
	_play(dialogue, choice)
	dialogue.resolve_story_consequences(EDGE, MESSENGER, table)


func _test_monologues_and_wood() -> void:
	var table := TableState.new()
	var flow := OpeningFlow.new()
	flow.start(table)
	_check(flow.stage == &"intro" and _kinds(table) == ["hero", "winter_seed"], "the hero starts with only the seed beside him: %s" % [_kinds(table)])
	_check(not table.stack_rect(table.stack_for(_card_of(table, &"hero"))).intersects(table.stack_rect(table.stack_for(_card_of(table, &"winter_seed")))), "the seed lies beside the hero, not on him")
	_check(flow.deliver_arrivals(THAW).is_empty(), "nothing arrives during the prologue")
	for i in OpeningFlow.intro_page_count():
		flow.advance_intro()
	_check(flow.stage == &"explore", "prologue leads to the table")
	_check(OpeningFlow.validate_data(flow.to_data(), table).is_empty(), "opening saves before the wood arrives")
	var dialogue := DialogueFlow.new()
	_check(not dialogue.start_solo(DOUBT), "the second monologue waits for the first")
	_check(not dialogue.start_solo(EDGE), "a scene with a person is not a monologue")
	_check(dialogue.start_solo(THAW) and dialogue.story_id == THAW and dialogue.active_npc_id.is_empty(), "first monologue starts with nobody else")
	var info := dialogue.presentation_info()
	_check(not info.narrator and info.npc_hidden and dialogue.current_line().speaker == "hero", "it is the hero speaking, with no one opposite")
	_check(DialogueFlow.validate_data(dialogue.to_data(), table).is_empty(), "a monologue validates with no one else on the table")
	var decoded := _roundtrip(table, flow, dialogue, PlayerProgress.new())
	_check(decoded.ok and decoded.dialogue.story_id == THAW, "save inside the first monologue: %s" % [decoded.get("reason", "")])
	var with_npc := dialogue.to_data()
	with_npc.active_npc_id = MESSENGER
	_check(not DialogueFlow.validate_data(with_npc, table).is_empty(), "a monologue claiming a person is rejected")
	_play(dialogue, "")
	_check(THAW in dialogue.completed and not dialogue.start_solo(THAW), "first monologue reads once")
	var arrived := flow.deliver_arrivals(THAW)
	_check(arrived.size() == 1 and _kinds(table) == ["first_forest", "hero", "winter_seed"], "the wood is the first card to arrive: %s" % [_kinds(table)])
	var hero := _card_of(table, &"hero")
	var wood := _card_of(table, &"first_forest")
	_check(table.card_position(wood).x > table.card_position(hero).x and not table.stack_rect(table.stack_for(hero)).intersects(table.stack_rect(table.stack_for(wood))), "the wood lands beside the hero")
	_check(flow.deliver_arrivals(THAW).is_empty() and _kinds(table) == ["first_forest", "hero", "winter_seed"], "the wood cannot arrive twice")
	_check(OpeningFlow.validate_data(flow.to_data(), table).is_empty() and table.validate().is_empty(), "opening saves after the wood arrives")
	_check(dialogue.start_solo(DOUBT) and dialogue.presentation_info().npc_hidden, "second monologue follows")
	decoded = _roundtrip(table, flow, dialogue, PlayerProgress.new())
	_check(decoded.ok and decoded.state.card_count() == 3, "save inside the second monologue: %s" % [decoded.get("reason", "")])
	_play(dialogue, "")
	_check(flow.deliver_arrivals(DOUBT).is_empty(), "nothing arrives after the second monologue")
	_check(dialogue.resolve_story_consequences(DOUBT, "", table).ok, "a monologue has no consequences to settle")
	_check(_stack(table, &"hero", &"first_forest"), "hero joins the wood")
	flow.advance(OpeningFlow.explore_seconds() + 1.0)
	_check(flow.stage == &"complete" and _kinds(table) == ["hero", "messenger", "stream_path", "winter_seed"], "walking the wood brings the messenger and the streamside path: %s" % [_kinds(table)])
	_check(table.cards[_card_of(table, &"messenger")].metadata.get("npc_id", "") == MESSENGER, "messenger card carries npc id")
	_check(table.validate().is_empty(), "table valid after the wood")


func _test_meeting_and_departure() -> void:
	var table := TableState.new()
	var flow := _start_opening(table)
	var dialogue := DialogueFlow.new()
	_walk_into_wood(table, flow, dialogue)
	# 信使还在桌上时，溪边小道走不了。
	var walk := LocationExploration.new()
	walk.state = table
	_check(_stack(table, &"hero", &"stream_path"), "hero can be put on the path early")
	walk.advance(60.0)
	_check(walk.work_progress().is_empty() and _kinds(table) == ["hero", "messenger", "stream_path", "winter_seed"], "but the path cannot be walked while the messenger stands there")
	table.take_from(_card_of(table, &"hero"), false)
	_check(dialogue.next_story(MESSENGER) == EDGE, "the meeting is the messenger's first story")
	_check(_stack(table, &"hero", &"messenger"), "hero sits with the messenger")
	_check(dialogue.start_for_npc(MESSENGER) and dialogue.story_id == EDGE, "the meeting starts on his card")
	_check(dialogue.presentation_info().narrator and dialogue.presentation_info().npc_hidden, "it opens with narration, before he is seen")
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
			_check(DialogueFlow.validate_data(dialogue.to_data(), table).is_empty(), "the meeting validates with both on one stack")
			continue
		dialogue.advance()
	_check(choices_seen == 2 and EDGE in dialogue.completed, "the meeting has two choices and completes")
	var messenger := _card_of(table, &"messenger")
	var result := dialogue.resolve_story_consequences(EDGE, MESSENGER, table)
	_check(result.ok and result.departed == [messenger] and result.created.is_empty(), "the messenger goes ahead and leaves nothing: %s" % [result])
	_check(_kinds(table) == ["hero", "stream_path", "winter_seed"] and table.validate().is_empty(), "his card is off the table: %s" % [_kinds(table)])
	_check(not dialogue.has_departed(MESSENGER), "but he has not left for good")
	_check(dialogue.next_story(MESSENGER) == CATCH, "his next story waits for him to come back")
	var again := dialogue.resolve_story_consequences(EDGE, MESSENGER, table)
	_check(again.ok and again.departed.is_empty(), "his leaving settles once")


func _test_stream_and_catch_up() -> void:
	var table := TableState.new()
	var flow := _start_opening(table)
	var dialogue := DialogueFlow.new()
	_meet_messenger(table, flow, dialogue, "stone")
	var walk := LocationExploration.new()
	walk.state = table
	var explored: Array[String] = []
	walk.explored.connect(func(id: String) -> void: explored.append(id))
	_check(_stack(table, &"hero", &"stream_path"), "hero steps onto the streamside path")
	walk.advance(3.0)
	_check(walk.work_progress().size() == 1 and is_equal_approx(walk.work_progress()[0].progress, 0.5), "path progress shows halfway")
	walk.advance(3.0, true)
	_check(is_equal_approx(walk.work_progress()[0].progress, 0.5), "suspended walking does not advance")
	walk.advance(3.5)
	_check(_kinds(table) == ["hero", "messenger", "the_lee", "winter_seed"] and explored == [STREAM], "the path leads to the Lee and the messenger catches up: %s" % [_kinds(table)])
	_check(table.validate().is_empty() and walk.work_progress().is_empty(), "table valid and nothing left to walk")
	var hero_rect := table.stack_rect(table.stack_for(_card_of(table, &"hero")))
	_check(not hero_rect.intersects(table.stack_rect(table.stack_for(_card_of(table, &"the_lee")))) and not hero_rect.intersects(table.stack_rect(table.stack_for(_card_of(table, &"messenger")))), "the new cards do not land on the hero")
	_check(table.cards[_card_of(table, &"messenger")].metadata.get("npc_id", "") == MESSENGER, "the returning card is the same person")
	_check(_stack(table, &"hero", &"messenger"), "hero sits with the messenger again")
	_check(dialogue.start_for_npc(MESSENGER) and dialogue.story_id == CATCH, "the catch-up talk starts")
	var names := 0
	var guard := 0
	while dialogue.is_active() and guard < 200:
		guard += 1
		if dialogue.awaiting_choice():
			names = dialogue.presentation_info().choices.size()
			dialogue.choose("you_first")
		else:
			dialogue.advance()
	_check(names == 3 and CATCH in dialogue.completed, "names are traded and the talk completes")
	var result := dialogue.resolve_story_consequences(CATCH, MESSENGER, table)
	_check(result.ok and result.departed.is_empty() and _kinds(table) == ["hero", "messenger", "the_lee", "winter_seed"], "he stays, with the Lee in sight: %s" % [_kinds(table)])
	_check(dialogue.next_story(MESSENGER).is_empty() and not dialogue.start_for_npc(MESSENGER), "nothing replays afterwards")
	_check(not _card_of(table, &"winter_seed").is_empty(), "the seed is still on the table at the end")


func _test_save_formats() -> void:
	var legacy := {"story_id": "", "line_index": 0, "active_npc_id": "", "completed": [], "settled_consequences": []}
	_check(DialogueFlow.validate_data(legacy).is_empty(), "five-field save still accepted")
	var skipped := legacy.duplicate(true)
	skipped.story_id = DOUBT
	_check(not DialogueFlow.validate_data(skipped).is_empty(), "second monologue cannot be active before the first is read")
	var bad := legacy.duplicate(true)
	bad["branch"] = ["ghost", 0]
	_check(not DialogueFlow.validate_data(bad).is_empty(), "branch outside a dialogue rejected")


# 真实存档编解码：相遇的选项分支中、信使走后、追上来交谈中、结束后都必须能读回（独白中的存档见上面）。
func _test_save_roundtrip() -> void:
	var table := TableState.new()
	var flow := _start_opening(table)
	var progress := PlayerProgress.new()
	var dialogue := DialogueFlow.new()
	_walk_into_wood(table, flow, dialogue)
	progress.meet_npc(MESSENGER, 1)
	_stack(table, &"hero", &"messenger")
	dialogue.start_for_npc(MESSENGER)
	while not dialogue.awaiting_choice():
		dialogue.advance()
	dialogue.choose("stone")
	var decoded := _roundtrip(table, flow, dialogue, progress)
	_check(decoded.ok and String(decoded.dialogue.branch[0]) == "stone", "save inside the meeting's choice: %s" % [decoded.get("reason", "")])
	_play(dialogue, "pull_away")
	dialogue.resolve_story_consequences(EDGE, MESSENGER, table)
	decoded = _roundtrip(table, flow, dialogue, progress)
	_check(decoded.ok and decoded.state.card_count() == 3, "save after the messenger goes ahead: %s" % [decoded.get("reason", "")])
	var walk := LocationExploration.new()
	walk.state = table
	_stack(table, &"hero", &"stream_path")
	walk.advance(7.0)
	_stack(table, &"hero", &"messenger")
	dialogue.start_for_npc(MESSENGER)
	for i in 5:
		dialogue.advance()
	decoded = _roundtrip(table, flow, dialogue, progress)
	_check(decoded.ok and decoded.state.card_count() == 4 and decoded.dialogue.story_id == CATCH, "save during the catch-up talk: %s" % [decoded.get("reason", "")])
	_play(dialogue, "silent")
	decoded = _roundtrip(table, flow, dialogue, progress)
	_check(decoded.ok and decoded.state.card_count() == 4, "save at the end of the opening: %s" % [decoded.get("reason", "")])


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
	for story_id: String in [THAW, DOUBT, EDGE, CATCH]:
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
