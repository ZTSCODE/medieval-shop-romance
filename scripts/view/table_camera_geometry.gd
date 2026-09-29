class_name TableCameraGeometry
extends RefCounted

const PIXELS_PER_UNIT := 100.0
const FOV_DEGREES := 32.0
const ELEVATION_DEGREES := 72.0
const MENU_REAR_OFFSET_METERS := 6.0


static func gameplay_transform(
	viewport_height: float,
	zoom: float,
	center_pixels: Vector2
) -> Transform3D:
	var safe_zoom := maxf(zoom, 0.01)
	var target := Vector3(
		center_pixels.x / PIXELS_PER_UNIT,
		0.0,
		center_pixels.y / PIXELS_PER_UNIT
	)
	return _camera_transform(viewport_height, safe_zoom, target)


static func menu_transform(viewport_height: float) -> Transform3D:
	var target := Vector3(
		0.0,
		0.0,
		FoldedTerrain.hinge_z() - MENU_REAR_OFFSET_METERS
	)
	return _camera_transform(viewport_height, TableCamera.MIN_ZOOM, target)


static func _camera_transform(
	viewport_height: float,
	zoom: float,
	target: Vector3
) -> Transform3D:
	var distance := maxf(viewport_height, 1.0) / (
		2.0
		* tan(deg_to_rad(FOV_DEGREES * 0.5))
		* PIXELS_PER_UNIT
		* zoom
	)
	var elevation := deg_to_rad(ELEVATION_DEGREES)
	var position := target + Vector3(
		0.0,
		sin(elevation),
		cos(elevation)
	) * distance
	var basis := Basis.from_euler(Vector3(-elevation, 0.0, 0.0))
	return Transform3D(basis, position)
