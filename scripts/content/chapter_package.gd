class_name ChapterPackage
extends RefCounted

const Bundle = preload("res://scripts/content/module_bundle.gd")
const Factory = preload("res://scripts/content/module_world_factory.gd")
const Runner = preload("res://scripts/content/module_recipe_runner.gd")
const Operations = preload("res://scripts/content/chapter_operation_runner.gd")
const Services = preload("res://scripts/content/chapter_service_effects.gd")
const Relationships = preload("res://scripts/content/chapter_relationship_progress.gd")
const Customers = preload("res://scripts/content/chapter_customer_queue.gd")
const MANIFEST_PATH := "res://data/modules/chapter_01/module.json"
const SIDECARS := ["action_bindings", "events", "scene_rules", "operations", "story_topics", "market", "services", "relationships", "customers"]
static var _validated_cache: Dictionary = {}


# 纯读取与候选验证，不启用全局目录，不装翻译，不读取或写入玩家存档。
static func load_package() -> Dictionary:
	return read(MANIFEST_PATH)


static func read(manifest_path: String = MANIFEST_PATH) -> Dictionary:
	var identity := ProjectSettings.globalize_path(manifest_path).replace("\\", "/").simplify_path()
	var inputs := _input_hashes(manifest_path)
	if not inputs.ok:
		_validated_cache.erase(identity)
		return inputs
	var previous: Dictionary = _validated_cache.get(identity, {})
	if previous.get("input_hashes") == inputs.hashes:
		# 只保存普通数据，绝不复用牌桌、剧情会话、工作锁或任何运行对象。
		var cached: Dictionary = previous.package.duplicate(true)
		_refresh_art_report(cached)
		return cached
	_validated_cache.erase(identity)
	var result := _read_uncached(manifest_path)
	if not result.ok:
		return result
	# 校验期间源文件被编辑时拒绝本次结果；不能给混合版本盖上新指纹。
	var after := _input_hashes(manifest_path)
	if not after.ok or after.hashes != inputs.hashes:
		return _failure("package_changed_during_validation")
	if _validated_cache.size() >= 8:
		_validated_cache.erase(_validated_cache.keys()[0])
	_validated_cache[identity] = {"input_hashes": inputs.hashes.duplicate(true), "package": result.duplicate(true)}
	return result


