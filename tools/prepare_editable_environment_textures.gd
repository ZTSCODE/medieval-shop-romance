extends SceneTree

const SOURCE_DIR := "res://assets/art/forest_rebuild/"
const OUTPUT_DIR := "res://assets/art/forest_rebuild/editable/"
const ASSETS := [
	"broadleaf",
	"rocks",
	"whiteflowers",
	"ancient-tree",
	"backpack",
	"travel-map",
	"wooden-mug",
	"lantern",
	"castle-town-night",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for asset: String in ASSETS:
		var source := load(SOURCE_DIR + asset + ".png") as Texture2D
		if source == null:
			push_error("Missing editable environment source: " + asset)
			quit(1)
			return
		var image := source.get_image()
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		if not used.has_area():
			push_error("Editable environment source is empty: " + asset)
			quit(1)
			return
		var cropped := image.get_region(used)
		var error := cropped.save_png(OUTPUT_DIR + asset + ".png")
		if error != OK:
			push_error("Cannot save editable environment texture: " + asset)
			quit(1)
			return
	print("EDITABLE_ENVIRONMENT_TEXTURES_PREPARED: %d" % ASSETS.size())
	quit(0)
