import json
import pathlib

import maya.cmds as cmds
import maya.standalone


maya.standalone.initialize(name="python")
root = pathlib.Path.cwd()
output = root / "outputs" / "maya-board-mesh"
cmds.loadPlugin("fbxmaya")
cmds.file(new=True, force=True)
cmds.currentUnit(linear="cm")
cmds.file(str(output / "board-terrain-maya-focused.fbx"), i=True, type="FBX", ignoreVersion=True)
meshes = cmds.ls(type="mesh", long=True)
assert len(meshes) == 1, meshes
mesh = meshes[0]
report = {
    "file": "board-terrain-maya-focused.fbx",
    "vertices": cmds.polyEvaluate(mesh, vertex=True),
    "faces": cmds.polyEvaluate(mesh, face=True),
    "shells": cmds.polyEvaluate(mesh, shell=True),
    "uv_sets": cmds.polyUVSet(mesh, q=True, allUVSets=True),
    "bounds_cm": cmds.exactWorldBoundingBox(mesh),
}
assert report["shells"] == 1, report
assert len(report["uv_sets"]) == 2, report
assert 4400.0 < report["bounds_cm"][3] - report["bounds_cm"][0] < 4600.0, report
(output / "focused-maya-validation.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("MAYA_FOCUSED_IMPORT_PASS")
maya.standalone.uninitialize()