static func _read_uncached(manifest_path: String) -> Dictionary:
	var bundle := Bundle.new().read_bundle(manifest_path)
	if not bundle.get("ok", false):
		return _failure("package_bundle_unavailable: " + str(bundle.get("error", "")))
	var root := ProjectSettings.globalize_path(manifest_path).replace("\\", "/").simplify_path().get_base_dir()
	var sections := {}
	for name: String in ["action_bindings", "events", "scene_rules", "operations", "story_topics"]:
		var path := Bundle._resolve_path(root, "source/" + name + ".json")
		if not path.ok:
			return _failure(str(path.error))
		var document := Bundle._read_json(path.path)
		if not document.ok:
			return _failure("package_sidecar_unavailable: " + name + ": " + str(document.error))
		var data: Dictionary = document.data
		var field := {"action_bindings": "bindings", "events": "events", "scene_rules": "rules", "operations": "operations", "story_topics": "topics"}[name] as String
		var allowed := ["schema_version", "module_id", field]
		if data.has("status"):
			allowed.append("status")
			if not data.status is String:
				return _failure("invalid_package_sidecar_status")
		if not _fields(data, allowed) or not _version_one(data.schema_version) or data.module_id != "chapter_01" or not data[field] is Dictionary:
			return _failure("invalid_package_sidecar: " + name)
		sections[name] = data[field]
	if sections.story_topics.size() != bundle.stories.size():
		return _failure("incomplete_package_story_topics")
	for story_id: Variant in sections.story_topics:
		var key: Variant = sections.story_topics[story_id]
		if not story_id is String or not bundle.stories.has(story_id) or not key is String or key.is_empty():
			return _failure("unknown_or_invalid_package_story_topic")
		for locale: String in ["en", "zh_CN"]:
			if not bundle.translations_by_locale[locale].has(key):
				return _failure("missing_story_topic_translation: " + locale + ": " + key)
	var market_path := Bundle._resolve_path(root, "source/market.json")
	if not market_path.ok:
		return _failure(str(market_path.error))
	var market_file := Bundle._read_json(market_path.path)
	if not market_file.ok:
		return _failure("package_market_unavailable: " + str(market_file.error))
	var market_data: Dictionary = market_file.data
	var market_fields := ["version", "module_id", "offers", "sources"]
	if market_data.has("price_evidence"):
		market_fields.append("price_evidence")
		if not market_data.price_evidence is Dictionary:
			return _failure("invalid_package_price_evidence")
		for value: Variant in market_data.price_evidence.values():
			if not value is String:
				return _failure("invalid_package_price_evidence")
	if not _fields(market_data, market_fields) or not _version_one(market_data.version) or market_data.module_id != "chapter_01":
		return _failure("invalid_package_market")
	var market := {"offers": market_data.offers, "sources": market_data.sources}
	var service_path := Bundle._resolve_path(root, "source/services.json")
	if not service_path.ok:
		return _failure(str(service_path.error))
	var service_file := Bundle._read_json(service_path.path)
	if not service_file.ok:
		return _failure("package_services_unavailable: " + str(service_file.error))
	var service_catalog: Dictionary = service_file.data
	if not service_catalog.get("workbench") is Dictionary:
		return _failure("package_workbench_policy_unavailable")
	for section: String in ["hearth", "consignment"]:
		if not service_catalog.get(section) is Dictionary:
			return _failure("invalid_package_service_section")
		for field: String in ["name_key", "description_key"]:
			var key: Variant = service_catalog[section].get(field)
			for locale: String in ["en", "zh_CN"]:
				if not key is String or not bundle.translations_by_locale[locale].has(key):
					return _failure("missing_service_translation: " + locale + ": " + str(key))
	# 当前包仍为开发包；缺美术保留报告，不能伪称正式美术或完整章节已完成。
	var base := Bundle._read_json(Bundle.BASE_CONTENT)
	if not base.ok:
		return _failure("base_catalog_unavailable")
	var world := Factory.create(bundle, sections.action_bindings, sections.events, sections.scene_rules, market, true, sections.operations, base.data, service_catalog)
	if not world.ok:
		return _failure("invalid_package_world: " + str(world.error))
	var operation_error := Operations.validate_catalog(sections.operations, world.table, world.story, Services.workbench_policy(service_catalog))
	if not operation_error.is_empty():
		return _failure("invalid_package_operations: " + operation_error)
	var relationship_path := Bundle._resolve_path(root, "source/relationships.json")
	if not relationship_path.ok:
		return _failure(str(relationship_path.error))
	var relationship_file := Bundle._read_json(relationship_path.path)
	if not relationship_file.ok:
		return _failure("package_relationships_unavailable: " + str(relationship_file.error))
	var relationship_catalog: Dictionary = relationship_file.data
	var relationship_error := Relationships.validate_catalog(relationship_catalog, world.table, world.story, sections.operations, sections.events, Services.workbench_policy(service_catalog))
	if not relationship_error.is_empty():
		return _failure("invalid_package_relationships: " + relationship_error)
	for milestone: Dictionary in relationship_catalog.milestones.values():
		for field: String in ["title_key", "detail_key"]:
			for locale: String in ["en", "zh_CN"]:
				if not bundle.translations_by_locale[locale].has(milestone[field]):
					return _failure("missing_relationship_translation: " + locale + ": " + milestone[field])
	var customer_path := Bundle._resolve_path(root, "source/customers.json")
	if not customer_path.ok:
		return _failure(str(customer_path.error))
	var customer_file := Bundle._read_json(customer_path.path)
	if not customer_file.ok:
		return _failure("package_customers_unavailable: " + str(customer_file.error))
	var customer_catalog: Dictionary = customer_file.data
	var customer_error := Customers.validate_catalog(customer_catalog, world.table)
	if not customer_error.is_empty():
		return _failure("invalid_package_customers: " + customer_error)
	for operation: Dictionary in sections.operations.values():
		for field: String in ["name_key", "description_key"]:
			for locale: String in ["en", "zh_CN"]:
				if not bundle.translations_by_locale[locale].has(operation[field]):
					return _failure("missing_operation_translation: " + locale + ": " + operation[field])
	var checkpoint: Dictionary = world.initial_checkpoint
	var npc_identities := {}
	for id: String in world.catalog_context.catalog.npcs:
		var npc: Dictionary = world.catalog_context.catalog.npcs[id]
		npc_identities[id] = {"id": id, "card_id": npc.get("card_id", ""), "module_id": npc.get("module_id", "")}
	var semantic := {
		"module_id": bundle.manifest.id,
		"cards": checkpoint.card_catalog_fingerprint,
		"npcs": npc_identities,
		"stories": checkpoint.story.catalog_fingerprint,
		"recipes": bundle.content.recipes,
		"bindings": sections.action_bindings,
		"events": sections.events,
		"rules": sections.scene_rules,
		"operations": sections.operations,
		"market": market,
		"services": service_catalog,
		"relationships": relationship_catalog,
		"customers": customer_catalog,
	}
	return {"ok": true, "error": "", "error_key": "", "bundle": bundle,
		"action_bindings": sections.action_bindings.duplicate(true), "event_definitions": sections.events.duplicate(true),
		"scene_rules": sections.scene_rules.duplicate(true), "market_catalog": market.duplicate(true),
		"story_topics": sections.story_topics.duplicate(true),
		"service_catalog": service_catalog.duplicate(true),
		"relationship_catalog": relationship_catalog.duplicate(true),
		"customer_catalog": customer_catalog.duplicate(true),
		"operations": sections.operations.duplicate(true), "catalog_context": world.catalog_context.duplicate(true),
		"package_fingerprint": Runner.canonical_digest(semantic), "missing_art": bundle.get("missing_art", []).duplicate(true)}


