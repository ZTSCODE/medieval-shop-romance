import json
import math
import pathlib

import maya.api.OpenMaya as om
import maya.cmds as cmds
import maya.mel as mel
import maya.standalone


maya.standalone.initialize(name="python")
root = pathlib.Path.cwd()
output = root / "outputs" / "maya-board-mesh"
source = json.loads((output / "source-mesh.json").read_text(encoding="utf-8"))

board_uv = source["surfaces"][1]["uv"]
board_left = min(point[0] for point in board_uv)
board_right = max(point[0] for point in board_uv)
board_back = min(point[1] for point in board_uv)
board_front = max(point[1] for point in board_uv)
hinge = board_back - 0.78
bevel_length = 1.6
terrain_width = 180.0
terrain_back = -300.0
terrain_front = 180.0

xs = [-terrain_width, board_left, board_right, terrain_width]
for x in range(-170, 180, 10):
    if all(abs(float(x) - edge) > 0.01 for edge in (board_left, board_right)):
        xs.append(float(x))
xs = sorted(set(xs))

cmds.file(new=True, force=True)
cmds.currentUnit(linear="cm")
cmds.loadPlugin("fbxmaya")


def material(name, color):
    shader = cmds.shadingNode("lambert", asShader=True, name=name)
    cmds.setAttr(shader + ".color", *color, type="double3")
    group = cmds.sets(renderable=True, noSurfaceShader=True, empty=True, name=name + "SG")
    cmds.connectAttr(shader + ".outColor", group + ".surfaceShader", force=True)
    return group


terrain_sg = material("Terrain", (0.19, 0.16, 0.12))
board_sg = material("Board", (0.34, 0.25, 0.17))


def create_section(name, logical_rows, local_anchor_y, rotation_x, translation_y, translation_z):
    points = om.MPointArray()
    for logical_y in logical_rows:
        local_z = (logical_y - local_anchor_y) * 100.0
        for x in xs:
            points.append(om.MPoint(x * 100.0, 0.0, local_z))

    counts = []
    connects = []
    face_centers = []
    row_width = len(xs)
    for row in range(len(logical_rows) - 1):
        for column in range(len(xs) - 1):
            counts.append(4)
            connects.extend(
                [
                    row * row_width + column,
                    (row + 1) * row_width + column,
                    (row + 1) * row_width + column + 1,
                    row * row_width + column + 1,
                ]
            )
            face_centers.append(
                (
                    (xs[column] + xs[column + 1]) * 0.5,
                    (logical_rows[row] + logical_rows[row + 1]) * 0.5,
                )
            )

    mesh_fn = om.MFnMesh()
    mesh_fn.create(points, counts, connects)
    shape_path = mesh_fn.getPath()
    shape = cmds.rename(shape_path.fullPathName(), name + "Shape")
    transform = cmds.listRelatives(shape, parent=True, fullPath=True)[0]
    transform = cmds.rename(transform, name)

    tiled_u = []
    tiled_v = []
    raw_u = []
    raw_v = []
    uv_counts = []
    uv_ids = []
    uv_id = 0
    for face_index, (center_x, center_y) in enumerate(face_centers):
        row = face_index // (len(xs) - 1)
        column = face_index % (len(xs) - 1)
        corners = [
            (xs[column], logical_rows[row]),
            (xs[column], logical_rows[row + 1]),
            (xs[column + 1], logical_rows[row + 1]),
            (xs[column + 1], logical_rows[row]),
        ]
        is_board = (
            board_left <= center_x <= board_right
            and board_back <= center_y <= board_front
            and name == "BoardTerrain_Flat_0deg"
        )
        tile_size = 6.0 if is_board else 4.0
        uv_counts.append(4)
        for x, y in corners:
            tiled_u.append(x / tile_size)
            tiled_v.append(-y / tile_size)
            raw_u.append(x)
            raw_v.append(y)
            uv_ids.append(uv_id)
            uv_id += 1

    default_uv = mesh_fn.currentUVSetName()
    mesh_fn.renameUVSet(default_uv, "TiledMaterialUV")
    mesh_fn.setUVs(tiled_u, tiled_v, "TiledMaterialUV")
    mesh_fn.assignUVs(uv_counts, uv_ids, "TiledMaterialUV")
    mesh_fn.createUVSet("UnfoldedMetersUV")
    mesh_fn.setUVs(raw_u, raw_v, "UnfoldedMetersUV")
    mesh_fn.assignUVs(uv_counts, uv_ids, "UnfoldedMetersUV")

    cmds.sets(transform, edit=True, forceElement=terrain_sg)
    board_faces = []
    for face_index, (center_x, center_y) in enumerate(face_centers):
        if (
            name == "BoardTerrain_Flat_0deg"
            and board_left <= center_x <= board_right
            and board_back <= center_y <= board_front
        ):
            board_faces.append("{}.f[{}]".format(transform, face_index))
    if board_faces:
        cmds.sets(board_faces, edit=True, forceElement=board_sg)

    cmds.setAttr(transform + ".rotateX", rotation_x)
    cmds.setAttr(transform + ".translateY", translation_y)
    cmds.setAttr(transform + ".translateZ", translation_z)
    return transform


flat = create_section(
    "BoardTerrain_Flat_0deg",
    [hinge, board_back, board_front, terrain_front],
    hinge,
    0.0,
    -1.8,
    hinge * 100.0,
)
bevel = create_section(
    "BoardTerrain_Bevel_30deg",
    [hinge - bevel_length, hinge],
    hinge,
    -30.0,
    -1.8,
    hinge * 100.0,
)
bevel_end_y = (-math.sin(math.radians(30.0)) * bevel_length - 0.018) * 100.0
bevel_end_z = (hinge - math.cos(math.radians(30.0)) * bevel_length) * 100.0
rear = create_section(
    "BoardTerrain_Rear_60deg",
    [terrain_back, hinge - bevel_length],
    hinge - bevel_length,
    -60.0,
    bevel_end_y,
    bevel_end_z,
)

group = cmds.group(flat, bevel, rear, name="BoardTerrain_AlignedAxes")
cmds.select(group, hierarchy=True)
mel.eval("FBXResetExport;")
mel.eval("FBXExportUpAxis y;")
mel.eval("FBXExportConvertUnitString cm;")
mel.eval("FBXExportInputConnections -v false;")
mel.eval("FBXExportBakeComplexAnimation -v false;")
target = (output / "board-terrain-original-clean-axes.fbx").as_posix()
mel.eval('FBXExport -f "{}" -s;'.format(target))

report = {
    "file": pathlib.Path(target).name,
    "unit": "centimeter",
    "objects": [
        {"name": flat, "rotation_x": 0.0, "scale": [1.0, 1.0, 1.0]},
        {"name": bevel, "rotation_x": -30.0, "scale": [1.0, 1.0, 1.0]},
        {"name": rear, "rotation_x": -60.0, "scale": [1.0, 1.0, 1.0]},
    ],
    "outer_edges": "straight",
    "note": "The three objects meet at identical seam positions; local Y is the face normal and local Z follows the face slope.",
}
(output / "clean-axes-export.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("MAYA_CLEAN_AXES_EXPORTED")
maya.standalone.uninitialize()
