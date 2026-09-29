class_name SaveStore
extends RefCounted

const FORMAT_ID := "medieval_shop_romance"
const SCHEMA_VERSION := 1
const SLOTS := ["auto", "slot_1", "slot_2", "slot_3"]
const MAX_SAVE_BYTES := 4 * 1024 * 1024
const MAX_DEPTH := 40
const MAX_NODES := 100000
const MAX_EXACT_INTEGER := 9007199254740991

var directory: String
var payload_validator: Callable
var _visited_nodes := 0
var _ui_slot_cache: Dictionary = {}


func _init(save_directory: String = "user://saves") -> void:
	directory = ProjectSettings.globalize_path(save_directory).simplify_path()


func write_save(slot: String, payload: Dictionary, prevalidated_payload: bool = false) -> Dictionary:
	if not SLOTS.has(slot):
		return _failure("SAVE_INVALID_SLOT")
	_visited_nodes = 0
	if not _is_json_safe(payload):
		return _failure("SAVE_INVALID_DATA")
	var payload_text := JSON.stringify(payload, "", true, true)
	if payload_text.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return _failure("SAVE_TOO_LARGE")
	var normalized: Variant = JSON.parse_string(payload_text)
	if not normalized is Dictionary:
		return _failure("SAVE_INVALID_DATA")
	var envelope := {
		"format": FORMAT_ID,
		"schema": SCHEMA_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true) + "Z",
		"payload": normalized,
	}
	envelope["checksum"] = _checksum(envelope)
	var text := JSON.stringify(envelope, "\t", true, true) + "\n"
	if text.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return _failure("SAVE_TOO_LARGE")
	var path := _slot_path(slot)
	var previous_started := HitchProbe.stamp()
	var previous := _read_file(path)
	var backup := _read_file(path + ".bak")
	HitchProbe.record("store_write_previous", previous_started)
	if previous.error_key == "SAVE_UNSUPPORTED_VERSION" or backup.error_key == "SAVE_UNSUPPORTED_VERSION":
		return _failure("SAVE_UNSUPPORTED_VERSION")
	if previous.error_key == "SAVE_READ_FAILED" or backup.error_key == "SAVE_READ_FAILED":
		return _failure("SAVE_READ_FAILED")
	if not _make_directory():
		return _failure("SAVE_WRITE_FAILED")
	var temporary := path + ".tmp"
	var temp_started := HitchProbe.stamp()
	if not _write_text(temporary, text):
		_remove_temporary(temporary)
		return _failure("SAVE_WRITE_FAILED")
	var temporary_result := _read_file(temporary, prevalidated_payload)
	HitchProbe.record("store_write_temp_verify", temp_started)
	if not temporary_result.ok:
		_remove_temporary(temporary)
		if temporary_result.error_key == "SAVE_UNSUPPORTED_VERSION":
			return _failure("SAVE_UNSUPPORTED_VERSION")
		return _failure("SAVE_WRITE_FAILED")
	if previous.ok:
		var backup_started := HitchProbe.stamp()
		var backup_temporary := path + ".bak.tmp"
		if DirAccess.copy_absolute(path, backup_temporary) != OK:
			_remove_temporary(temporary)
			_remove_temporary(backup_temporary)
			return _failure("SAVE_WRITE_FAILED")
		if not _read_file(backup_temporary, prevalidated_payload).ok or DirAccess.rename_absolute(backup_temporary, path + ".bak") != OK:
			_remove_temporary(temporary)
			_remove_temporary(backup_temporary)
			return _failure("SAVE_WRITE_FAILED")
		HitchProbe.record("store_write_backup", backup_started)
	if DirAccess.rename_absolute(temporary, path) != OK:
		_remove_temporary(temporary)
		return _failure("SAVE_WRITE_FAILED")
	_ui_slot_cache[slot] = {"stamp": _slot_stamp(slot), "entry": _slot_summary(slot, {"ok": true, "error_key": "", "payload": normalized, "saved_at": envelope.saved_at, "recovered": false})}
	return {"ok": true, "error_key": "", "saved_at": envelope.saved_at}


func read_save(slot: String) -> Dictionary:
	if not SLOTS.has(slot):
		return _failure("SAVE_INVALID_SLOT")
	var path := _slot_path(slot)
	var primary := _read_file(path)
	if primary.ok or primary.error_key == "SAVE_UNSUPPORTED_VERSION":
		return primary
	var backup := _read_file(path + ".bak")
	if backup.error_key == "SAVE_UNSUPPORTED_VERSION":
		return backup
	if backup.ok:
		backup.recovered = true
		return backup
	if primary.error_key == "SAVE_NOT_FOUND" and backup.error_key != "SAVE_NOT_FOUND":
		return backup
	return primary


func list_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: String in SLOTS:
		result.append(_slot_summary(slot, read_save(slot)))
	return result


func list_slots_quick() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: String in SLOTS:
		var stamp := _slot_stamp(slot)
		var cached: Dictionary = _ui_slot_cache.get(slot, {})
		if cached.get("stamp") != stamp:
			cached = {"stamp": stamp, "entry": _slot_summary(slot, read_save(slot))}
			_ui_slot_cache[slot] = cached
		result.append((cached.entry as Dictionary).duplicate(true))
	return result


