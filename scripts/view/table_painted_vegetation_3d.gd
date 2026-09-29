@tool
class_name TablePaintedVegetation3D
extends Node3D

const EVENT_COUNT := 32
const EVENT_LIFETIME := 1.1

@export var interaction_retrigger_interval := 0.35

var elapsed := 0.0
var _events := PackedVector4Array()
var _directions := PackedVector4Array()
var _segments := PackedVector4Array()
var _next_event := 0
var _last_motion_time := -1.0
var _last_pointer := Vector2(-100000.0,-100000.0)
var _camera_basis := Basis(Vector3.RIGHT,deg_to_rad(-72.0))
var _pointer_light_position := Vector3.ZERO
var _pointer_light_range := 4.5
var _pointer_light_energy := 0.0
var _pointer_light_color := Color("ffd7a0")

func _init() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_events.resize(EVENT_COUNT)
	_directions.resize(EVENT_COUNT)
	_segments.resize(EVENT_COUNT)
	for index in EVENT_COUNT:
		_events[index] = Vector4(0,0,-100,0)

func _ready() -> void:
	_apply_runtime_state()

func set_camera_basis(value: Basis) -> void:
	_camera_basis = value.orthonormalized()
	_apply_runtime_state()

func set_pointer_light(position: Vector3, light_range: float, energy: float, color: Color, enabled: bool) -> void:
	_pointer_light_position = position
	_pointer_light_range = maxf(light_range, 0.001)
	_pointer_light_energy = maxf(energy, 0.0) if enabled else 0.0
	_pointer_light_color = color
	_apply_runtime_state()

func set_pointer(point: Vector2,velocity: Vector2,impulse := false,segment_start := Vector2.INF) -> void:
	if not is_visible_in_tree() or not can_process():
		return
	var start := segment_start
	if not start.is_finite():
		start = _last_pointer if elapsed-_last_motion_time<0.15 and _last_motion_time>=0.0 else point
	if impulse:
		start = point
	_last_pointer = point
	if not impulse and velocity.length()<2.0:
		return
	var direction := velocity.normalized()
	var intensity := 0.8 if impulse else motion_intensity(velocity.length())
	if _interaction_on_cooldown(start,point):
		return
	var slot := _next_event
	if elapsed-_events[slot].z<EVENT_LIFETIME:
		return
	_next_event = (_next_event+1)%EVENT_COUNT
	_events[slot] = Vector4(point.x/100.0,point.y/100.0,elapsed,intensity)
	_segments[slot] = Vector4(start.x/100.0,start.y/100.0,point.x/100.0,point.y/100.0)
	_directions[slot] = Vector4(direction.x,direction.y,0,0)
	_last_motion_time = elapsed
	_apply_runtime_state()

func _interaction_on_cooldown(start: Vector2,finish: Vector2) -> bool:
	for index in EVENT_COUNT:
		var age := elapsed-_events[index].z
		if age<0.0 or age>=interaction_retrigger_interval or _events[index].w<=0.0:
			continue
		var a := Vector2(_segments[index].x,_segments[index].y)*100.0
		var b := Vector2(_segments[index].z,_segments[index].w)*100.0
		var radius := _disturbance_radius_pixels()*0.75
		if start.distance_to(Geometry2D.get_closest_point_to_segment(start,a,b))<=radius and finish.distance_to(Geometry2D.get_closest_point_to_segment(finish,a,b))<=radius:
			return true
	return false

static func motion_intensity(speed: float) -> float:
	return smoothstep(10.0,400.0,speed)

static func interaction_response(age: float) -> float:
	return sin(age*11.0)*exp(-age*4.4) if age>=0.0 and age<EVENT_LIFETIME else 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	elapsed += maxf(delta,0.0)
	_apply_runtime_state()

func _apply_runtime_state() -> void:
	_apply_runtime_state_below(self)

func _apply_runtime_state_below(scope: Node) -> void:
	for child: Node in scope.get_children(true):
		if child.has_method("set_table_environment_state"):
			child.call("set_table_environment_state",elapsed,_events,_directions,_segments,_camera_basis)
		else:
			_apply_runtime_state_below(child)
		if child.has_method("set_table_pointer_light"):
			child.call("set_table_pointer_light",_pointer_light_position,_pointer_light_range,_pointer_light_energy,_pointer_light_color,_pointer_light_energy>0.0)

func _disturbance_radius_pixels() -> float:
	for patch in _grass_patches_below(self):
		if patch.player_interaction_enabled:
			return patch.disturbance_radius*100.0
	return 130.0

func painted_instance_count() -> int:
	var total := 0
	for patch in _grass_patches_below(self):
		total += patch.grass_positions.size()
	return total

func _grass_patches_below(scope: Node) -> Array[GrassPatch3D]:
	var patches: Array[GrassPatch3D] = []
	for child: Node in scope.get_children(true):
		if child is GrassPatch3D:
			patches.append(child as GrassPatch3D)
		else:
			patches.append_array(_grass_patches_below(child))
	return patches
