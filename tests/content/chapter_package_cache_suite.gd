extends SceneTree

const Package = preload("res://scripts/content/chapter_package.gd")
const Bundle = preload("res://scripts/content/module_bundle.gd")
const Runner = preload("res://scripts/content/module_recipe_runner.gd")
const DIRECTORY := "res://outputs/content-production/package-cache-suite"
var checks := 0
var failures := 0
var mirror := ""
var manifest := ""
var package: Dictionary
var files: Array[String] = []


func _initialize() -> void:
	var baseline := ContentCatalog.snapshot_context()
	var locale := TranslationServer.get_locale()
	package = Package.load_package()
	_check("real package validates", package.ok)
	if not package.ok:
		push_error(str(package))
		quit(1)
		return
	_clone()
	var first := Package.read(manifest)
	_check("isolated package initially validates", first.ok)
	var fingerprint: String = first.package_fingerprint
	var untouched := Runner.canonical_digest(first)
	first.bundle.content.cards.clear()
	first.operations.clear()
	first.relationship_catalog.milestones.clear()
	first.catalog_context.catalog.npcs.clear()
	first.bundle.translations_by_locale.en.clear()
	var second := Package.read(manifest)
	_check("caller cannot mutate cached nested dictionaries", Runner.canonical_digest(second) == untouched)
	_check("cached package contains only plain data", _plain(second))
	_test_every_module_input()
	_test_same_second_and_size()
	_test_translation_only(fingerprint)
	_test_relationship_translation(fingerprint)
	_test_base_inputs()
	_check("all mutations remained in isolated module", Runner.canonical_digest(ContentCatalog.snapshot_context()) == Runner.canonical_digest(baseline))
	_check("cache does not install translations or change locale", TranslationServer.get_locale() == locale)
	print("CHAPTER_PACKAGE_CACHE_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _clone() -> void:
	mirror = DIRECTORY + "/module-" + str(Time.get_ticks_usec())
	manifest = mirror + "/module.json"
	files.assign(["module.json", package.bundle.manifest.content, package.bundle.manifest.stories])
	for relative: String in package.bundle.manifest.translations:
		files.append(relative)
	for sidecar: String in Package.SIDECARS:
		files.append("source/" + sidecar + ".json")
	for relative: String in files:
		_write(mirror.path_join(relative), FileAccess.get_file_as_bytes(Package.MANIFEST_PATH.get_base_dir().path_join(relative)))


func _test_every_module_input() -> void:
	for relative: String in files:
		var path := mirror.path_join(relative)
		var original := FileAccess.get_file_as_bytes(path)
		_check("warm cache before corrupting " + relative, Package.read(manifest).ok)
		var broken := original.duplicate()
		var first := 3 if broken.size() > 3 and broken[0] == 0xef and broken[1] == 0xbb and broken[2] == 0xbf else 0
		broken[first] = 33
		_write(path, broken)
		var result := Package.read(manifest)
		_check("content hash rejects changed " + relative, not result.ok and result.error_key == "SAVE_UNSUPPORTED_VERSION")
		_write(path, original)
		_check("repaired input revalidates " + relative, Package.read(manifest).ok)
		var absolute := ProjectSettings.globalize_path(path)
		_check("remove isolated input " + relative, DirAccess.remove_absolute(absolute) == OK)
		result = Package.read(manifest)
		_check("missing input cannot reuse old cache " + relative, not result.ok and result.error_key == "SAVE_UNSUPPORTED_VERSION")
		_write(path, original)
		_check("restored input can load again " + relative, Package.read(manifest).ok)


func _test_same_second_and_size() -> void:
	var path := mirror + "/source/operations.json"
	var original := FileAccess.get_file_as_bytes(path)
	var fraction := fposmod(Time.get_unix_time_from_system(), 1.0)
	if fraction > 0.6:
		OS.delay_msec(int(ceil((1.02 - fraction) * 1000)))
	_write(path, original)
	_check("warm unchanged-content cache in current second", Package.read(manifest).ok)
	var timestamp := FileAccess.get_modified_time(path)
	var broken := original.duplicate()
	broken[0] = 33
	_write(path, broken)
	_check("test mutation preserves byte length", FileAccess.get_file_as_bytes(path).size() == original.size())
	_check("test mutation has identical second-resolution mtime", FileAccess.get_modified_time(path) == timestamp)
	_check("same-size same-second mutation invalidates cache", not Package.read(manifest).ok)
	_write(path, original)
	_check("same-second restoration does not retain failure cache", Package.read(manifest).ok)


func _test_translation_only(fingerprint: String) -> void:
	var path := mirror + "/source/operations_localization.csv"
	var original := FileAccess.get_file_as_bytes(path)
	var input := FileAccess.open(path, FileAccess.READ)
	var rows: Array[PackedStringArray] = []
	while not input.eof_reached():
		var row := input.get_csv_line()
		if row.size() > 1:
			rows.append(row)
	input.close()
	var en_index := rows[0].find("en")
	var key_index := rows[0].find("key")
	if key_index < 0:
		key_index = rows[0].find("keys")
	_check("fixture contains key and English columns", en_index >= 0 and key_index >= 0)
	var text_key := ""
	for index in range(1, rows.size()):
		if rows[index][key_index] == "CH01_TOPIC_ARRIVAL_ROAD":
			text_key = rows[index][key_index]
			rows[index][en_index] = "A quiet roadside"
	_check("actual story topic text exists", not text_key.is_empty())
	var output := FileAccess.open(path, FileAccess.WRITE)
	for row: PackedStringArray in rows:
		output.store_csv_line(row)
	output.close()
	var result := Package.read(manifest)
	_check("text-only edit revalidates package", result.ok)
	if result.ok:
		_check("text-only edit refreshes cached translation value", result.bundle.translations_by_locale.en[text_key] == "A quiet roadside")
		_check("text-only edit preserves semantic save fingerprint", result.package_fingerprint == fingerprint)
	_write(path, original)
	_check("restored text is loaded rather than stale changed cache", Package.read(manifest).bundle.translations_by_locale.en[text_key] != "A quiet roadside")


func _test_base_inputs() -> void:
	var inputs := Package._input_hashes(manifest)
	for path: String in [Bundle.BASE_CONTENT, Bundle.BASE_TRANSLATIONS]:
		var absolute := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
		_check("base input included in every cache proof " + path, inputs.ok and inputs.hashes.has(absolute))
		var fixture := mirror + "/base-copy-" + path.get_file()
		var bytes := FileAccess.get_file_as_bytes(path)
		_write(fixture, bytes)
		var paths: Array[String] = [fixture]
		var before := Package._hash_paths(paths)
		var modified := bytes.duplicate()
		modified[0] = 33
		_write(fixture, modified)
		var after := Package._hash_paths(paths)
		_check("shared proof detects base-input content changes " + path, before.hashes != after.hashes)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
		_check("shared proof fails closed on missing base input " + path, not Package._hash_paths(paths).ok)


func _test_relationship_translation(fingerprint: String) -> void:
	var path := mirror + "/source/relationships_localization.csv"
	var original := FileAccess.get_file_as_bytes(path)
	var input := FileAccess.open(path, FileAccess.READ)
	var rows: Array[PackedStringArray] = []
	while not input.eof_reached():
		var row := input.get_csv_line()
		if row.size() > 1:
			rows.append(row)
	input.close()
	var en_index := rows[0].find("en")
	var key_index := rows[0].find("keys")
	var text_key := "CH01_REL_CORIN_FOREST_MEETING_DETAIL"
	for index in range(1, rows.size()):
		if rows[index][key_index] == text_key:
			rows[index][en_index] = "A new memory of the roadside."
	var output := FileAccess.open(path, FileAccess.WRITE)
	for row: PackedStringArray in rows:
		output.store_csv_line(row)
	output.close()
	var result := Package.read(manifest)
	_check("relationship text-only edit refreshes cache", result.ok and result.bundle.translations_by_locale.en[text_key] == "A new memory of the roadside.")
	_check("relationship prose does not change earned-reward fingerprint", result.ok and result.package_fingerprint == fingerprint)
	_write(path, original)
	_check("restored relationship text is not stale", Package.read(manifest).bundle.translations_by_locale.en[text_key] != "A new memory of the roadside.")


func _plain(value: Variant) -> bool:
	if value is Dictionary:
		for item: Variant in value.values():
			if not _plain(item):
				return false
		return true
	if value is Array:
		for item: Variant in value:
			if not _plain(item):
				return false
		return true
	return typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]


func _write(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check("write isolated cache fixture", file != null)
	if file != null:
		file.store_buffer(data)
		file.close()


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("FAIL: " + label)
