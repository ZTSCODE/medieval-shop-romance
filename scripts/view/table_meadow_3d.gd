class_name TableMeadow3D
extends Node3D

const GRASS_SHADER := preload("res://assets/shaders/table_meadow_3d.gdshader")
const TERRAIN := preload("res://scripts/view/folded_terrain.gd")


const ASSETS := [
	"res://assets/art/forest_rebuild/broadleaf.png",
	"res://assets/art/forest_rebuild/rocks.png",
	"res://assets/art/forest_rebuild/whiteflowers.png",
]
@export var patch_count := 2200
@export var distribution_seed := 480731
@export var meadow_width := 1600.0
@export var wind_strength := 10.5
@export var wind_speed := 1.05
@export var interaction_strength := 30.0
@export var disturbance_radius := 130.0
@export var interaction_retrigger_interval := 0.35
@export var build_near_patches := true
@export var build_near_landmarks := true
@export var build_distant_environment := true
const EVENT_COUNT := 32
const EVENT_LIFETIME := 1.1
var elapsed := 0.0
var patches: Array[Dictionary] = []
var batches: Array[MultiMeshInstance3D] = []
var shadow_batches: Array[MultiMeshInstance3D] = []
var _ground: Node3D
var _props: Node3D
var _texture_cache: Dictionary = {}
var _board := Rect2(-1600, -1100, 3200, 2200)
var _materials: Array[ShaderMaterial] = []
var _events := PackedVector4Array()
var _directions := PackedVector4Array()
var _segments := PackedVector4Array()
var _next_event := 0
var _last_motion_time := -1.0
var _last_pointer := Vector2(-100000, -100000)
var _camera_basis := Basis(Vector3.RIGHT, deg_to_rad(-72.0))
var _built := false

func set_camera_basis(value: Basis) -> void:
	if _camera_basis.is_equal_approx(value):
		return
	_camera_basis = value.orthonormalized()
	for material in _materials:
		_apply_camera_basis(material)

func _apply_camera_basis(material: ShaderMaterial) -> void:
	material.set_shader_parameter("facing_right", _camera_basis.x)
	material.set_shader_parameter("facing_up", _camera_basis.y)
	material.set_shader_parameter("facing_forward", _camera_basis.z)

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_events.resize(EVENT_COUNT)
	_directions.resize(EVENT_COUNT)
	_segments.resize(EVENT_COUNT)
	for index in EVENT_COUNT:
		_events[index] = Vector4(0, 0, -100, 0)

func _ready() -> void:
	_build()

func configure_world(board_rect: Rect2) -> void:
	if _board == board_rect and _built:
		return
	_board = board_rect
	if is_node_ready():
		_build()

func ensure_visible_area(area: Rect2) -> void:
	if not is_node_ready() or not area.has_area():
		return
	var needed := maxf(maxf(_board.position.x - area.position.x, area.end.x - _board.end.x), maxf(_board.position.y - area.position.y, area.end.y - _board.end.y)) + 300.0
	if needed <= meadow_width:
		return
	meadow_width = ceilf(needed / 512.0) * 512.0
	_build()

func set_pointer(point: Vector2, velocity: Vector2, impulse := false, segment_start := Vector2.INF) -> void:
	if not is_visible_in_tree() or not can_process():
		return
	var start := segment_start
	if not start.is_finite():
		start = _last_pointer if elapsed - _last_motion_time < 0.15 and _last_motion_time >= 0.0 else point
	if impulse:
		start = point
	_last_pointer = point
	if not impulse and velocity.length() < 2.0:
		return
	var direction := velocity.normalized()
	var intensity := 0.8 if impulse else motion_intensity(velocity.length())
	if _interaction_on_cooldown(start, point):
		return
	var slot := _next_event
	var event_time := elapsed
	if elapsed - _events[slot].z < EVENT_LIFETIME:
		return
	_next_event = (_next_event + 1) % EVENT_COUNT
	_events[slot] = Vector4(point.x / 100.0, point.y / 100.0, event_time, intensity)
	_segments[slot] = Vector4(start.x / 100.0, start.y / 100.0, point.x / 100.0, point.y / 100.0)
	_directions[slot] = Vector4(direction.x, direction.y, 0, 0)
	_last_motion_time = elapsed