func note_external_write(slot: String, payload: Dictionary, saved_at: String) -> void:
	if not SLOTS.has(slot):
		return
	_ui_slot_cache[slot] = {"stamp": _slot_stamp(slot), "entry": _slot_summary(slot,
		{"ok": true, "error_key": "", "payload": payload, "saved_at": saved_at, "recovered": false})}


func _slot_summary(slot: String, entry: Dictionary) -> Dictionary:
	var path := _slot_path(slot)
	var payload: Dictionary = entry.get("payload", {})
	var day_number := 0
	var card_total := 0
	var day_data: Variant = payload.get("day", {})
	if day_data is Dictionary and _is_whole_number(day_data.get("day")):
		day_number = maxi(0, int(day_data.day))
	var table_data: Variant = payload.get("table", {})
	if table_data is Dictionary:
		var cards: Variant = table_data.get("cards")
		if cards is Dictionary or cards is Array:
			card_total = cards.size()
	return {"slot": slot, "exists": FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"),
		"valid": entry.ok, "saved_at": entry.get("saved_at", ""), "day": day_number,
		"card_count": card_total, "session_mode": payload.get("session_mode", "legacy"),
		"error_key": entry.error_key, "recovered": entry.recovered}


func _slot_stamp(slot: String) -> String:
	var path := _slot_path(slot)
	return _file_stamp(path) + ":" + _file_stamp(path + ".bak")


func _file_stamp(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"


func _slot_path(slot: String) -> String:
	return directory.path_join(slot + ".json")


func _read_file(path: String, skip_payload_validator: bool = false) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("SAVE_NOT_FOUND")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("SAVE_READ_FAILED")
	var length := file.get_length()
	if length > MAX_SAVE_BYTES:
		file.close()
		return _failure("SAVE_TOO_LARGE")
	if length == 0:
		file.close()
		return _failure("SAVE_CORRUPT")
	var bytes := file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		return _failure("SAVE_READ_FAILED")
	var parser := JSON.new()
	var parse_started := HitchProbe.stamp()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return _failure("SAVE_CORRUPT")
	HitchProbe.record("store_read_parse", parse_started)
	var envelope: Dictionary = parser.data
	if envelope.get("format") != FORMAT_ID or not _is_whole_number(envelope.get("schema")):
		return _failure("SAVE_CORRUPT")
	if int(envelope.schema) != SCHEMA_VERSION:
		return _failure("SAVE_UNSUPPORTED_VERSION")
	if not envelope.get("payload") is Dictionary or not envelope.get("saved_at") is String or not envelope.get("checksum") is String:
		return _failure("SAVE_CORRUPT")
	var date_pattern := RegEx.new()
	date_pattern.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
	if date_pattern.search(envelope.saved_at) == null or envelope.checksum.length() != 64:
		return _failure("SAVE_CORRUPT")
	_visited_nodes = 0
	var checksum_started := HitchProbe.stamp()
	if not _is_json_safe(envelope.payload) or envelope.checksum != _checksum(envelope):
		return _failure("SAVE_CORRUPT")
	HitchProbe.record("store_read_checksum", checksum_started)
	var decoded: Variant = null
	if payload_validator.is_valid() and not skip_payload_validator:
		var validate_started := HitchProbe.stamp()
		var validation: Variant = payload_validator.call(envelope.payload)
		HitchProbe.record("store_read_payload_decode", validate_started)
		if not validation is Dictionary or not validation.get("ok", false):
			var key: String = str(validation.get("error_key", "SAVE_CORRUPT")) if validation is Dictionary else "SAVE_CORRUPT"
			return _failure(key)
		decoded = validation
	return {"ok": true, "error_key": "", "payload": envelope.payload, "saved_at": envelope.saved_at, "recovered": false, "decoded": decoded}


func _checksum(envelope: Dictionary) -> String:
	var signed_fields := {
		"format": envelope.get("format"),
		"schema": int(envelope.get("schema", 0)),
		"saved_at": envelope.get("saved_at"),
		"payload": envelope.get("payload"),
	}
	return JSON.stringify(signed_fields, "", true, true).sha256_text()


func _is_json_safe(value: Variant, depth: int = 0) -> bool:
	_visited_nodes += 1
	if depth > MAX_DEPTH or _visited_nodes > MAX_NODES:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return true
		TYPE_INT:
			return value >= -MAX_EXACT_INTEGER and value <= MAX_EXACT_INTEGER
		TYPE_FLOAT:
			return is_finite(value) and absf(value) <= MAX_EXACT_INTEGER
		TYPE_STRING:
			return value.length() <= MAX_SAVE_BYTES
		TYPE_ARRAY:
			for child: Variant in value:
				if not _is_json_safe(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if typeof(key) != TYPE_STRING or key.length() > MAX_SAVE_BYTES or not _is_json_safe(value[key], depth + 1):
					return false
			return true
	return false


func _is_whole_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and absf(float(value)) <= MAX_EXACT_INTEGER and float(value) == floorf(float(value))


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var successful := file.get_error() == OK
	file.close()
	return successful


func _remove_temporary(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _make_directory() -> bool:
	var ancestor := directory
	while not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor):
			return false
		var parent := ancestor.get_base_dir()
		if parent == ancestor or parent.is_empty():
			break
		ancestor = parent
	return DirAccess.make_dir_recursive_absolute(directory) == OK


func _failure(key: String) -> Dictionary:
	return {"ok": false, "error_key": key, "payload": {}, "saved_at": "", "recovered": false}
