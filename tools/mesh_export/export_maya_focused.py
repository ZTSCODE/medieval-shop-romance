import bpy
import json
import math
import pathlib
import shutil

from mathutils import Vector


ROOT = pathlib.Path.cwd()
OUT = ROOT / "outputs" / "maya-board-mesh"
SOURCE = json.loads((OUT / "source-mesh.json").read_text(encoding="utf-8"))


def axis_values(start, end, step, mandatory):
    values = [start, end, *mandatory]
    cursor = math.ceil(start / step) * step
    while cursor < end:
        values.append(cursor)
        cursor += step
    return sorted(set(round(value, 6) for value in values if start <= value <= end))


board_uv = SOURCE["surfaces"][1]["uv"]
board_left = min(point[0] for point in board_uv)
board_right = max(point[0] for point in board_uv)
board_back = min(point[1] for point in board_uv)
board_front = max(point[1] for point in board_uv)
hinge = board_back - 0.78
bevel_length = 1.6
bevel_angle = math.radians(30.0)
rear_angle = math.radians(60.0)

focused_left = board_left - 12.0
focused_right = board_right + 12.0
focused_back = board_back - 82.0
focused_front = board_front + 8.0

xs = axis_values(focused_left, focused_right, 0.5, [board_left, board_right])
ys = axis_values(
    focused_back,
    focused_front,
    0.5,
    [board_back, board_front, hinge, hinge - bevel_length],
)


def folded_world(x, y):
    depth = max(0.0, hinge - y)
    if depth <= 0.0:
        return Vector((x, y, -0.018))
    bevel = min(depth, bevel_length)
    rear = max(0.0, depth - bevel_length)
    godot_y = -math.sin(bevel_angle) * bevel - math.sin(rear_angle) * rear - 0.018
    godot_z = hinge - math.cos(bevel_angle) * bevel - math.cos(rear_angle) * rear
    return Vector((x, -godot_z, godot_y))


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1.0

materials = []
for name, texture_name in [("Terrain", "forest-floor-tile.png"), ("Board", "earth-tile.png")]:
    texture_out = OUT / "textures" / texture_name
    texture_out.parent.mkdir(exist_ok=True)
    if not texture_out.exists():
        shutil.copy2(ROOT / "assets" / "art" / "forest_rebuild" / texture_name, texture_out)
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.96
    image = material.node_tree.nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(str(texture_out))
    material.node_tree.links.new(image.outputs["Color"], shader.inputs["Base Color"])
    materials.append(material)

vertices = [folded_world(x, y) for y in ys for x in xs]
faces = []
face_uv = []
material_ids = []
row_width = len(xs)
for yi in range(len(ys) - 1):
    for xi in range(len(xs) - 1):
        faces.append(
            [
                yi * row_width + xi,
                (yi + 1) * row_width + xi,
                (yi + 1) * row_width + xi + 1,
                yi * row_width + xi + 1,
            ]
        )
        corners = [
            Vector((xs[xi], ys[yi])),
            Vector((xs[xi], ys[yi + 1])),
            Vector((xs[xi + 1], ys[yi + 1])),
            Vector((xs[xi + 1], ys[yi])),
        ]
        face_uv.append(corners)
        center_x = (xs[xi] + xs[xi + 1]) * 0.5
        center_y = (ys[yi] + ys[yi + 1]) * 0.5
        material_ids.append(
            1 if board_left <= center_x <= board_right and board_back <= center_y <= board_front else 0
        )

mesh = bpy.data.meshes.new("BoardTerrainMayaFocused")
mesh.from_pydata(vertices, [], faces)
mesh.update()
obj = bpy.data.objects.new("BoardTerrain_Maya_Edit", mesh)
bpy.context.collection.objects.link(obj)
for material in materials:
    mesh.materials.append(material)

tiled = mesh.uv_layers.new(name="TiledMaterialUV")
unfolded = mesh.uv_layers.new(name="UnfoldedMetersUV")
for polygon, corners, material_id in zip(mesh.polygons, face_uv, material_ids):
    polygon.material_index = material_id
    tile_size = 6.0 if material_id == 1 else 4.0
    for loop_index, uv in zip(polygon.loop_indices, corners):
        tiled.data[loop_index].uv = (uv.x / tile_size, -uv.y / tile_size)
        unfolded.data[loop_index].uv = uv
mesh.uv_layers.active_index = 0

bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
output_path = OUT / "board-terrain-maya-focused.fbx"
bpy.ops.export_scene.fbx(
    filepath=str(output_path),
    use_selection=True,
    object_types={"MESH"},
    axis_forward="-Z",
    axis_up="Y",
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_UNITS",
    use_mesh_modifiers=False,
    mesh_smooth_type="FACE",
    use_triangles=False,
    bake_anim=False,
    path_mode="RELATIVE",
)

report = {
    "file": output_path.name,
    "game_unit": "1 Godot unit = 1 meter",
    "maya_default_unit": "centimeter; Maya imports 1 meter as 100 centimeters",
    "board_width_m": board_right - board_left,
    "focused_width_m": focused_right - focused_left,
    "focused_unfolded_depth_m": focused_front - focused_back,
    "rear_depth_from_board_m": board_back - focused_back,
    "vertices": len(mesh.vertices),
    "quads": len(mesh.polygons),
    "uv_layers": len(mesh.uv_layers),
}
(OUT / "focused-validation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report))
