import bpy
import collections


bpy.ops.import_scene.fbx(
    filepath=r"C:/Users/ZTCUS/Documents/Codex/2026-09-15/medieval-shop-romance/outputs/maya-board-mesh/mesh.fbx"
)
obj = bpy.data.objects.get("BoardTerrain_Rear_60deg")
uv_layer = obj.data.uv_layers["UnfoldedMetersUV"]
rows = collections.defaultdict(list)
for polygon in obj.data.polygons:
    for loop_index in polygon.loop_indices:
        loop = obj.data.loops[loop_index]
        uv = uv_layer.data[loop_index].uv
        rows[round(uv.y, 3)].append(obj.matrix_world @ obj.data.vertices[loop.vertex_index].co)
for logical_y, points in sorted(rows.items()):
    average = tuple(sum(point[i] for point in points) / len(points) for i in range(3))
    minimum = tuple(min(point[i] for point in points) for i in range(3))
    maximum = tuple(max(point[i] for point in points) for i in range(3))
    print("USER_MESH_ROW", logical_y, len(points), average, minimum, maximum)
