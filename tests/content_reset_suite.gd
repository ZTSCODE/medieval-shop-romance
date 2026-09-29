extends SceneTree

class ProbeStory:
	extends RefCounted
	var state := {"facts": [], "completed": [], "story_id": ""}
	func to_data() -> Dictionary:
		return {"state": state}

var checks := 0
var failures := 0

func _initialize() -> void:
	var state := TableState.new()
	var shop := ShopSession.new()
	shop.state = state
	var day := DayCycle.new()
	var camera := TableCamera.new()
	var progress := PlayerProgress.new()
	var payload := GameSnapshot.capture(state, shop, day, camera, progress)
	check(ContentCatalog.card_ids().is_empty(), "catalog_is_empty")
	check(payload.content_generation == "reset_20260924", "capture_generation")
	check(GameSnapshot.decode(payload).get("ok", false), "empty_roundtrip")
	_test_save_store(payload)
	var malformed := payload.duplicate(true)
	malformed.erase("content_generation")
	check(GameSnapshot.decode(malformed).get("error_key") == "SAVE_UNSUPPORTED_VERSION", "reject_missing_generation")
	malformed = payload.duplicate(true)
	malformed.content_generation = "old_content"
	check(GameSnapshot.decode(malformed).get("error_key") == "SAVE_UNSUPPORTED_VERSION", "reject_old_generation")
	malformed.state_version = 9
	malformed.session_mode = "chapter_01"
	check(GameSnapshot.decode(malformed).get("error_key") == "SAVE_UNSUPPORTED_VERSION", "reject_old_chapter_before_package_read")
	malformed = payload.duplicate(true)
	malformed.shop.is_open = true
	check(not GameSnapshot.decode(malformed).get("ok", false), "reject_empty_open_shop")
	malformed = payload.duplicate(true)
	malformed.day.elapsed = malformed.day.seconds_per_day
	check(not GameSnapshot.decode(malformed).get("ok", false), "reject_invalid_day")
	malformed = payload.duplicate(true)
	malformed.table.cards.card_0001 = {"definition_id": "card.hero", "zone": "board", "metadata": {}}
	check(not GameSnapshot.decode(malformed).get("ok", false), "reject_deleted_card")
	var module := {"version": 1, "module_id": "snapshot_probe", "cards": {}, "recipes": {}, "npcs": {}}
	for kind: String in ["hero", "shop"]:
		var id := "card.snapshot_probe." + kind
		module.cards[id] = {"id": id, "kind": kind, "category": "character" if kind == "hero" else "location", "name_key": "TEST_NAME", "detail_key": "TEST_DETAIL", "art_path": "", "module_id": "snapshot_probe", "unique": true, "protected": true, "sellable": false}
	var registered := ContentCatalog.enable_module("snapshot_probe", module)
	check(registered.ok, "fixture_registered")
	if registered.ok:
		check(not GameSnapshot.decode(payload).get("ok", false), "nonempty_catalog_still_requires_hero")
		state.create_defined("card.snapshot_probe.hero", Vector2.ZERO)
		var hero_only := GameSnapshot.capture(state, shop, day, camera, progress)
		check(not GameSnapshot.decode(hero_only).get("ok", false), "nonempty_catalog_still_requires_shop")
		state.create_defined("card.snapshot_probe.shop", Vector2(300, 0))
		check(GameSnapshot.decode(GameSnapshot.capture(state, shop, day, camera, progress)).get("ok", false), "nonempty_valid_roundtrip")
		check(state.create_typed(&"hero", Vector2.ZERO).is_empty(), "typed_creation_cannot_duplicate_unique_card")
		ContentCatalog.disable_module("snapshot_probe")
	_test_recipe_mechanisms()
	_test_chapter_generation()
	_test_contact_rules()
	check(ContentCatalog.card_ids().is_empty() and ContentCatalog.recipe_ids().is_empty(), "fixture_catalog_restored")
	shop.free()
	day.free()
	print("RESET_SNAPSHOT_AUDIT: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print(("PASS " if value else "FAIL ") + label)


func _test_recipe_mechanisms() -> void:
	var catalog := {"version": 1, "cards": {}, "recipes": {}, "npcs": {}, "stories": {}, "events": {}}
	for kind: String in ["input", "output"]:
		var id := "card.reset_probe." + kind
		catalog.cards[id] = {"id": id, "kind": "reset_probe_" + kind, "category": "item", "name_key": "TEST_NAME", "detail_key": "TEST_DETAIL", "art_path": "", "unique": false, "protected": false, "sellable": true}
	var table := TableState.new()
	check(table.configure_catalog(catalog, []).ok, "isolated_fixture_catalog")
	var stack := table.create_defined("card.reset_probe.input", Vector2.ZERO, 2)
	var ids: Array[String] = []
	ids.assign(table.stacks[stack].cards)
	var recipe := {"id": "recipe.reset_probe.combine", "name_key": "TEST_NAME", "description_key": "TEST_DETAIL", "action": "craft", "duration": 1.0, "inputs": [{"card_id": "card.reset_probe.input", "count": 2}], "reusable": [], "outputs": [{"card_id": "card.reset_probe.output", "count": 1}]}
	var runner := ModuleRecipeRunner.new()
	check(runner.configure(table, {recipe.id: recipe}).ok, "recipe_index_configures")
	check(runner.matching_recipes(ids) == [recipe.id], "recipe_index_matches_repeated_material")
	var started := runner.begin(recipe.id, ids, ids[0])
	check(started.ok, "recipe_begins")
	if not started.ok:
		return
	runner.advance(0.5)
	runner.advance(5.0, true)
	check(is_equal_approx(float(runner.get_job(started.job_id).elapsed), 0.5), "paused_recipe_keeps_progress")
	var split := table.take_from(ids[1], false)
	var cancelled := runner.advance(0.0)
	check(cancelled.size() == 1 and cancelled[0].status == "cancelled" and table.card_count() == 2, "split_cancels_without_consumption")
	check(table.merge(split, stack), "recipe_participants_recombine")
	started = runner.begin(recipe.id, ids, ids[0])
	check(started.ok, "recipe_restarts_after_membership_change")
	var committed := runner.advance(1.0)
	check(committed.size() == 1 and committed[0].status == "completed" and table.card_count() == 1, "recipe_commits_atomically")
	check(table.definition_id_for_card(table.cards.keys()[0]) == "card.reset_probe.output", "recipe_creates_defined_output")
	check(runner.advance(1.0).is_empty() and table.card_count() == 1, "recipe_does_not_repeat_committed_output")
	check(runner.configure(table, {}).ok and runner.matching_recipes(ids).is_empty(), "empty_recipe_index_clears_candidates")
	var full := TableState.new()
	var capacity_catalog := catalog.duplicate(true)
	capacity_catalog.cards["card.reset_probe.actor"] = {"id": "card.reset_probe.actor", "kind": "reset_probe_actor", "category": "character", "name_key": "TEST_NAME", "detail_key": "TEST_DETAIL", "art_path": "", "unique": true, "protected": true, "sellable": false}
	capacity_catalog.npcs["npc.reset_probe.actor"] = {"id": "npc.reset_probe.actor", "card_id": "card.reset_probe.actor", "name_key": "TEST_NAME", "description_key": "TEST_DETAIL"}
	check(full.configure_catalog(capacity_catalog, []).ok, "capacity_fixture_catalog")
	full.next_card_id = 2
	for index in 8:
		full.create_defined("card.reset_probe.input", Vector2.ZERO, 20)
	full.transaction_receipts["reset_probe_reservation"] = {"created_ids": ["card_0001"]}
	var before := full.snapshot()
	check(full.card_count() == TableState.MAX_CARDS and full.create_defined("card.reset_probe.output", Vector2.ZERO).is_empty() and full.snapshot() == before, "capacity_rejects_without_mutation")
	check(not full.materialize_reserved_npc("card_0001", "card.reset_probe.actor", "npc.reset_probe.actor", Vector2.ZERO) and full.snapshot() == before, "reserved_npc_cannot_exceed_capacity")


func _test_save_store(payload: Dictionary) -> void:
	var directory := OS.get_temp_dir().path_join("cardshop_reset_audit_%s" % Time.get_ticks_usec())
	var store := SaveStore.new(directory)
	store.payload_validator = GameSnapshot.decode
	check(store.write_save("auto", payload).ok, "empty_save_writes")
	var record := store.read_save("auto")
	check(record.ok and record.payload == JSON.parse_string(JSON.stringify(payload, "", true, true)), "empty_save_reads_same_payload")
	var newer := payload.duplicate(true)
	newer.day.day = 2
	check(store.write_save("auto", newer).ok, "empty_save_rotates_backup")
	var invalid := newer.duplicate(true)
	invalid.content_generation = "obsolete_probe"
	check(not store.write_save("auto", invalid).ok and store.read_save("auto").payload.day.day == 2, "rejected_save_preserves_primary")
	var corrupt := FileAccess.open(directory.path_join("auto.json"), FileAccess.WRITE)
	corrupt.store_string("invalid_probe")
	corrupt.close()
	record = store.read_save("auto")
	check(record.ok and record.recovered and record.payload.day.day == 1, "backup_recovers_empty_save")
	var worker := StorageJobWorker.new()
	var thread := Thread.new()
	var started := thread.start(Callable(worker, "validate_and_write").bind(newer, directory, "slot_1"))
	check(started == OK, "empty_save_worker_thread_starts")
	if started == OK:
		var result: Dictionary = thread.wait_to_finish()
		check(result.get("ok", false) and result.get("payload") == newer, "empty_save_worker_validates_and_writes")
		check(store.read_save("slot_1").get("ok", false), "empty_async_save_reads_back")
	for filename: String in ["auto.json", "auto.json.bak", "auto.json.tmp", "auto.json.bak.tmp", "slot_1.json"]:
		var path := directory.path_join(filename)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)


