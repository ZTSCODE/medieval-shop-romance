class_name TableSound
extends Node
## Backward-compatible board facade. All actual playback uses AudioEvents.
var enabled := true
const EVENTS := {&"pick": "card.pick", &"pickup": "card.pick", &"grab": "card.pick", &"lift": "card.pick", &"take": "card.pick", &"drop": "card.drop", &"land": "card.land", &"release": "card.drop", &"stack": "card.stack", &"split": "card.split", &"add": "card.unfold", &"cancel": "card.cancel", &"reject": "card.reject", &"select": "card.select", &"hover": "card.hover", &"target": "card.target", &"remove": "card.remove"}

func play_cue(kind: StringName) -> void:
	if enabled:
		AudioEvents.play_event(String(EVENTS.get(kind, "card.drop")))
