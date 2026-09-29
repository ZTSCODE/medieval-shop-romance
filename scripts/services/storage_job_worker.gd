class_name StorageJobWorker
extends RefCounted

const Snapshot = preload("res://scripts/content/chapter_snapshot.gd")
const Store = preload("res://scripts/services/save_store.gd")
const GameSnapshotScript = preload("res://scripts/services/game_snapshot.gd")


func validate_and_write(payload: Dictionary, directory: String, slot: String) -> Dictionary:
	var validated: Dictionary
	if payload.get("state_version") == 9:
		validated = Snapshot.validate_prepared_capture(payload)
	else:
		validated = GameSnapshotScript.decode(payload)
		if validated.ok:
			validated = {"ok": true, "payload": payload}
	if not validated.ok:
		return validated
	var store := Store.new(directory)
	store.payload_validator = GameSnapshotScript.decode
	var written := store.write_save(slot, validated.payload, true)
	if not written.ok:
		return written
	return {"ok": true, "saved_at": written.saved_at, "payload": validated.payload}


func read_slot(directory: String, slot: String) -> Dictionary:
	var store := Store.new(directory)
	store.payload_validator = GameSnapshotScript.decode
	return store.read_save(slot)
