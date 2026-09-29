class_name PlayerIdentity
extends RefCounted

const MAX_NAME_UNITS := 12
const LEGACY_MAX_NAME_LENGTH := 20

var name := ""


func set_name(value: String) -> bool:
	if not name_error(value).is_empty():
		return false
	name = normalize(value)
	return true


func to_data() -> Dictionary:
	return {"name": name}


func restore(data: Variant) -> bool:
	if not validate_data(data).is_empty():
		return false
	name = String(data.name)
	return true


static func name_error(value: String) -> String:
	var syntax_error := _syntax_error(value)
	if not syntax_error.is_empty():
		return syntax_error
	if name_units(value) > MAX_NAME_UNITS:
		return "NAME_ENTRY_TOO_LONG"
	return ""


static func name_units(value: String) -> int:
	var normalized := normalize(value)
	var units := 0
	for index: int in normalized.length():
		units += 1 if normalized.unicode_at(index) <= 0x7F else 2
	return units


static func _syntax_error(value: String) -> String:
	var controls := RegEx.new()
	controls.compile("[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}]")
	if controls.search(value) != null:
		return "NAME_ENTRY_INVALID"
	var normalized := normalize(value)
	if normalized.is_empty():
		return "NAME_ENTRY_REQUIRED"
	return ""


static func normalize(value: String) -> String:
	var first := 0
	var last := value.length()
	while first < last and _is_space(value.unicode_at(first)):
		first += 1
	while last > first and _is_space(value.unicode_at(last - 1)):
		last -= 1
	return value.substr(first, last - first)


static func validate_data(data: Variant) -> String:
	if not data is Dictionary or data.size() != 1 or not data.get("name") is String:
		return "Player identity fields are invalid"
	if data.name.is_empty():
		return ""
	# 旧存档仍接受历史二十字上限；新建名字单独遵循当前额度。
	if not _syntax_error(data.name).is_empty() or data.name.length() > LEGACY_MAX_NAME_LENGTH or normalize(data.name) != data.name:
		return "Player name is invalid"
	return ""


static func _is_space(code: int) -> bool:
	return code in [32, 0xA0, 0x1680, 0x202F, 0x205F, 0x3000] or (code >= 0x2000 and code <= 0x200A)
