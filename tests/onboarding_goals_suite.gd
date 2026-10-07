extends SceneTree

var failures := 0


func _initialize() -> void:
	var goals := OnboardingGoals.new()
	_check("definition loads three stages", goals.stages.size() == 3)
	_check("starts at first stage", goals.stage_index == 0 and not goals.is_finished())
	_check("unknown event ignored", not goals.report(&"nothing_happened"))
	_check("later-stage event only remembered", not goals.report(&"journal_recipes_opened") and goals.seen_events.has(&"journal_recipes_opened"))
	# 第一阶段：基础操作（拖动桌面、缩放、拖一张卡）加上把“你”拖到林子上。
	_check("pan completes goal", goals.report(&"camera_panned") and goals.is_goal_complete("pan_table"))
	_check("repeat report is idempotent", not goals.report(&"camera_panned"))
	goals.report(&"camera_zoomed")
	_check("dragging one card completes its goal", goals.report(&"card_dragged") and goals.is_goal_complete("drag_card"))
	_check("first stage still open until the wood is walked", goals.stage_index == 0)
	goals.report(&"opening_explored")
	_check("first stage completes with the wood", goals.stage_index == 1 and goals.is_goal_complete("walk_wood"))
	goals.report(&"story_completed:story.messenger.edge")
	_check("second stage waits for the path", goals.stage_index == 1 and goals.is_goal_complete("meet_messenger"))
	goals.report(&"explore_completed:card.loc.stream_path")
	_check("stage still open with one goal left", goals.stage_index == 1)
	goals.report(&"story_completed:story.messenger.catch_up")
	_check("stage advances when all done", goals.stage_index == 2)
	_check("earlier event carried into new stage", goals.is_goal_complete("open_recipes"))
	var saved := goals.to_data()
	var restored := OnboardingGoals.new()
	_check("restore accepts saved data", restored.restore(saved))
	_check("restore derives stage", restored.stage_index == 2 and restored.is_goal_complete("open_recipes"))
	_check("restore rejects garbage", not OnboardingGoals.new().restore({"version": 99}))
	var tampered := OnboardingGoals.new()
	tampered.restore({"version": 1, "completed": ["ghost_goal", "pan_table"], "seen": [7]})
	_check("restore drops unknown ids", tampered.completed.size() == 1 and tampered.seen_events.is_empty())
	goals.report(&"hero_focused")
	goals.report(&"time_mode_changed", "speed=3")
	goals.report(&"journal_npcs_opened")
	_check("all stages finish", goals.is_finished())
	_check("history explains causes", goals.debug_text().contains("carried journal_recipes_opened") and goals.debug_text().contains("report(speed=3) time_mode_changed"))
	_check("finished ignores reports", not goals.report(&"camera_zoomed"))
	_check("sanitize rejects non-dictionary", OnboardingGoals.sanitize("x").is_empty())
	_check("sanitize keeps strings only", OnboardingGoals.sanitize({"version": 1, "completed": ["pan_table", 3], "seen": ["camera_zoomed"]}).completed == ["pan_table"])
	_check("sanitize of missing field is fresh-start", OnboardingGoals.sanitize(null).is_empty())
	var fresh := OnboardingGoals.new()
	_check("fresh data restores to stage zero", fresh.restore(OnboardingGoals.fresh_data()) and fresh.stage_index == 0 and fresh.completed.is_empty())
	print("ONBOARDING_GOALS failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