func _interaction_on_cooldown(start: Vector2, finish: Vector2) -> bool:
	for index in EVENT_COUNT:
		var age := elapsed - _events[index].z
		if age < 0.0 or age >= interaction_retrigger_interval or _events[index].w <= 0.0:
			continue
		var a := Vector2(_segments[index].x, _segments[index].y) * 100.0
		var b := Vector2(_segments[index].z, _segments[index].w) * 100.0
		var radius := disturbance_radius * 0.75
		if start.distance_to(Geometry2D.get_closest_point_to_segment(start, a, b)) <= radius and finish.distance_to(Geometry2D.get_closest_point_to_segment(finish, a, b)) <= radius:
			return true
	return false

static func motion_intensity(speed: float) -> float:
	return smoothstep(10.0, 400.0, speed)

static func interaction_response(age: float) -> float:
	return sin(age * 11.0) * exp(-age * 4.4) if age >= 0.0 and age < EVENT_LIFETIME else 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	elapsed += delta
	for material in _materials:
		material.set_shader_parameter("elapsed", elapsed)
		material.set_shader_parameter("events", _events)
		material.set_shader_parameter("directions", _directions)
		material.set_shader_parameter("segments", _segments)
		material.set_shader_parameter("wind_strength", wind_strength / 100.0)
		material.set_shader_parameter("wind_speed", wind_speed)
		material.set_shader_parameter("interaction_strength", interaction_strength / 100.0)
		material.set_shader_parameter("disturbance_radius", disturbance_radius / 100.0)

func _build() -> void:
	_built = false
	for batch in batches:
		batch.free()
	batches.clear()
	for batch in shadow_batches:
		batch.free()
	shadow_batches.clear()
	patches.clear()
	_materials.clear()
	var textures: Array[Texture2D] = []
	var meshes: Array[ArrayMesh] = []
	for variant in ASSETS.size():
		var texture := _load_sprite_texture(ASSETS[variant])
		textures.append(texture)
		meshes.append(_make_mesh(texture, [1.85, 1.65, 1.50][variant]))
		var material := ShaderMaterial.new()
		material.shader = GRASS_SHADER
		_apply_camera_basis(material)
		material.set_shader_parameter("static_texture", texture)
		material.set_shader_parameter("region_strength", 0.0)
		material.set_shader_parameter("saturation", 1.0)
		material.set_shader_parameter("natural_multiplier", Vector3.ONE * 0.86)
		material.set_shader_parameter("variation_strength", 0.045)
		material.set_shader_parameter("bend_strength", 0.0 if variant == 1 else 1.0)
		_materials.append(material)
	var outer := _board.grow(meadow_width)
	var groups: Dictionary = {}
	var clusters := FastNoiseLite.new()
	clusters.seed = distribution_seed
	clusters.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	clusters.frequency = 0.0018
	var cell_y_start := floori(outer.position.y / 256.0)
	var cell_y_end := ceili(outer.end.y / 256.0) if build_near_patches else cell_y_start
	for cell_y in range(cell_y_start, cell_y_end):
		for cell_x in range(floori(outer.position.x / 512.0), ceili(outer.end.x / 512.0)):
			var random := RandomNumberGenerator.new()
			random.seed = hash(Vector3i(cell_x, cell_y, distribution_seed))
			for index in 6:
				# 植物团之间留出石头与地面；错位格保证根点不挤在一起。
				var slot := Vector2(index % 3, index / 3)
				var jitter := Vector2(random.randf_range(-0.28, 0.28), random.randf_range(-0.28, 0.28))
				var at := Vector2(cell_x * 512.0, cell_y * 256.0) + (slot + Vector2.ONE * 0.5 + jitter) * Vector2(512.0 / 3.0, 128.0)
				var cluster_weight := smoothstep(-0.4, 0.35, clusters.get_noise_2dv(at))
				if random.randf() > lerpf(0.24, 1.0, cluster_weight):
					continue
				var roll := random.randf()
				var variant := 0 if roll < 0.46 else (1 if roll < 0.64 else 2)
				var patch := {"position": at, "scale": random.randf_range(0.62, 1.28), "phase": random.randf(), "angle": random.randf_range(-0.244, 0.244), "variant": variant}
				if _in_rear_corridor(at / 100.0):
					if random.randf() > 0.18:
						continue
					variant = 2
					patch.variant = variant
					patch.scale *= 0.32
				var rim_clearance := Rect2(_board.position - Vector2(145.0, 70.0), _board.size + Vector2(290.0, 335.0))
				if rim_clearance.has_point(at) or not outer.has_point(at):
					continue
				patches.append(patch)
				var key := Vector3i(cell_x, cell_y, variant)
				if not groups.has(key):
					groups[key] = []
				groups[key].append(patch)
	patch_count = patches.size()
	var keys := groups.keys()
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y < b.y if a.y != b.y else a.z < b.z)
	for key: Vector3i in keys:
		var entries: Array = groups[key]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.position.y < b.position.y)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = meshes[key.z]
		multimesh.instance_count = entries.size()
		var batch_bounds := AABB()
		var first_root := true
		for index in entries.size():
			var entry: Dictionary = entries[index]
			var at: Vector2 = entry.position / 100.0
			var root_position := TERRAIN.world_position(entry.position)
			var basis := Basis(Vector3.UP, entry.angle).scaled(Vector3.ONE * entry.scale)
			multimesh.set_instance_transform(index, Transform3D(basis, root_position))
			multimesh.set_instance_custom_data(index, Color(entry.phase, fposmod(entry.phase * 7.13, 1.0), at.y, entry.scale))
			if first_root:
				batch_bounds = AABB(root_position, Vector3.ZERO)
				first_root = false
			else:
				batch_bounds = batch_bounds.expand(root_position)
		multimesh.custom_aabb = batch_bounds.grow(4.0)
		var node := MultiMeshInstance3D.new()
		node.multimesh = multimesh
		node.material_override = _materials[key.z]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		batches.append(node)
	if is_instance_valid(_ground):
		_ground.free()
	_build_props()
	_built = true