func _test_chapter_generation() -> void:
	var checkpoint := {"table": TableState.new().snapshot(), "schema_version": 1}
	var original := checkpoint.duplicate(true)
	var prepared := ChapterSnapshot.prepare_capture(checkpoint,
		{"day": 1, "elapsed": 0.0, "seconds_per_day": 120.0}, {"zoom": 1.0, "center": [0, 0]},
		{"recipes": [], "npcs": {}}, {"stage": "inactive", "intro_index": 0, "elapsed": 0.0},
		{"name": ""}, {}, "synthetic_fingerprint")
	check(prepared.content_generation == ContentCatalog.content_generation(), "chapter_async_capture_carries_generation")
	check(checkpoint == original and not prepared.module_checkpoint.has("table"), "chapter_prepare_preserves_checkpoint")
	var decoded := ChapterSnapshot._decode_with_package(prepared, {"package_fingerprint": "different_synthetic_fingerprint"})
	check(decoded.get("reason") == "package_fingerprint_mismatch", "chapter_codec_accepts_generation_field_before_fingerprint_check")
	var unexpected := prepared.duplicate(true)
	unexpected["unexpected_probe_field"] = true
	decoded = ChapterSnapshot._decode_with_package(unexpected, {})
	check(decoded.get("reason") == "invalid_chapter_payload_fields", "chapter_codec_still_rejects_extra_fields")
	var old := prepared.duplicate(true)
	old.erase("content_generation")
	check(ChapterSnapshot.decode(old).get("error_key") == "SAVE_UNSUPPORTED_VERSION", "chapter_direct_decode_rejects_missing_generation_before_package_read")
	check(ChapterSnapshot.validate_prepared_capture(old).get("error_key") == "SAVE_UNSUPPORTED_VERSION", "chapter_async_validation_rejects_missing_generation")
	old.content_generation = "obsolete_probe"
	check(ChapterSnapshot.decode(old).get("error_key") == "SAVE_UNSUPPORTED_VERSION", "chapter_direct_decode_rejects_old_generation")
	check(ChapterSnapshot.validate_prepared_capture(old).get("error_key") == "SAVE_UNSUPPORTED_VERSION", "chapter_async_validation_rejects_old_generation")
	old.content_generation = 42
	check(ChapterSnapshot._decode_with_package(old, {}).get("error_key") == "SAVE_UNSUPPORTED_VERSION", "chapter_codec_rejects_non_string_generation")
	var directory := OS.get_temp_dir().path_join("cardshop_rejected_async_probe_%s" % Time.get_ticks_usec())
	var worker := StorageJobWorker.new()
	var thread := Thread.new()
	var started := thread.start(Callable(worker, "validate_and_write").bind(old, directory, "auto"))
	check(started == OK, "chapter_storage_worker_thread_starts")
	if started == OK:
		var result: Dictionary = thread.wait_to_finish()
		check(result.get("error_key") == "SAVE_UNSUPPORTED_VERSION" and not DirAccess.dir_exists_absolute(directory), "chapter_worker_rejects_generation_without_disk_mutation")


