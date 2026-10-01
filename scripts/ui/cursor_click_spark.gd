extends Node2D

# Screen-position handle for real world-space dust. Only the CPUParticles3D
# children render; this node never draws a 2D substitute.
const DURATION := 1.1
const CLEANUP_DEADLINE := 1.35
const MOTES_PER_CLICK := 32

static var _dust_texture: GradientTexture2D
static var _fade: Gradient
static var _tints: Gradient
static var _shrink: Curve
static var _mote_mesh: QuadMesh
var emitters: Array[CPUParticles3D] = []
var _age := 0.0


func setup(at: Vector2, stage: Node = null) -> void:
	position = at
	process_mode = Node.PROCESS_MODE_ALWAYS
	if stage == null:
		return
	var ground: Vector2 = stage.to_terrain(at)
	if not ground.is_finite():
		return
	_ensure_shared_resources()
	var origin := FoldedTerrain.world_position(ground) + Vector3.UP * 0.04
	for haze in [false, true]:
		var dust := CPUParticles3D.new()
		dust.emitting = false
		dust.process_mode = Node.PROCESS_MODE_PAUSABLE
		dust.amount = 7 if haze else MOTES_PER_CLICK
		dust.lifetime = DURATION
		dust.one_shot = true
		dust.explosiveness = 0.96
		dust.lifetime_randomness = 0.4
		dust.local_coords = false
		dust.mesh = _mote_mesh
		dust.color = Color(1, 1, 1, 0.12 if haze else 0.85)
		dust.color_initial_ramp = _tints
		dust.color_ramp = _fade
		dust.scale_amount_curve = _shrink
		dust.scale_amount_min = 0.07 if haze else 0.009
		dust.scale_amount_max = 0.16 if haze else 0.032
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		dust.emission_sphere_radius = 0.035
		dust.direction = Vector3.UP
		dust.spread = 78.0
		dust.initial_velocity_min = 0.22 if haze else 0.32
		dust.initial_velocity_max = 0.60 if haze else 1.05
		dust.damping_min = 0.38
		dust.damping_max = 0.78
		dust.gravity = Vector3(0.07, 0.02, -0.03)
		dust.angular_velocity_min = -70.0
		dust.angular_velocity_max = 70.0
		dust.angle_min = -180.0
		dust.angle_max = 180.0
		dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.scene_root.add_child(dust)
		dust.position = origin
		emitters.append(dust)
		dust.restart()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_age += delta
	if _age >= CLEANUP_DEADLINE:
		queue_free()


func _exit_tree() -> void:
	# Emitters live in the stage's World3D, so explicitly retire them even when
	# rapid-click eviction, scene replacement, or shutdown removes this handle.
	for dust in emitters:
		if is_instance_valid(dust):
			dust.queue_free()
	emitters.clear()


static func _ensure_shared_resources() -> void:
	if _dust_texture != null:
		return
	var profile := Gradient.new()
	profile.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	profile.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.82), Color(1, 1, 1, 0)])
	_dust_texture = GradientTexture2D.new()
	_dust_texture.width = 16
	_dust_texture.height = 16
	_dust_texture.gradient = profile
	_dust_texture.fill = GradientTexture2D.FILL_RADIAL
	_dust_texture.fill_from = Vector2(0.5, 0.5)
	_dust_texture.fill_to = Vector2(1.0, 1.0)
	_fade = Gradient.new()
	_fade.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 1.0])
	_fade.colors = PackedColorArray([Color(1, 1, 1, 0.52), Color(1, 1, 1, 0.78), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0)])
	_tints = Gradient.new()
	_tints.colors = PackedColorArray([Color("a79c88"), Color("d4cbb8")])
	_shrink = Curve.new()
	_shrink.add_point(Vector2(0.0, 0.85))
	_shrink.add_point(Vector2(0.18, 1.0))
	_shrink.add_point(Vector2(1.0, 0.25))

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _dust_texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mote_mesh = QuadMesh.new()
	_mote_mesh.size = Vector2.ONE
	_mote_mesh.material = material
