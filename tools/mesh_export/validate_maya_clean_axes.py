import json
import pathlib

import maya.cmds as cmds
import maya.standalone


maya.standalone.initialize(name="python")
root = pathlib.Path.cwd()
output = root / "outputs" / "maya-board-mesh"
cmds.file(new=True, force=True)
cmds.currentUnit(linear="cm")
cmds.loadPlugin("fbxmaya")
cmds.file(
    str(output / "board-terrain-original-clean-axes.fbx"),
    i=True,
    type="FBX",
    ignoreVersion=True,
)

expected = {
    "BoardTerrain_Flat_0deg": 0.0,
    "BoardTerrain_Bevel_30deg": -30.0,
    "BoardTerrain_Rear_60deg": -60.0,
}
objects = []
for name, expected_rotation in expected.items():
    assert cmds.objExists(name), name
    scale = list(cmds.getAttr(name + ".scale")[0])
    rotation = list(cmds.getAttr(name + ".rotate")[0])
    uv_sets = cmds.polyUVSet(name, q=True, allUVSets=True)
    assert max(abs(value - 1.0) for value in scale) < 0.0001, (name, scale)
    assert abs(rotation[0] - expected_rotation) < 0.001, (name, rotation)
    assert len(uv_sets) == 2, (name, uv_sets)
    objects.append(
        {
            "name": name,
            "scale": scale,
            "rotation": rotation,
            "faces": cmds.polyEvaluate(name, face=True),
            "shells": cmds.polyEvaluate(name, shell=True),
            "uv_sets": uv_sets,
            "bounds_cm": cmds.exactWorldBoundingBox(name),
        }
    )

flat_box = cmds.exactWorldBoundingBox("BoardTerrain_Flat_0deg")
rear_box = cmds.exactWorldBoundingBox("BoardTerrain_Rear_60deg")
assert abs((flat_box[3] - flat_box[0]) - 36000.0) < 0.1
assert abs((rear_box[3] - rear_box[0]) - 36000.0) < 0.1
bevel_box = cmds.exactWorldBoundingBox("BoardTerrain_Bevel_30deg")
assert abs(flat_box[2] - bevel_box[5]) < 0.1, (flat_box, bevel_box)
assert abs(bevel_box[2] - rear_box[5]) < 0.1, (bevel_box, rear_box)
assert abs(flat_box[1] - bevel_box[4]) < 0.1, (flat_box, bevel_box)
assert abs(bevel_box[1] - rear_box[4]) < 0.1, (bevel_box, rear_box)

report = {
    "file": "board-terrain-original-clean-axes.fbx",
    "maya_import": "PASS",
    "objects": objects,
}
(output / "clean-axes-maya-validation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("MAYA_CLEAN_AXES_IMPORT_PASS")
maya.standalone.uninitialize()