func _test_contact_rules() -> void:
	var base := ContentCatalog._base_data.duplicate(true)
	var table := TableState.new()
	var story := ProbeStory.new()
	ContentCatalog._base_data["runtime_rules"] = {}
	check(ChapterSnapshot._contact_interest_error(table, story).is_empty(), "empty_contact_rules_require_no_old_characters")
	var rule := {"permission_fact": "fact.probe.permission", "interest_facts": ["fact.probe.first", "fact.probe.second"],
		"visit_story": "story.probe.visit", "first_receipt": "probe/first", "arrival_fact": "fact.probe.arrived", "visit_operation": "operation.probe.visit",
		"return_story": "story.probe.return", "revisit_receipt_prefix": "probe/return/"}
	ContentCatalog._base_data.runtime_rules = {"contact_visits": {"probe": rule}}
	story.state.facts = ["fact.probe.permission"]
	check(ChapterSnapshot._contact_interest_error(table, story) == "chapter_contact_interest_missing_or_ambiguous", "configured_contact_requires_one_interest")
	story.state.facts.append("fact.probe.first")
	check(ChapterSnapshot._contact_interest_error(table, story).is_empty(), "configured_contact_accepts_single_interest")
	story.state.completed = ["story.probe.visit"]
	check(ChapterSnapshot._contact_interest_error(table, story) == "chapter_contact_visit_without_day_record", "configured_contact_requires_day_record")
	table.transaction_receipts["probe/first"] = {"status": "completed"}
	check(ChapterSnapshot._contact_interest_error(table, story) == "chapter_contact_visit_without_arrival", "configured_contact_requires_arrival_receipt")
	table.transaction_receipts["probe/first"].grants_facts = ["fact.probe.arrived"]
	check(ChapterSnapshot._contact_interest_error(table, story) == "chapter_contact_visit_without_operation", "configured_contact_requires_operation_receipt")
	table.transaction_receipts["probe/operation"] = {"status": "completed", "kind": "chapter_operation", "operation_id": "operation.probe.visit"}
	check(ChapterSnapshot._contact_interest_error(table, story).is_empty(), "configured_contact_accepts_complete_evidence")
	story.state.story_id = "story.probe.return"
	check(ChapterSnapshot._contact_interest_error(table, story) == "chapter_return_visit_without_day_record", "configured_return_requires_day_record")
	table.transaction_receipts["probe/return/1"] = {"status": "completed"}
	check(ChapterSnapshot._contact_interest_error(table, story).is_empty(), "configured_return_accepts_evidence")
	ContentCatalog._base_data.runtime_rules.contact_visits.probe.interest_facts = ["fact.probe.first", "fact.probe.first"]
	check(ChapterSnapshot._contact_interest_error(table, story) == "invalid_contact_visit_interests", "configured_interests_must_be_distinct")
	ContentCatalog._base_data = base
