extends SceneTree

const OUTPUT_PATH := "res://scenes/world/table_environment_editable.tscn"
const TABLE_TEXTURE := "res://assets/art/forest_rebuild/earth-tile.png"
const MEADOW_TEXTURE := "res://assets/art/forest_rebuild/forest-floor-tile.png"
const SURFACE_SHADER := preload("res://assets/shaders/painterly_tiling.gdshader")
const GRASS_PATCH := preload("res://addons/grass_painter/grass_patch_3d.gd")
const PAINT_SURFACE := preload("res://scripts/view/table_grass_paint_surface_3d.gd")
const PAINTED_ROOT := preload("res://scripts/view/table_painted_vegetation_3d.gd")
const PREVIEW_RIG := preload("res://scripts/view/table_editor_preview_rig_3d.gd")
const MANUAL_PLANT := preload("res://scripts/view/table_manual_plant_3d.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_root := Node3D.new()
	scene_root.name = "TableScene"
	scene_root.rotation_degrees.x = 90.0
	_build_board(scene_root)
	_build_lighting(scene_root)
	_build_background(scene_root)
	_build_editor_preview(scene_root)
	_build_editor_environment(scene_root)
	var packed := PackedScene.new()
	var pack_error := packed.pack(scene_root)
	if pack_error != OK:
		push_error("Cannot pack editable table scene: %d" % pack_error)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var save_error := ResourceSaver.save(packed, OUTPUT_PATH)
	if save_error != OK:
		push_error("Cannot save editable table scene: %d" % save_error)
		quit(1)
		return
	print("EDITABLE_TABLE_SCENE_BUILT: " + OUTPUT_PATH)
	quit(0)


func _build_board(scene_root: Node3D) -> void:
	var extent := TableState.WORLD_BOUNDS.size / 100.0
	var slab := MeshInstance3D.new()
	slab.name = "BoardThickness"
	var box := BoxMesh.new()
	box.size = Vector3(extent.x, 0.16, extent.y)
	slab.mesh = box
	# Leave enough depth clearance for the imported painted surface.
	slab.position.y = -0.15
	slab.visible = false
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color("30251e")
	edge.roughness = 0.95
	slab.material_override = edge
	_add_owned(scene_root, slab, scene_root)

	var surface := MeshInstance3D.new()
	surface.name = "BoardSurface"
	var board_material := ShaderMaterial.new()
	board_material.shader = SURFACE_SHADER
	board_material.set_shader_parameter("grain", load(TABLE_TEXTURE))
	board_material.set_shader_parameter("tile_size_meters", 6.0)
	board_material.set_shader_parameter("surface_tint", Color.WHITE)
	board_material.set_shader_parameter("unfolded_coordinates", true)
	var ground_material := ShaderMaterial.new()
	ground_material.shader = SURFACE_SHADER
	ground_material.set_shader_parameter("grain", load(MEADOW_TEXTURE))
	ground_material.set_shader_parameter("tile_size_meters", 4.0)
	ground_material.set_shader_parameter("unfolded_coordinates", true)
	surface.mesh = load("res://assets/models/terrain/board-terrain-user-v1.res") as ArrayMesh
	if surface.mesh == null:
		surface.mesh = FoldedTerrain.make_mesh(board_material, ground_material)
	else:
		surface.set_surface_override_material(0, ground_material)
		if surface.mesh.get_surface_count() > 1:
			surface.set_surface_override_material(1, board_material)
	_add_owned(scene_root, surface, scene_root)

	var wood := ShaderMaterial.new()
	wood.shader = SURFACE_SHADER
	wood.set_shader_parameter("grain", load("res://assets/art/forest_rebuild/wood-rim-tile.png"))
	wood.set_shader_parameter("tile_size_meters", 2.0)
	for side in 4:
		var beam := MeshInstance3D.new()
		beam.name = "WoodRim" + str(side)
		var shape := BoxMesh.new()
		shape.size = Vector3(extent.x + 1.4, 0.28, 0.72) if side < 2 else Vector3(0.72, 0.28, extent.y)
		beam.mesh = shape
		beam.material_override = wood
		beam.position = Vector3(0, -0.055, (-1.0 if side == 0 else 1.0) * (extent.y * 0.5 + 0.30)) if side < 2 else Vector3((-1.0 if side == 2 else 1.0) * (extent.x * 0.5 + 0.30), -0.055, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add_owned(scene_root, beam, scene_root)


func _build_lighting(scene_root: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.name = "TableLightEnvironment"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_CLEAR_COLOR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("a6b8d4")
	settings.ambient_light_energy = 0.65
	environment.environment = settings
	_add_owned(scene_root, environment, scene_root)
	var warm := DirectionalLight3D.new()
	warm.name = "WarmKey"
	warm.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	warm.light_color = Color("ffe1b4")
	warm.light_energy = 0.7
	warm.shadow_enabled = false
	_add_owned(scene_root, warm, scene_root)
	var cool := DirectionalLight3D.new()
	cool.name = "CoolFill"
	cool.rotation_degrees = Vector3(-35.0, 145.0, 0.0)
	cool.light_color = Color("a8c5ef")
	cool.light_energy = 0.25
	_add_owned(scene_root, cool, scene_root)


func _build_background(scene_root: Node3D) -> void:
	var far_background := MeshInstance3D.new()
	far_background.name = "DistantSkyWorldPlane"
	var plane := QuadMesh.new()
	plane.size = Vector2(500, 500.0 / 3.0)
	far_background.mesh = plane
	far_background.position = Vector3(0, -290, -173)
	far_background.rotation.x = deg_to_rad(-72.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = load("res://assets/art/forest_rebuild/distant-river.png")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	far_background.material_override = material
	far_background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_owned(scene_root, far_background, scene_root)


func _build_editor_preview(scene_root: Node3D) -> void:
	var rig: TableEditorPreviewRig3D = PREVIEW_RIG.new()
	rig.name = "EditorGamePreviewRig"
	_add_owned(scene_root, rig, scene_root)
	var camera := Camera3D.new()
	camera.name = "EditorGamePreviewCamera"
	camera.current = false
	camera.fov = TableCameraGeometry.FOV_DEGREES
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.05
	camera.far = 1400.0
	camera.add_to_group("table_editor_preview_camera", true)
	_add_owned(rig, camera, scene_root)
	var pointer_light := OmniLight3D.new()
	pointer_light.name = "PreviewPointerWarmLight"
	pointer_light.light_color = Color("ffd7a0")
	pointer_light.light_energy = 1.5
	pointer_light.omni_range = 4.5
	pointer_light.omni_attenuation = 1.4
	pointer_light.shadow_enabled = false
	pointer_light.visible = false
	_add_owned(rig, pointer_light, scene_root)
	rig.refresh_preview()


func _build_editor_environment(scene_root: Node3D) -> void:
	var environment_root := Node3D.new()
	environment_root.name = "EnvironmentRoot"
	environment_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	_add_owned(scene_root, environment_root, scene_root)
	var paint_surface := PAINT_SURFACE.new()
	paint_surface.name = "GrassPaintSurface"
	_add_owned(environment_root, paint_surface, scene_root)
	var painted := PAINTED_ROOT.new()
	painted.name = "EditableVegetation"
	_add_owned(environment_root, painted, scene_root)
	var distribution := _initial_distribution()
	_add_grass_layer(painted, scene_root, "BroadleafField", "res://assets/art/forest_rebuild/editable/broadleaf.png", 1.85, distribution[0], true)
	_add_grass_layer(painted, scene_root, "RocksField", "res://assets/art/forest_rebuild/editable/rocks.png", 1.65, distribution[1], false)
	_add_grass_layer(painted, scene_root, "WhiteFlowersField", "res://assets/art/forest_rebuild/editable/whiteflowers.png", 1.50, distribution[2], true)
	_add_far_vegetation(painted, scene_root)
	var manual_plants := Node3D.new()
	manual_plants.name = "EditableManualPlants"
	_add_owned(painted, manual_plants, scene_root)
	var landmarks := Node3D.new()
	landmarks.name = "EditableLandmarks"
	_add_owned(environment_root, landmarks, scene_root)
	_add_initial_landmarks(landmarks, manual_plants, scene_root)
	var distant_landmarks := Node3D.new()
	distant_landmarks.name = "EditableDistantLandmarks"
	_add_owned(environment_root, distant_landmarks, scene_root)
	_add_distant_landmarks(distant_landmarks, scene_root)


func _initial_distribution() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for _index in 3:
		result.append({"positions": PackedVector3Array(), "rotations": PackedFloat32Array(), "scales": PackedFloat32Array(), "phases": PackedFloat32Array(), "tints": PackedFloat32Array()})
	var board := TableState.WORLD_BOUNDS
	var outer := board.grow(1600.0)
	var clusters := FastNoiseLite.new()
	clusters.seed = 480731
	clusters.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	clusters.frequency = 0.0018
	for cell_y in range(floori(outer.position.y / 256.0), ceili(outer.end.y / 256.0)):
		for cell_x in range(floori(outer.position.x / 512.0), ceili(outer.end.x / 512.0)):
			var random := RandomNumberGenerator.new()
			random.seed = hash(Vector3i(cell_x, cell_y, 480731))
			for index in 6:
				var slot := Vector2(index % 3, index / 3)
				var jitter := Vector2(random.randf_range(-0.28, 0.28), random.randf_range(-0.28, 0.28))
				var logical := Vector2(cell_x * 512.0, cell_y * 256.0) + (slot + Vector2.ONE * 0.5 + jitter) * Vector2(512.0 / 3.0, 128.0)
				var cluster_weight := smoothstep(-0.4, 0.35, clusters.get_noise_2dv(logical))
				if random.randf() > lerpf(0.24, 1.0, cluster_weight):
					continue
				var roll := random.randf()
				var variant := 0 if roll < 0.46 else (1 if roll < 0.64 else 2)
				var scale := random.randf_range(0.62, 1.28)
				var phase := random.randf()
				var angle := random.randf_range(-0.244, 0.244)
				if _in_rear_corridor(logical / 100.0, board):
					if random.randf() > 0.18:
						continue
					variant = 2
					scale *= 0.32
				var rim_clearance := Rect2(board.position - Vector2(145.0, 70.0), board.size + Vector2(290.0, 335.0))
				if rim_clearance.has_point(logical) or not outer.has_point(logical):
					continue
				var layer: Dictionary = result[variant]
				layer.positions.append(FoldedTerrain.world_position(logical))
				layer.rotations.append(angle)
				layer.scales.append(scale)
				layer.phases.append(phase)
				layer.tints.append(fposmod(phase * 7.13, 1.0))
	return result


func _in_rear_corridor(at_meters: Vector2, board: Rect2, padding := 0.0) -> bool:
	var depth := board.position.y / 100.0 - at_meters.y
	if depth < 0.70:
		return false
	var center := minf(depth * 0.18, 13.0)
	var half_width := 5.0 + depth * 0.045 + padding
	return absf(at_meters.x - center) < half_width


func _add_grass_layer(parent: Node3D, scene_root: Node3D, node_name: String, texture_path: String, width: float, distribution: Dictionary, bends: bool, brightness := 0.86, tint := Color.WHITE, layer_wind_strength := 0.105) -> void:
	var patch: GrassPatch3D = GRASS_PATCH.new()
	patch.name = node_name
	patch.static_texture = load(texture_path)
	var texture_size := patch.static_texture.get_size()
	patch.quad_size = Vector2(width, width * texture_size.y / texture_size.x)
	patch.auto_fill_on_empty = false
	patch.suppress_auto_fill = true
	patch.wind_enabled = bends
	patch.player_interaction_enabled = bends
	patch.color_saturation = 1.0
	patch.natural_color_multiplier = Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, 1.0)
	patch.color_variation_strength = 0.045
	patch.region_color_strength = 0.0
	patch.outline_strength = 0.0
	patch.wind_strength = layer_wind_strength if bends else 0.0
	patch.player_bend_strength = 0.30 if bends else 0.0
	patch.disturbance_radius = 1.30
	patch.minimum_scale = 0.62
	patch.maximum_scale = 1.28
	patch.minimum_spacing = 0.09
	patch.grass_positions = distribution.positions
	patch.grass_rotations = distribution.rotations
	patch.grass_scales = distribution.scales
	patch.grass_phases = distribution.phases
	patch.grass_tints = distribution.tints
	_add_owned(parent, patch, scene_root)


func _add_far_vegetation(parent: Node3D, scene_root: Node3D) -> void:
	var layers := _far_vegetation_distribution()
	_add_grass_layer(parent, scene_root, "FarAncientTreesField", "res://assets/art/forest_rebuild/editable/ancient-tree.png", 4.0, layers.far_trees, true, 0.76, Color.WHITE, 0.012)
	_add_grass_layer(parent, scene_root, "FarBroadleafField", "res://assets/art/forest_rebuild/editable/broadleaf.png", 2.3, layers.far_broadleaf, true, 0.77)
	_add_grass_layer(parent, scene_root, "FarWhiteFlowersField", "res://assets/art/forest_rebuild/editable/whiteflowers.png", 1.7, layers.far_flowers, true, 0.83)
	_add_grass_layer(parent, scene_root, "HorizonCrownsField", "res://assets/art/forest_rebuild/editable/broadleaf.png", 4.0, layers.horizon_crowns, true, 0.67, Color(0.65,0.82,1.0), 0.004)
	_add_grass_layer(parent, scene_root, "HorizonTreesField", "res://assets/art/forest_rebuild/editable/ancient-tree.png", 5.5, layers.horizon_trees, true, 0.62, Color(0.65,0.82,1.0), 0.003)


func _far_vegetation_distribution() -> Dictionary:
	var board := TableState.WORLD_BOUNDS
	var back := board.position.y / 100.0
	var far_trees := _empty_distribution()
	var far_broadleaf := _empty_distribution()
	var far_flowers := _empty_distribution()
	var horizon_crowns := _empty_distribution()
	var horizon_trees := _empty_distribution()
	var random := RandomNumberGenerator.new()
	random.seed = 480731 + 7431
	for layer in 5:
		var depth := float([38.0, 54.0, 73.0, 95.0, 120.0][layer])
		var half_width := 18.0 + depth * 0.30
		var groups := 7 + layer * 2
		for group in groups:
			var x := lerpf(-half_width, half_width, (group + 0.5) / float(groups)) + random.randf_range(-2.5, 2.5)
			var center := Vector2(x, back - depth - random.randf_range(-4.0, 4.0))
			for _member in random.randi_range(2, 4):
				var logical := (center + Vector2(random.randf_range(-2.5, 2.5), random.randf_range(-3.0, 3.0))) * 100.0
				if _in_rear_corridor(logical / 100.0, board, 2.0):
					continue
				_append_distribution(far_trees, logical, random.randf_range(0.65, 1.10) * (1.0 - layer * 0.085), random.randf())
			for _member in random.randi_range(3, 5):
				var logical := (center + Vector2(random.randf_range(-3.7, 3.7), random.randf_range(-2.5, 2.5))) * 100.0
				var scale := random.randf_range(0.70, 1.50)
				var phase := random.randf()
				if _in_rear_corridor(logical / 100.0, board):
					if random.randf() > 0.20:
						continue
					scale *= 0.35
				if random.randf() < 0.26:
					_append_distribution(far_flowers, logical, scale, phase)
				else:
					_append_distribution(far_broadleaf, logical, scale, phase)
	random.seed = 480731 + 26195
	for layer in 5:
		var x := -178.0
		while x < 178.0:
			var end := FoldedTerrain.terminal_z(x * 100.0) / 100.0
			var z := end + 8.0 + float(layer) * 26.0 + random.randf_range(-7.0, 7.0)
			var logical := Vector2(x, z) * 100.0
			_append_distribution(horizon_trees, logical, random.randf_range(0.65, 1.45), random.randf())
			_append_distribution(horizon_crowns, logical + Vector2(130, 250), random.randf_range(0.8, 1.4), random.randf())
			x += random.randf_range(3.5, 6.0)
	return {
		"far_trees": far_trees,
		"far_broadleaf": far_broadleaf,
		"far_flowers": far_flowers,
		"horizon_crowns": horizon_crowns,
		"horizon_trees": horizon_trees,
	}


func _empty_distribution() -> Dictionary:
	return {"positions": PackedVector3Array(), "rotations": PackedFloat32Array(), "scales": PackedFloat32Array(), "phases": PackedFloat32Array(), "tints": PackedFloat32Array()}


func _append_distribution(layer: Dictionary, logical: Vector2, scale: float, phase: float, angle := 0.0) -> void:
	layer.positions.append(FoldedTerrain.world_position(logical))
	layer.rotations.append(angle)
	layer.scales.append(scale)
	layer.phases.append(phase)
	layer.tints.append(fposmod(phase * 7.13, 1.0))


func _add_initial_landmarks(parent: Node3D, manual_parent: Node3D, scene_root: Node3D) -> void:
	var board := TableState.WORLD_BOUNDS
	var left := board.position.x / 100.0
	var right := board.end.x / 100.0
	var back := board.position.y / 100.0
	var front := board.end.y / 100.0
	var entries := [
		["ancient-tree", Vector2(left - 1.5, back + 3.0), 10.5, false, 1.0],
		["ancient-tree", Vector2(right + 2.0, back + 2.0), 11.4, true, 1.0],
		["ancient-tree", Vector2(left - 5.0, back - 1.8), 7.0, true, 1.0],
		["ancient-tree", Vector2(right + 5.0, back - 2.8), 7.8, false, 1.0],
		["backpack", Vector2(left - 3.2, back + 4.6), 4.5, false, 1.0],
		["travel-map", Vector2(left - 1.8, front - 1.0), 4.6, false, 1.0],
		["wooden-mug", Vector2(left - 0.8, back + 7.0), 2.75, false, 1.0],
		["lantern", Vector2(left - 0.1, back + 4.6), 4.6, false, 1.0],
		["backpack", Vector2(right + 0.8, front + 1.5), 5.9, true, 1.0],
		["wooden-mug", Vector2(right - 0.2, front + 0.8), 2.5, false, 1.0],
		["rocks", Vector2(left + 2.0, front + 1.4), 1.3, false, 1.0],
		["rocks", Vector2(right - 1.0, back - 0.8), 1.5, false, 1.0],
		["broadleaf", Vector2(left - 2.2, front + 3.0), 6.375, false, 0.65],
		["broadleaf", Vector2(right + 1.5, front + 3.0), 5.5, true, 0.65],
		["whiteflowers", Vector2(left - 1.2, front + 0.6), 2.1, false, 1.0],
		["whiteflowers", Vector2(right + 2.1, back + 5.0), 1.8, false, 1.0],
		["whiteflowers", Vector2(left - 1.9, back + 1.5), 1.5, false, 1.0],
		["whiteflowers", Vector2(right - 2.5, back - 0.6), 1.5, false, 1.0],
	]
	for index in entries.size():
		var entry: Array = entries[index]
		var node_name := "%s_%02d" % [String(entry[0]).to_pascal_case(), index + 1]
		if String(entry[0]) == "broadleaf":
			_add_manual_plant(manual_parent,scene_root,node_name,entry[1],entry[2],entry[3],entry[4],index+1)
		else:
			_add_landmark(parent,scene_root,node_name,String(entry[0]),entry[1],entry[2],entry[3],entry[4])


func _add_manual_plant(parent: Node3D,scene_root: Node3D,node_name: String,logical: Vector2,height: float,flip: bool,brightness: float,seed: int) -> void:
	var plant: TableManualPlant3D = MANUAL_PLANT.new()
	plant.name = node_name
	plant.plant_texture = load("res://assets/art/forest_rebuild/editable/broadleaf.png")
	plant.plant_height_meters = height
	plant.flip_horizontal = flip
	plant.color_multiplier = Color(brightness,brightness,brightness,1.0)
	plant.variation_seed = seed
	plant.position = FoldedTerrain.world_position(logical*100.0)+Vector3(0,0.025,0)
	_add_owned(parent,plant,scene_root)


func _add_distant_landmarks(parent: Node3D, scene_root: Node3D) -> void:
	var board := TableState.WORLD_BOUNDS
	var left := board.position.x / 100.0
	var right := board.end.x / 100.0
	var back := board.position.y / 100.0
	var landmark_index := 1
	for layer in 4:
		var depth := [4.0, 9.0, 16.0, 26.0][layer] as float
		var random := RandomNumberGenerator.new()
		random.seed = 480731 + layer * 911
		var count := 5 + layer * 2
		for index in count:
			var fraction := (float(index) + 0.5) / float(count)
			var x := lerpf(left - 8.0, right + 8.0, fraction) + random.randf_range(-1.2, 1.2)
			var at := Vector2(x, back - depth - random.randf_range(0.0, 2.0))
			if _in_rear_corridor(at, board, 2.0):
				continue
			var height := random.randf_range(2.6, 4.2) * (1.0 - layer * 0.13)
			_add_landmark(parent, scene_root, "DistantTree_%02d" % landmark_index, "ancient-tree", at, height, index % 2 == 1, 0.80 - layer * 0.04)
			landmark_index += 1
	_add_landmark(parent, scene_root, "CastleTown", "castle-town-night", Vector2(11.7, back - 65.0), 5.1, false, 0.85)
	_add_landmark(parent, scene_root, "TownRockLeft", "rocks", Vector2(6.8, back - 64.3), 0.85, false, 0.68)
	_add_landmark(parent, scene_root, "TownRockRight", "rocks", Vector2(16.6, back - 64.3), 0.75, true, 0.68)
	_add_landmark(parent, scene_root, "TownBroadleafLeft", "broadleaf", Vector2(6.0, back - 64.0), 1.35, false, 0.62)
	_add_landmark(parent, scene_root, "TownBroadleafRight", "broadleaf", Vector2(17.4, back - 64.0), 1.20, true, 0.62)


func _add_landmark(parent: Node3D, scene_root: Node3D, node_name: String, asset: String, at_meters: Vector2, height: float, flipped: bool, brightness: float) -> void:
	var texture := load("res://assets/art/forest_rebuild/editable/" + asset + ".png") as Texture2D
	if texture == null:
		return
	var picture := Sprite3D.new()
	picture.name = node_name
	picture.texture = texture
	picture.pixel_size = height / float(texture.get_height())
	picture.offset = Vector2(0.0, texture.get_height() * 0.5)
	picture.position = FoldedTerrain.world_position(at_meters * 100.0) + Vector3.UP * 0.025
	picture.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	picture.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	picture.alpha_scissor_threshold = 0.18
	picture.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	picture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	picture.shaded = true
	picture.flip_h = flipped
	picture.modulate = Color(brightness, brightness, brightness, 1.0)
	_add_owned(parent, picture, scene_root)


func _add_owned(parent: Node, child: Node, scene_root: Node) -> void:
	parent.add_child(child)
	child.owner = scene_root
