class_name ModuleWorldFactory
extends RefCounted

const Registry = preload("res://scripts/content/module_registry.gd")
const Story = preload("res://scripts/content/module_story_session.gd")
const Runner = preload("res://scripts/content/module_recipe_runner.gd")
const Sigils = preload("res://scripts/content/module_sigil_bindings.gd")
const Effects = preload("res://scripts/content/module_event_effects.gd")
const Scheduler = preload("res://scripts/content/module_scene_scheduler.gd")
const Bridge = preload("res://scripts/content/module_action_bridge.gd")
const Market = preload("res://scripts/content/module_market_exchange.gd")
const Checkpoint = preload("res://scripts/content/module_checkpoint.gd")
const Operations = preload("res://scripts/content/chapter_operation_runner.gd")
const Services = preload("res://scripts/content/chapter_service_effects.gd")


# 只创建候选模型，不注册全局模块、不装翻译、不改变当前存档或牌桌。
static func create(bundle: Dictionary, action_bindings: Dictionary, event_definitions: Dictionary, scene_rules: Dictionary, market_catalog: Dictionary, allow_development: bool = false, operations: Variant = null, base_catalog: Dictionary = {}, service_catalog: Variant = null, customer_catalog: Variant = null) -> Dictionary:
	if bundle.get("ok") != true or not bundle.get("manifest") is Dictionary or not bundle.get("content") is Dictionary or not bundle.get("stories") is Dictionary or not bundle.get("exclusive_fact_groups") is Array:
		return _failure("invalid_bundle")
	if not allow_development and bundle.manifest.get("status") != "ready":
		return _failure("module_not_ready_for_main_game")
	if not allow_development and not bundle.get("missing_art", []).is_empty():
		return _failure("module_art_is_incomplete")
	if not market_catalog.get("offers") is Dictionary or not market_catalog.get("sources") is Dictionary:
		return _failure("invalid_market_context")
	var module_id: String = bundle.manifest.get("id", "")
	var registry := Registry.new()
	var checked := registry.configure_base(base_catalog if not base_catalog.is_empty() else ContentCatalog.base_snapshot_context().catalog)
	if not checked.ok:
		return _failure("invalid_base_context: " + str(checked.error))
	checked = registry.register_module(module_id, bundle.content)
	if not checked.ok:
		return _failure("invalid_module_context: " + str(checked.error))
	var context := {"catalog": registry.catalog(), "module_ids": [module_id]}
	var table := TableState.new()
	checked = table.configure_catalog(context.catalog, [module_id])
	if not checked.ok:
		return _failure("invalid_table_context: " + str(checked.error))
	var story := Story.new()
	checked = story.configure(bundle.stories, bundle.exclusive_fact_groups)
	if not checked.ok:
		return _failure("invalid_story_context: " + str(checked.error))
	var runner := Runner.new()
	checked = runner.configure(table, bundle.content.recipes)
	if not checked.ok:
		return _failure("invalid_recipe_context: " + str(checked.error))
	var sigils := Sigils.new()
	checked = sigils.configure(table)
	if not checked.ok:
		return _failure("invalid_sigil_context: " + str(checked.error))
	var effects := Effects.new()
	checked = effects.configure(table, story, event_definitions)
	if not checked.ok:
		return _failure("invalid_event_context: " + str(checked.error))
	var services: Services = null
	var policy := {}
	if service_catalog != null:
		if not service_catalog is Dictionary or not operations is Dictionary:
			return _failure("invalid_service_context")
		services = Services.new()
		checked = services.configure(table, story, service_catalog, operations, market_catalog)
		if not checked.ok:
			return _failure("invalid_service_context: " + str(checked.error))
		policy = Services.market_policy(service_catalog)
	var market := Market.new()
	checked = market.configure(table, market_catalog.offers, market_catalog.sources, policy, operations if operations is Dictionary else {})
	if not checked.ok:
		return _failure("invalid_market_context: " + str(checked.error))
	var bridge := Bridge.new()
	checked = bridge.configure(table, story, action_bindings, bundle.content.recipes, market_catalog, event_definitions, operations, service_catalog, customer_catalog)
	if not checked.ok:
		return _failure("invalid_action_context: " + str(checked.error))
	var scheduler := Scheduler.new()
	checked = scheduler.configure(table, story, scene_rules, bundle.content.recipes, event_definitions, operations if operations is Dictionary else {}, service_catalog, market_catalog)
	if not checked.ok:
		return _failure("invalid_scene_context: " + str(checked.error))
	var operation_runner: Operations = null
	if operations != null:
		if not operations is Dictionary:
			return _failure("invalid_operation_context")
		operation_runner = Operations.new()
		checked = operation_runner.configure(table, story, operations, Services.workbench_policy(service_catalog))
		if not checked.ok:
			return _failure("invalid_operation_context: " + str(checked.error))
	var payload := Checkpoint.capture(table, story, runner, bridge, market_catalog, event_definitions, operations, service_catalog)
	if not payload.has("schema_version"):
		return _failure("invalid_initial_checkpoint: " + str(payload.get("error", "")))
	return {"ok": true, "error": "", "table": table, "story": story, "runner": runner,
		"sigils": sigils, "effects": effects, "market": market, "bridge": bridge, "scheduler": scheduler,
		"catalog_context": context, "initial_checkpoint": payload, "operation_runner": operation_runner, "services": services, "development_only": allow_development}


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}
