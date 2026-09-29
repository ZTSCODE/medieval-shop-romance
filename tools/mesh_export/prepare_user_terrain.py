import bpy
import json
import pathlib
from mathutils import Vector


root = pathlib.Path.cwd()
source = root / "outputs" / "maya-board-mesh" / "mesh.fbx"
target = root / "assets" / "models" / "terrain" / "board-terrain-user-v1.glb"

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=str(source))
mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
if len(mesh_objects) != 1:
    raise RuntimeError("Expected exactly one user terrain mesh, got {}".format(len(mesh_objects)))
obj = mesh_objects[0]

bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

uv_layer = obj.data.uv_layers.get("UnfoldedMetersUV")
if uv_layer is None:
    raise RuntimeError("UnfoldedMetersUV is required to restore game placement")
anchor_points = []
anchor_indices = []
for polygon in obj.data.polygons:
    for loop_index in polygon.loop_indices:
        if abs(uv_layer.data[loop_index].uv.y - 7.1) < 0.001:
            vertex_index = obj.data.loops[loop_index].vertex_index
            anchor_points.append(obj.data.vertices[vertex_index].co.copy())
            anchor_indices.append(vertex_index)
if not anchor_points:
    raise RuntimeError("Could not find the 7.1 meter board anchor row")
anchor = sum(anchor_points, Vector()) / len(anchor_points)
target_anchor = Vector((0.0, -7.1, -0.018))
for vertex in obj.data.vertices:
    vertex.co = (vertex.co - anchor) * 100.0 + target_anchor
placed_anchor = sum((obj.data.vertices[index].co for index in anchor_indices), Vector()) / len(anchor_indices)
anchor_correction = target_anchor - placed_anchor
for vertex in obj.data.vertices:
    vertex.co += anchor_correction
obj.data.update()
obj.name = "BoardTerrainUserV1"
obj.data.name = "BoardTerrainUserV1Mesh"
for material in obj.data.materials:
    if material is not None:
        material.name = "Board" if "Board" in material.name else "Terrain"

bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(
    filepath=str(target),
    export_format="GLB",
    use_selection=True,
    export_yup=True,
    export_texcoords=True,
    export_normals=True,
    export_materials="EXPORT",
    export_apply=True,
)

obj.data.calc_loop_triangles()
raw_uv = obj.data.uv_layers["UnfoldedMetersUV"].data
surface_data = {0: {"vertices": [], "normals": [], "uv": []}, 1: {"vertices": [], "normals": [], "uv": []}}
for triangle in obj.data.loop_triangles:
    polygon = obj.data.polygons[triangle.polygon_index]
    surface = surface_data[1 if polygon.material_index == 1 else 0]
    normal = polygon.normal
    godot_normal = (normal.x, normal.z, -normal.y)
    for vertex_index, loop_index in zip(triangle.vertices, triangle.loops):
        point = obj.data.vertices[vertex_index].co
        uv = raw_uv[loop_index].uv
        surface["vertices"].append([point.x, point.z, -point.y])
        surface["normals"].append(list(godot_normal))
        surface["uv"].append([uv.x, uv.y])
(root / "assets" / "models" / "terrain" / "board-terrain-user-v1.json").write_text(
    json.dumps({"surfaces": surface_data}, separators=(",", ":")), encoding="utf-8"
)

points = [vertex.co for vertex in obj.data.vertices]
profile_rows = {}
for polygon in obj.data.polygons:
    for loop_index in polygon.loop_indices:
        logical_y = round(raw_uv[loop_index].uv.y, 4)
        vertex_index = obj.data.loops[loop_index].vertex_index
        point = obj.data.vertices[vertex_index].co
        profile_rows.setdefault(logical_y, []).append((point.z + 0.018, -point.y))
profile = []
for logical_y, values in sorted(profile_rows.items()):
    profile.append(
        {
            "logical_y": logical_y,
            "world_y": sum(value[0] for value in values) / len(values),
            "world_z": sum(value[1] for value in values) / len(values),
        }
    )
report = {
    "source": str(source),
    "target": str(target),
    "scale_recovery": 100.0,
    "anchor_uv_y": 7.1,
    "anchor_blender": list(anchor),
    "target_anchor_blender": list(target_anchor),
    "vertices": len(obj.data.vertices),
    "faces": len(obj.data.polygons),
    "runtime_triangles": sum(len(surface["vertices"]) // 3 for surface in surface_data.values()),
    "profile": profile,
    "bounds_blender": [
        [min(point[i] for point in points) for i in range(3)],
        [max(point[i] for point in points) for i in range(3)],
    ],
}
(root / "outputs" / "maya-board-mesh" / "user-terrain-conversion.json").write_text(
    json.dumps(report, indent=2), encoding="utf-8"
)
print(json.dumps(report))