# 每次调用重新读取所有语义/文本输入并散列内容，不使用秒级mtime或文件长度作为版本证明。
static func _input_hashes(manifest_path: String) -> Dictionary:
	var document := Bundle._read_json(manifest_path)
	if not document.ok:
		return _failure("package_manifest_unavailable: " + str(document.error))
	var manifest: Dictionary = document.data
	if not manifest.get("translations") is Array:
		return _failure("invalid_package_translation_paths")
	var root := ProjectSettings.globalize_path(manifest_path).replace("\\", "/").simplify_path().get_base_dir()
	var paths: Array[String] = [manifest_path, Bundle.BASE_CONTENT, Bundle.BASE_TRANSLATIONS]
	var relatives: Array = [manifest.get("content"), manifest.get("stories")]
	relatives.append_array(manifest.translations)
	for sidecar: String in SIDECARS:
		relatives.append("source/" + sidecar + ".json")
	for relative: Variant in relatives:
		var resolved := Bundle._resolve_path(root, relative)
		if not resolved.ok:
			return _failure(str(resolved.error))
		paths.append(resolved.path)
	return _hash_paths(paths)


static func _hash_paths(paths: Array[String]) -> Dictionary:
	var hashes := {}
	for path: String in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _failure("package_input_unavailable: " + path)
		var size := file.get_length()
		if size <= 0 or size > Bundle.MAX_FILE_BYTES:
			file.close()
			return _failure("package_input_size_invalid: " + path)
		var bytes := file.get_buffer(size)
		file.close()
		if bytes.size() != size:
			return _failure("package_input_read_incomplete: " + path)
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(bytes)
		var absolute := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
		hashes[absolute] = digest.finish().hex_encode()
	return {"ok": true, "hashes": hashes}


static func _refresh_art_report(package: Dictionary) -> void:
	# 美术文件不参与玩法版本指纹；新生成或删除图片后，缺图报告仍须立即反映实况。
	var missing: Array[Dictionary] = []
	for id: String in package.bundle.content.cards:
		Bundle._check_art(id, "art_path", package.bundle.content.cards[id].get("art_path", ""), missing)
	for id: String in package.bundle.content.npcs:
		Bundle._check_art(id, "portrait_path", package.bundle.content.npcs[id].get("portrait_path", ""), missing)
	package.missing_art = missing
	package.bundle.missing_art = missing.duplicate(true)


static func _fields(data: Variant, fields: Array) -> bool:
	if not data is Dictionary or data.size() != fields.size():
		return false
	for field: String in fields:
		if not data.has(field):
			return false
	return true


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "error_key": "SAVE_UNSUPPORTED_VERSION"}


static func _version_one(value: Variant) -> bool:
	return (value is int or value is float) and value == 1
