extends SceneTree

class ParentMaterialProbe extends Node2D:
	func _ready() -> void:
		RosePaperStyle.watch_canvas(self)
	func _draw() -> void:
		RosePaperStyle.draw_paper(get_canvas_item(), Rect2(0, 0, 32, 40), &"card")
		draw_rect(Rect2(44, 4, 8, 8), Color.BLUE)

var checks := 0
var failures := 0
var _fixture_textures: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RosePaperStyle.reload_assets()
	var fixture := _fixture()
	_install_fixture_textures(fixture)
	_test_fixed_geometry(fixture)
	_test_registration(fixture)
	_test_density_and_rotation(fixture)
	_test_compositor(fixture)
	await _test_gpu_composite(fixture)
	RosePaperStyle.reload_assets()
	if not "--fixtures-only" in OS.get_cmdline_user_args():
		_test_real_assets()
	_test_card_geometry()
	RosePaperStyle.reload_assets()
	print("ROSE_PAPER_GEOMETRY_SUITE: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _fixture() -> Dictionary:
	var assets := {
		"shape": {"path": "fixture_shape.png", "source_size": [128, 96], "region": [16, 16, 96, 64], "source_margins": [16, 16, 16, 16]},
		"shadow": {"path": "fixture_shadow.png", "source_size": [128, 96], "region": [12, 12, 104, 72], "registered_region": [16, 16, 96, 64], "source_margins": [20, 20, 20, 20], "alpha_gain": 2.0},
		"ink": {"path": "fixture_ink.png", "source_size": [128, 96], "region": [16, 16, 96, 64], "registered_region": [16, 16, 96, 64], "source_margins": [16, 16, 16, 16]},
		"brush_tile": {"path": "fixture_brush.png", "source_size": [64, 64], "region": [0, 0, 64, 64], "logical_width": 640, "mirror_repeat": false},
	}
	var layers := [
		{"id": "back_a", "shape": "shape", "shadow": "shadow", "texture": "brush_tile", "frame_scale": 0.25, "insets": [0, 8, 0, 8], "rotation_deg": -0.4, "tint": "c29c98"},
		{"id": "back_b", "shape": "shape", "shadow": "shadow", "texture": "brush_tile", "frame_scale": 0.25, "insets": [8, 0, 8, 0], "rotation_deg": 0.6, "tint": "d6aaa4"},
		{"id": "front", "shape": "shape", "shadow": "shadow", "ink": "ink", "texture": "brush_tile", "frame_scale": 0.25, "insets": [2, 3, 2, 3], "tint": "f1e5d4", "texture_strength": 0.2},
	]
	return {"assets": assets, "roles": {"card": {"layers": layers}, "dialogue": {"layers": layers.duplicate(true)}}}


func _install_fixture_textures(fixture: Dictionary) -> void:
	for name: String in fixture.assets:
		var entry: Dictionary = fixture.assets[name]
		var dimensions: Array = entry.source_size
		var pixels := Image.create(dimensions[0], dimensions[1], false, Image.FORMAT_RGBA8)
		pixels.fill(Color.TRANSPARENT)
		if name == "brush_tile":
			for y in pixels.get_height():
				for x in pixels.get_width():
					var shade := 0.35 + float(x) / pixels.get_width() * 0.3
					pixels.set_pixel(x, y, Color(shade, shade, shade, 1.0))
		else:
			var region: Array = entry.region
			pixels.fill_rect(Rect2i(region[0], region[1], region[2], region[3]), Color(0.0, 0.0, 0.0, 0.4) if name == "shadow" else Color.WHITE)
			if name == "ink":
				pixels.fill_rect(Rect2i(32, 32, 64, 32), Color.TRANSPARENT)
		var texture := ImageTexture.create_from_image(pixels)
		var path := RosePaperStyle.ART_DIR + String(entry.path)
		_fixture_textures[path] = texture
		RosePaperStyle._textures[path] = texture


func _test_fixed_geometry(fixture: Dictionary) -> void:
	var small := RosePaperStyle.plan_for(Rect2(10, 20, 112, 184), &"card", fixture)
	var large := RosePaperStyle.plan_for(Rect2(10, 20, 964, 320), &"card", fixture)
	_check("three independently shaped paper layers remain separate", small.layers.size() == 3 and small.components.size() == 7)
	_check("every paper gets a separate shadow before it", small.components[0].mode == &"shadow" and small.components[1].mode == &"paper" and small.components[4].mode == &"shadow" and small.components[5].mode == &"paper")
	_check("ink is a separate final mask", small.components[6].mode == &"ink")
	_check("front corner scale stays fixed across resizing", is_equal_approx(small.frame_scale, large.frame_scale))
	_check("front insets stay fixed across resizing", small.face_rect.position - small.outer_rect.position == large.face_rect.position - large.outer_rect.position)
	_check("texture density stays fixed across resizing", small.tile_scale == large.tile_scale and is_equal_approx(small.tile_scale, 10.0))
	_check("paper texture is not split into mirrored little tiles", not small.patches.any(func(patch: Dictionary) -> bool: return patch.kind == &"tile"))
	for plan: Dictionary in [small, large]:
		var proportional := true
		var valid_uv := true
		var centers_inside := true
		for component: Dictionary in plan.components:
			for patch: Dictionary in component.patches:
				if patch.kind == &"center":
					centers_inside = centers_inside and component.rect.encloses(patch.destination) and patch.destination.position.x > component.rect.position.x and patch.destination.position.y > component.rect.position.y
					continue
				proportional = proportional and _uniform(patch)
				valid_uv = valid_uv and Rect2(Vector2.ZERO, component.mask_size).grow(0.001).encloses(patch.source)
		_check("all mask corners and edge pieces retain equal x and y scale", proportional)
		_check("mask crops stay within their original alpha images", valid_uv)
		_check("opaque centers do not fill the external rectangular corners", centers_inside)
	var front: Dictionary = small.components[5]
	_check("opaque reading field is provided by the paper layer only", _patches(front, "center").size() == 1 and front.tint.a == 1.0)
	_check("ink never adds an opaque center rectangle", _patches(small.components[6], "center").is_empty())
	for invalid: Rect2 in [Rect2(), Rect2(0, 0, -1, 20), Rect2(NAN, 0, 20, 20), Rect2(0, 0, INF, 20)]:
		_check("invalid rectangles produce no component geometry", RosePaperStyle.plan_for(invalid, &"card", fixture).components.is_empty())


func _test_registration(fixture: Dictionary) -> void:
	var plan := RosePaperStyle.plan_for(Rect2(0, 0, 112, 184), &"card", fixture)
	var paper: Dictionary = plan.components[5]
	var shadow: Dictionary = plan.components[4]
	_check("shadow padding is measured against paper registration", shadow.rect == paper.rect.grow(1.0))
	var paper_corner: Dictionary = _patches(paper, "corner_0")[0]
	var shadow_corner: Dictionary = _patches(shadow, "corner_0")[0]
	_check("shadow and shape retain the same registered source scale", is_equal_approx(paper_corner.destination.size.x / paper_corner.source.size.x, shadow_corner.destination.size.x / shadow_corner.source.size.x))
	var paper_inner: Vector2 = paper_corner.destination.end
	var shadow_inner: Vector2 = shadow_corner.destination.end
	_check("shadow inner boundary aligns with paper before the deliberate shadow offset", paper_inner.is_equal_approx(shadow_inner))
	_check("shadow offset remains a separate small translation", (shadow.transform.origin - paper.transform.origin).is_equal_approx(Vector2(1.0, 1.5)))
	_check("shadow tint remains translucent while paper is opaque", shadow.tint.a <= 0.11 and paper.tint.a == 1.0)
	_check("actual bounds include rotated shadow coverage", plan.bounds.encloses(shadow.bounds) and plan.bounds.encloses(paper.bounds))


func _test_density_and_rotation(fixture: Dictionary) -> void:
	var plan := RosePaperStyle.plan_for(Rect2(0, 0, 964, 280), &"dialogue", fixture)
	var plain_repeat := true
	var rigid := true
	for component: Dictionary in plan.components:
		for patch: Dictionary in component.patches:
			if patch.kind == &"center":
				continue
			plain_repeat = plain_repeat and not patch.flip_h and not patch.flip_v
			var quad: PackedVector2Array = patch.quad
			var horizontal := quad[1] - quad[0]
			var vertical := quad[3] - quad[0]
			var destination: Rect2 = patch.destination
			rigid = rigid and is_equal_approx(horizontal.length(), destination.size.x) and is_equal_approx(vertical.length(), destination.size.y) and absf(horizontal.normalized().dot(vertical.normalized())) < 0.0001
	_check("mask and texture mapping do not force mirror alternation", plain_repeat)
	_check("rotating a backing never shears or scales its paper pixels", rigid)
	_check("backing papers use distinct slight rotations", is_equal_approx(plan.layers[0].rotation_deg, -0.4) and is_equal_approx(plan.layers[1].rotation_deg, 0.6))
	var front: Dictionary = plan.components[5]
	_check("brush coordinates use whole-paper logical dimensions", front.texture_logical_size == Vector2(640, 640) and front.paper_origin == plan.face_rect.position)
	var edges := _patches(front, "edge_0")
	_check("long alpha edges repeat and crop a final piece", edges.size() > 1 and edges.back().source.size.x < edges.front().source.size.x)
	var moved := RosePaperStyle.plan_for(Rect2(75, -30, 964, 280), &"dialogue", fixture)
	_check("moving a paper translates the brush anchor with its shape", moved.components[5].paper_origin == front.paper_origin + Vector2(75, -30))
	var coarse := fixture.duplicate(true)
	coarse.roles.dialogue.layers[2].tile_width = 1100
	var coarse_plan := RosePaperStyle.plan_for(Rect2(0, 0, 964, 280), &"dialogue", coarse)
	_check("reference-scale texture can exceed the old 512 pixel limit", coarse_plan.components[5].texture_logical_size == Vector2(1100, 1100))
	var tiny := RosePaperStyle.plan_for(Rect2(0, 0, 3, 2), &"card", fixture)
	var valid_tiny := true
	for component: Dictionary in tiny.components:
		valid_tiny = valid_tiny and component.rect.has_area() and component.bounds.position.is_finite() and component.bounds.size.is_finite()
	_check("tiny controls remain finite without stretching the corner pieces", valid_tiny)


func _test_compositor(fixture: Dictionary) -> void:
	var plan := RosePaperStyle.plan_for(Rect2(0, 0, 112, 184), &"card", fixture)
	var prepared := RosePaperCompositor.prepare_components(plan, _fixture_textures)
	_check("compositor prepares one isolated material per mask component", prepared.size() == 7)
	_check("paper shadow and ink retain independent shader modes", prepared[0].material.get_shader_parameter("layer_mode") == 1 and prepared[1].material.get_shader_parameter("layer_mode") == 0 and prepared[6].material.get_shader_parameter("layer_mode") == 2)
	_check("faint black alpha shadows have an independent gain", is_equal_approx(prepared[0].material.get_shader_parameter("mask_alpha_gain"), 2.0) and is_equal_approx(prepared[1].material.get_shader_parameter("mask_alpha_gain"), 1.0))
	_check("paper shader binds neutral brush independently of alpha shape", prepared[1].material.get_shader_parameter("brush_texture") == _fixture_textures[plan.components[1].texture_path] and prepared[1].mask == _fixture_textures[plan.components[1].mask_path])
	_check("independent layers do not share mutable material state", prepared[1].material != prepared[3].material and prepared[1].material != prepared[0].material)
	_check("brush mapping is not the mask UV transform", prepared[1].material.get_shader_parameter("texture_logical_size") == Vector2(640, 640))
	var mesh_ok := true
	var preserved := true
	for index in prepared.size():
		var mesh: Dictionary = prepared[index].mesh
		mesh_ok = mesh_ok and mesh.points.size() == mesh.uvs.size() and mesh.indices.size() == mesh.points.size() / 4 * 6
		for vertex: int in mesh.indices:
			mesh_ok = mesh_ok and vertex >= 0 and vertex < mesh.points.size()
		var expected := 0
		for patch: Dictionary in plan.components[index].patches:
			if patch.kind != &"center":
				expected += 4
		preserved = preserved and mesh.points.size() == expected
	_check("compositor emits valid indexed mask meshes", mesh_ok)
	_check("batched meshes preserve all generated alpha edge pieces", preserved)
	var geometry := RosePaperCompositor.surface_geometry(plan.bounds, 4.0)
	_check("card cache reserves at least four physical pixels per logical pixel", geometry.pixel_ratio >= 4.0)
	_check("cache output mapping has identical x and y pixel density", is_equal_approx(float(geometry.pixel_size.x) / geometry.bounds.size.x, float(geometry.pixel_size.y) / geometry.bounds.size.y))
	_check("cache includes transparent padding around complete rotated bounds", geometry.bounds.encloses(plan.bounds))
	var huge := RosePaperCompositor.surface_geometry(Rect2(-4, -4, 5000, 1100), 8.0)
	_check("very large panels respect the GPU texture dimension limit", huge.pixel_size.x <= RosePaperCompositor.MAX_DIMENSION and huge.pixel_size.y <= RosePaperCompositor.MAX_DIMENSION)
	_check("runtime card quality floor is four times logical resolution", RosePaperStyle.pixel_ratio_for(&"card") >= 4.0)
	var compositor := RosePaperCompositor.new()
	var owner := RefCounted.new()
	var first := compositor.request(plan, _fixture_textures, 4.0, owner, "paper")
	var second := compositor.request(plan, _fixture_textures, 4.0, owner, "paper")
	_check("same role size and pixel density reuse the composited surface", first.key == second.key and compositor.entries.size() == 1)
	var larger_plan := RosePaperStyle.plan_for(Rect2(0, 0, 160, 210), &"card", fixture)
	var larger := compositor.request(larger_plan, _fixture_textures, 4.0, owner, "paper")
	_check("resize requests a new composition instead of stretching a cached one", larger.key != first.key and larger.pixel_size != first.pixel_size)
	compositor.prune_unreferenced()
	_check("replaced surface is released after its consumer moves to new size", compositor.entries.size() == 1 and compositor.entries.has(larger.key))
	owner = null
	compositor.prune_unreferenced()
	_check("unreferenced materials and surface RIDs are reclaimed", compositor.entries.is_empty() and compositor.allocated_bytes == 0)
	compositor.clear()
	_check("headless path never claims that a GPU surface was rendered", not first.headless or not first.ready)
	for index in RosePaperCompositor.MAX_ENTRIES + 3:
		var alternate := plan.duplicate()
		alternate.role = "temporary_%d" % index
		compositor.request(alternate, _fixture_textures, 4.0)
	_check("unowned compositions cannot grow the cache without a bound", compositor.entries.size() <= RosePaperCompositor.MAX_ENTRIES and compositor.allocated_bytes <= RosePaperCompositor.MAX_BYTES)
	compositor.prune_unreferenced()
	_check("cache sweep releases every unowned GPU allocation", compositor.entries.is_empty() and compositor.allocated_bytes == 0 and compositor.created_surfaces == compositor.released_surfaces)
	compositor.clear()


func _test_gpu_composite(fixture: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		print("GPU_PIXEL_PROOF: deferred; headless has no render target")
		return
	RosePaperStyle._layout = fixture
	RosePaperStyle._layout_loaded = true
	var compositor := RosePaperCompositor.new()
	var plan := RosePaperStyle.plan_for(Rect2(0, 0, 112, 184), &"card", fixture)
	var surface := compositor.request(plan, _fixture_textures, 4.0)
	for index in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	_check("GPU cache produces a real viewport texture", surface.ready and surface.texture.is_valid() and surface.items.size() == plan.components.size())
	var pixels := RenderingServer.texture_2d_get(surface.texture)
	_check("GPU texture can be read back at the requested dimensions", pixels != null and pixels.get_size() == surface.pixel_size)
	if pixels != null:
		var center := Vector2i((plan.face_rect.get_center() - surface.bounds.position) * surface.pixel_ratio)
		_check("GPU reading field remains fully opaque", pixels.get_pixelv(center).a > 0.995)
		_check("GPU exterior remains transparent", pixels.get_pixel(0, 0).a < 0.01)
		var visible_shadow := false
		for y in range(0, pixels.get_height(), 2):
			for x in range(0, pixels.get_width(), 2):
				var pixel := pixels.get_pixel(x, y)
				visible_shadow = visible_shadow or (pixel.a > 0.005 and pixel.a < 0.2 and pixel.r < 0.3)
		_check("GPU uses the alpha of a black shadow mask", visible_shadow)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var probe := ParentMaterialProbe.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0, 0.0, 0.0, 1.0); }"
	var sentinel := ShaderMaterial.new()
	sentinel.shader = shader
	probe.material = sentinel
	viewport.add_child(probe)
	for index in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var observed := viewport.get_texture().get_image().get_pixel(47, 7)
	_check("paper composition cannot replace the parent's text or portrait material", observed.r > 0.99 and observed.g < 0.01 and observed.b < 0.01)
	viewport.queue_free()
	compositor.clear()


