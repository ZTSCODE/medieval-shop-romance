class_name FoldedTerrain
extends RefCounted

const FOLD_ANGLE := deg_to_rad(60.0)
const BEVEL_ANGLE := deg_to_rad(30.0)
const BEVEL_LENGTH := 1.6
const TERRAIN_DEPTH := 30000.0
const TERRAIN_WIDTH := 18000.0

static func hinge_z() -> float:
	return TableState.WORLD_BOUNDS.position.y / 100.0 - 0.78

static func world_position(logical: Vector2) -> Vector3:
	var flat := logical / 100.0
	var depth := maxf(0.0, hinge_z() - flat.y)
	if depth <= 0.0:
		return Vector3(flat.x,0,flat.y)
	var bevel := minf(depth,BEVEL_LENGTH)
	var rear := maxf(0.0,depth-BEVEL_LENGTH)
	return Vector3(flat.x,-sin(BEVEL_ANGLE)*bevel-sin(FOLD_ANGLE)*rear,hinge_z()-cos(BEVEL_ANGLE)*bevel-cos(FOLD_ANGLE)*rear)

static func from_ray(origin: Vector3, direction: Vector3) -> Vector2:
	var answer := Vector2.INF
	var nearest := INF
	for section in 3:
		var angle := [0.0,BEVEL_ANGLE,FOLD_ANGLE][section] as float
		var start_depth := BEVEL_LENGTH if section==2 else 0.0
		var start := world_position(Vector2(0,(hinge_z()-start_depth)*100.0))
		var normal := Vector3(0,cos(angle),-sin(angle))
		var hit: Variant = Plane(normal,normal.dot(start)).intersects_ray(origin,direction)
		if hit == null:
			continue
		var depth: float = start_depth+(start.z-hit.z)/cos(angle)
		var belongs: bool = depth<=0.00001 if section==0 else (depth>=-0.00001 and depth<=BEVEL_LENGTH+0.00001 if section==1 else depth>=BEVEL_LENGTH-0.00001)
		if belongs and origin.distance_squared_to(hit)<nearest:
			nearest = origin.distance_squared_to(hit)
			answer = Vector2(hit.x,hinge_z()-depth)*100.0
	return answer

static func terminal_z(x: float) -> float:
	return -TERRAIN_DEPTH + 3800.0*sin(x/3100.0) + 1900.0*sin(x/1270.0+0.7)

static func make_mesh(board_material: Material, ground_material: Material) -> ArrayMesh:
	var bounds := TableState.WORLD_BOUNDS
	var xs := [-TERRAIN_WIDTH, bounds.position.x, bounds.end.x, TERRAIN_WIDTH]
	for x in range(-17000,18000,1000):
		if absf(float(x)-bounds.position.x)>1 and absf(float(x)-bounds.end.x)>1:
			xs.append(float(x))
	xs.sort()
	var zs := [-TERRAIN_DEPTH, (hinge_z()-BEVEL_LENGTH)*100.0, hinge_z() * 100.0, bounds.position.y, bounds.end.y, TERRAIN_WIDTH]
	var mesh := ArrayMesh.new()
	for is_board in [false, true]:
		var build := SurfaceTool.new()
		build.begin(Mesh.PRIMITIVE_TRIANGLES)
		for zi in range(zs.size() - 1):
			for xi in range(xs.size() - 1):
				var center := Vector2((xs[xi]+xs[xi+1])*0.5, (zs[zi]+zs[zi+1])*0.5)
				if bounds.has_point(center) != is_board:
					continue
				var points := [Vector2(xs[xi],zs[zi]),Vector2(xs[xi+1],zs[zi]),Vector2(xs[xi+1],zs[zi+1]),Vector2(xs[xi],zs[zi+1])]
				for index in [0, 2, 1, 0, 3, 2]:
					var point: Vector2 = points[index]
					if is_equal_approx(point.y,-TERRAIN_DEPTH):
						point.y = terminal_z(point.x)
					build.set_uv(point / 100.0)
					build.add_vertex(world_position(point) - Vector3(0, 0.018, 0))
		build.generate_normals()
		build.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count()-1, board_material if is_board else ground_material)
	return mesh