func _build_props() -> void:
	if is_instance_valid(_props):
		_props.free()
	_props = Node3D.new()
	_props.name = "ForestLandmarks"
	add_child(_props)
	var left := _board.position.x / 100.0
	var right := _board.end.x / 100.0
	var back := _board.position.y / 100.0
	var front := _board.end.y / 100.0
	if build_near_landmarks:
		_add_prop("ancient-tree", Vector2(left - 1.5, back + 3.0), 10.5)
		_add_prop("ancient-tree", Vector2(right + 2.0, back + 2.0), 11.4, true)
		_add_prop("ancient-tree", Vector2(left - 5.0, back - 1.8), 7.0, true)
		_add_prop("ancient-tree", Vector2(right + 5.0, back - 2.8), 7.8)
		_add_prop("backpack", Vector2(left - 3.2, back + 4.6), 4.5)
		_add_prop("travel-map", Vector2(left - 1.8, front - 1.0), 4.6)
		_add_prop("wooden-mug", Vector2(left - 0.8, back + 7.0), 2.75)
		_add_prop("lantern", Vector2(left - 0.1, back + 4.6), 4.6)
		_add_prop("backpack", Vector2(right + 0.8, front + 1.5), 5.9, true)
		_add_prop("wooden-mug", Vector2(right - 0.2, front + 0.8), 2.5)
		_add_prop("rocks", Vector2(left + 2.0, front + 1.4), 1.3)
		_add_prop("rocks", Vector2(right - 1.0, back - 0.8), 1.5)
		_add_prop("broadleaf", Vector2(left - 2.2, front + 3.0), 6.375, false, 0.65)
		_add_prop("broadleaf", Vector2(right + 1.5, front + 3.0), 5.5, true, 0.65)
		_add_prop("whiteflowers", Vector2(left - 1.2, front + 0.6), 2.1)
		_add_prop("whiteflowers", Vector2(right + 2.1, back + 5.0), 1.8)
		_add_prop("whiteflowers", Vector2(left - 1.9, back + 1.5), 1.5)
		_add_prop("whiteflowers", Vector2(right - 2.5, back - 0.6), 1.5)
	if build_distant_environment:
		_build_distant_props(left, right, back)

