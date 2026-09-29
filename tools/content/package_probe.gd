extends SceneTree


func _initialize() -> void:
	var package := preload("res://scripts/content/chapter_package.gd").load_package()
	print(JSON.stringify({"ok": package.ok, "error": package.get("error", ""), "operations": package.get("operations", {}).size()}))
	quit(0 if package.ok else 1)
