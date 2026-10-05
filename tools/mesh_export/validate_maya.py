import maya.standalone
maya.standalone.initialize(name='python')
import maya.cmds as cmds
import pathlib, json
out=pathlib.Path.cwd()/'outputs/maya-board-mesh'
cmds.loadPlugin('fbxmaya')
reports=[]
for name in ['board-terrain-original.fbx','board-terrain-editable.fbx']:
    cmds.file(new=True,force=True)
    cmds.currentUnit(linear='cm')
    cmds.file(str(out/name),i=True,type='FBX',ignoreVersion=True)
    meshes=cmds.ls(type='mesh',long=True)
    assert len(meshes)==1, meshes
    mesh=meshes[0]
    report={'file':name,'vertices':cmds.polyEvaluate(mesh,vertex=True),'faces':cmds.polyEvaluate(mesh,face=True),'shells':cmds.polyEvaluate(mesh,shell=True),'uv_sets':cmds.polyUVSet(mesh,q=True,allUVSets=True),'bounds_cm':cmds.exactWorldBoundingBox(mesh)}
    assert report['shells']==1,report
    assert len(report['uv_sets'])==2,report
    reports.append(report)
(out/'maya-validation.json').write_text(json.dumps(reports,indent=2))
print('MAYA_IMPORT_PASS')
maya.standalone.uninitialize()