func _build_distant_props(left: float, right: float, back: float) -> void:
	for layer in 4:
		var depth := [4.0, 9.0, 16.0, 26.0][layer] as float
		var random := RandomNumberGenerator.new()
		random.seed = distribution_seed + layer * 911
		var count := 5 + layer * 2
		for index in count:
			var fraction := (float(index) + 0.5) / float(count)
			var x := lerpf(left - 8.0, right + 8.0, fraction) + random.randf_range(-1.2, 1.2)
			var at := Vector2(x, back - depth - random.randf_range(0.0, 2.0))
			if _in_rear_corridor(at, 2.0):
				continue
			var height := random.randf_range(2.6, 4.2) * (1.0 - layer * 0.13)
			_add_prop("ancient-tree", at, height, index % 2 == 1, 0.80 - layer * 0.04)
	_build_far_slope(back)

func _in_rear_corridor(at_meters: Vector2, padding := 0.0) -> bool:
	var depth := _board.position.y / 100.0 - at_meters.y
	if depth < 0.70:
		return false
	var center := minf(depth * 0.18, 13.0)
	var half_width := 5.0 + depth * 0.045 + padding
	return absf(at_meters.x - center) < half_width

func _build_far_slope(back: float) -> void:
	var trees: Array[Dictionary] = []
	var undergrowth: Array[Dictionary] = []
	var flowers: Array[Dictionary] = []
	var random := RandomNumberGenerator.new()
	random.seed = distribution_seed + 7431
	for layer in 5:
		var depth := float([38.0, 54.0, 73.0, 95.0, 120.0][layer])
		var half_width := 18.0 + depth * 0.30
		var groups := 7 + layer * 2
		for group in groups:
			var x := lerpf(-half_width, half_width, (group + 0.5) / float(groups)) + random.randf_range(-2.5, 2.5)
			var center := Vector2(x, back - depth - random.randf_range(-4.0, 4.0))
			# 不连续的树丛与树间空隙形成纵深，而非另一张均匀地毯。
			for member in random.randi_range(2, 4):
				var at := (center + Vector2(random.randf_range(-2.5, 2.5), random.randf_range(-3.0, 3.0))) * 100.0
				if _in_rear_corridor(at / 100.0, 2.0):
					continue
				trees.append({"position": at, "scale": random.randf_range(0.65, 1.10) * (1.0 - layer * 0.085), "phase": random.randf()})
			for member in random.randi_range(3, 5):
				var at := (center + Vector2(random.randf_range(-3.7, 3.7), random.randf_range(-2.5, 2.5))) * 100.0
				var patch := {"position": at, "scale": random.randf_range(0.70, 1.50), "phase": random.randf()}
				if _in_rear_corridor(at / 100.0):
					if random.randf() > 0.20:
						continue
					patch.scale *= 0.35
				if random.randf() < 0.26:
					flowers.append(patch)
				else:
					undergrowth.append(patch)
	_add_distant_batch("ancient-tree", trees, 4.0, 0.12, 0.76)
	_add_distant_batch("broadleaf", undergrowth, 2.3, 1.0, 0.77)
	_add_distant_batch("whiteflowers", flowers, 1.7, 1.0, 0.83)
	_build_horizon_trees(back)
	_add_prop("castle-town-night", Vector2(11.7, back - 65.0), 5.1, false, 0.85)
	_add_prop("rocks", Vector2(6.8, back - 64.3), 0.85, false, 0.68)
	_add_prop("rocks", Vector2(16.6, back - 64.3), 0.75, true, 0.68)
	_add_prop("broadleaf", Vector2(6.0, back - 64.0), 1.35, false, 0.62)
	_add_prop("broadleaf", Vector2(17.4, back - 64.0), 1.20, true, 0.62)

