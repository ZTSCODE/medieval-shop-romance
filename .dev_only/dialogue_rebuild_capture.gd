extends "res://tests/bottom_dialogue_runtime_suite.gd"

func _check(label: String, condition: bool) -> void:
	if not condition and label.begins_with("dialogue fits viewport"):
		var ui: DialogueOverlay = app.dialogue_overlay
		print("BOUNDS root=%s paper=%s stage=%s" % [ui._root.get_rect(),ui.text_panel.get_rect(),ui._stage.get_rect()])
	super._check(label,condition)