func _test_real_assets() -> void:
	_check("new mask layout exists", FileAccess.file_exists(RosePaperStyle.LAYOUT_PATH))
	if not FileAccess.file_exists(RosePaperStyle.LAYOUT_PATH):
		return
	var checked := {}
	for role: StringName in [&"card", &"dialogue", &"panel", &"label", &"button"]:
		var plan := RosePaperStyle.plan_for(Rect2(0, 0, 112 if role == &"card" else 964, 184 if role == &"card" else 280), role)
		_check("live role has separate mask components " + String(role), not plan.components.is_empty())
		var paper_count := 0
		var shadow_count := 0
		for component: Dictionary in plan.components:
			if component.mode == &"paper":
				paper_count += 1
				_check("live paper keeps the intended brush density " + String(role), component.texture_logical_size.x >= (192.0 if role == &"card" else 384.0))
				_check("live paper center is opaque " + String(role), component.tint.a == 1.0 and not _patches(component, "center").is_empty())
				_check("live texture mean is removed before tint modulation " + String(role), is_equal_approx(component.texture_neutral, 0.89))
			elif component.mode == &"shadow":
				shadow_count += 1
				_check("live shadow is independent and restrained " + String(role), component.tint.a <= 0.18)
			for path: String in [component.mask_path, component.texture_path]:
				if checked.has(path):
					continue
				checked[path] = true
				var texture := RosePaperStyle._texture(path)
				_check("real mask or texture source exists " + path.get_file(), texture != null)
				if texture == null:
					continue
				var image := texture.get_image()
				var sample := image.get_pixelv(image.get_size() / 2)
				if path.get_file().begins_with("shape_"):
					_check("shape source is a white alpha mask " + path.get_file(), sample.r > 0.9 and sample.g > 0.9 and sample.b > 0.9 and sample.a > 0.85)
					_check("shape source keeps transparent external canvas " + path.get_file(), image.get_pixel(0, 0).a < 0.01)
				elif path.get_file().begins_with("brush_"):
					_check("brush source is neutral instead of precolored paper", absf(sample.r - sample.g) + absf(sample.g - sample.b) < 0.04 and sample.a > 0.99)
		_check("every live paper has its own shadow mask " + String(role), paper_count > 0 and paper_count == shadow_count)


func _test_card_geometry() -> void:
	_check("card logical footprint remains unchanged", TableCardView.CARD_SIZE == Vector2(112, 184))
	_check("card art stays inside and the independent title overlaps its paper", TableCardView.FACE_RECT.encloses(TableCardView.ART_RECT) and TableCardView.FACE_RECT.intersects(TableCardView.TITLE_RECT) and TableCardView.TITLE_RECT.position.x >= TableCardView.FACE_RECT.position.x and TableCardView.TITLE_RECT.end.x <= TableCardView.FACE_RECT.end.x)
	var view := TableCardView.new()
	view.snap_to(Vector2(40, 60))
	_check("card center remains pickable", view.hit_test(Vector2(96, 152)))
	_check("backing shape cannot enlarge the logical hitbox", not view.hit_test(Vector2(39, 150)))
	view.free()


func _patches(component: Dictionary, kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for patch: Dictionary in component.patches:
		if String(patch.kind) == kind:
			result.append(patch)
	return result


func _uniform(patch: Dictionary) -> bool:
	var source: Rect2 = patch.source
	var target: Rect2 = patch.destination
	return source.has_area() and target.has_area() and is_equal_approx(target.size.x / source.size.x, target.size.y / source.size.y)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL " + label)