func _build_horizon_trees(_back: float) -> void:
	var crowns: Array[Dictionary] = []
	var trees: Array[Dictionary] = []
	var random := RandomNumberGenerator.new()
	random.seed = distribution_seed + 26195
	for layer in 5:
		var x := -178.0
		while x < 178.0:
			var end := TERRAIN.terminal_z(x*100.0)/100.0
			var z := end + 8.0 + float(layer)*26.0 + random.randf_range(-7.0,7.0)
			var at := Vector2(x,z)*100.0
			trees.append({"position":at,"scale":random.randf_range(0.65,1.45),"phase":random.randf()})
			crowns.append({"position":at+Vector2(130,250),"scale":random.randf_range(0.8,1.4),"phase":random.randf()})
			x += random.randf_range(3.5,6.0)
	_add_distant_batch("broadleaf", crowns, 4.0, 0.025, 0.67, Vector3(0.65,0.82,1.0))
	_add_distant_batch("ancient-tree", trees, 5.5, 0.015, 0.62, Vector3(0.65,0.82,1.0))

func _add_distant_batch(asset: String, entries: Array[Dictionary], width: float, bend: float, brightness: float, tint := Vector3.ONE) -> void:
	if entries.is_empty():
		return
	var texture := _load_sprite_texture("res://assets/art/forest_rebuild/" + asset + ".png")
	var material := ShaderMaterial.new()
	material.shader = GRASS_SHADER
	_apply_camera_basis(material)
	material.set_shader_parameter("static_texture", texture)
	material.set_shader_parameter("region_strength", 0.0)
	material.set_shader_parameter("saturation", 1.0)
	material.set_shader_parameter("natural_multiplier", tint * brightness)
	material.set_shader_parameter("variation_strength", 0.03)
	material.set_shader_parameter("bend_strength", bend)
	_materials.append(material)
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = _make_mesh(texture, width)
	mesh.instance_count = entries.size()
	var bounds := AABB()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var root_position := TERRAIN.world_position(entry.position)
		var basis := Basis.IDENTITY.scaled(Vector3.ONE * entry.scale)
		mesh.set_instance_transform(index, Transform3D(basis, root_position))
		mesh.set_instance_custom_data(index, Color(entry.phase, fposmod(entry.phase * 7.13, 1.0), entry.position.y / 100.0, entry.scale))
		bounds = AABB(root_position, Vector3.ZERO) if index == 0 else bounds.expand(root_position)
	mesh.custom_aabb = bounds.grow(width * 2.5)
	var node := MultiMeshInstance3D.new()
	node.name = "Far" + asset.to_pascal_case()
	node.multimesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props.add_child(node)

func _add_prop(asset: String, at: Vector2, height: float, flipped := false, brightness := 1.0) -> void:
	var texture := _load_sprite_texture("res://assets/art/forest_rebuild/" + asset + ".png")
	if texture == null:
		return
	var picture := Sprite3D.new()
	picture.name = asset.to_pascal_case()
	picture.texture = texture
	picture.pixel_size = height / float(texture.get_height())
	picture.offset = Vector2(0.0, texture.get_height() * 0.5)
	picture.position = TERRAIN.world_position(at * 100.0) + Vector3.UP * 0.025
	picture.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	picture.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	picture.alpha_scissor_threshold = 0.18
	picture.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	picture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	picture.shaded = true
	picture.flip_h = flipped
	picture.modulate = Color(brightness, brightness, brightness, 1.0)
	_props.add_child(picture)

func _load_sprite_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var source := load(path) as Texture2D
	if source == null:
		return null
	var original := source.get_image()
	var image := original.get_region(original.get_used_rect())
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[path] = texture
	return texture

func _make_mesh(texture: Texture2D, width: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var height := width * float(texture.get_height()) / float(texture.get_width())
	for row in 9:
		for column in 5:
			var at := Vector2(column / 4.0, row / 8.0)
			vertices.append(Vector3((at.x - 0.5) * width, (1.0 - at.y) * height, 0))
			uv.append(at)
			normals.append(Vector3.BACK)
	for row in 8:
		for column in 4:
			var start := row * 5 + column
			indices.append_array(PackedInt32Array([start, start + 1, start + 5, start + 1, start + 6, start + 5]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


