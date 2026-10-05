import bpy, json, math, pathlib, shutil
from mathutils import Vector
root=pathlib.Path.cwd()
out=root/'outputs/maya-board-mesh'
data=json.loads((out/'source-mesh.json').read_text())
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.scene.unit_settings.system='METRIC'
bpy.context.scene.unit_settings.scale_length=1.0
materials=[]
for name,tex,tint in [('Terrain','forest-floor-tile.png',(1,1,1,1)),('Board','earth-tile.png',(.60,.65,.70,1))]:
    dst=out/'textures'/tex; dst.parent.mkdir(exist_ok=True)
    shutil.copy2(root/'assets/art/forest_rebuild'/tex,dst)
    mat=bpy.data.materials.new(name); mat.use_nodes=True
    bsdf=mat.node_tree.nodes.get('Principled BSDF'); bsdf.inputs['Roughness'].default_value=.96
    image=mat.node_tree.nodes.new('ShaderNodeTexImage'); image.image=bpy.data.images.load(str(dst))
    mat.node_tree.links.new(image.outputs['Color'],bsdf.inputs['Base Color'])
    materials.append(mat)
quads=[]
for mi,s in enumerate(data['surfaces']):
    for i in range(0,len(s['vertices']),6):
        ix=[i,i+2,i+1,i+4]
        quads.append(([Vector(s['vertices'][j]) for j in ix],[Vector(s['uv'][j]) for j in ix],mi))
def build(dense):
    vertices=[]; faces=[]; face_uv=[]; mids=[]; lookup={}
    def vertex(p):
        key=tuple(round(float(v),5) for v in p)
        if key not in lookup:
            lookup[key]=len(vertices); vertices.append((p.x,-p.z,p.y))
        return lookup[key]
    def blend(v,u,w): return v[0]*(1-u)*(1-w)+v[1]*u*(1-w)+v[2]*u*w+v[3]*(1-u)*w
    for p,uv,mi in quads:
        nx=ny=1
        if dense:
            nx=max(1,math.ceil((uv[1]-uv[0]).length/2))
            length=(uv[3]-uv[0]).length
            ny=160 if length>200 else (90 if length>100 else max(1,math.ceil(length/.5)))
        grid={}
        for y in range(ny+1):
            for x in range(nx+1): grid[x,y]=vertex(blend(p,x/nx,y/ny))
        for y in range(ny):
            for x in range(nx):
                corners=[(x,y),(x,y+1),(x+1,y+1),(x+1,y)]
                faces.append([grid[k] for k in corners]); face_uv.append([blend(uv,a/nx,b/ny) for a,b in corners]); mids.append(mi)
    mesh=bpy.data.meshes.new('ContinuousBoardMesh'); mesh.from_pydata(vertices,[],faces); mesh.update()
    obj=bpy.data.objects.new('BoardTerrain_Editable' if dense else 'BoardTerrain_Original',mesh); bpy.context.collection.objects.link(obj)
    for m in materials: mesh.materials.append(m)
    primary=mesh.uv_layers.new(name='TiledMaterialUV'); raw=mesh.uv_layers.new(name='UnfoldedMetersUV')
    for poly,uv,mi in zip(mesh.polygons,face_uv,mids):
        poly.material_index=mi
        for loop,v in zip(poly.loop_indices,uv):
            raw.data[loop].uv=v; primary.data[loop].uv=(v.x/(6 if mi==1 else 4),-v.y/(6 if mi==1 else 4))
    mesh.uv_layers.active_index=0
    return obj
reports=[]
for dense in [False,True]:
    obj=build(dense)
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active=obj
    name='board-terrain-editable.fbx' if dense else 'board-terrain-original.fbx'
    bpy.ops.export_scene.fbx(filepath=str(out/name),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',use_mesh_modifiers=False,mesh_smooth_type='FACE',use_triangles=False,bake_anim=False,path_mode='RELATIVE')
    reports.append({'file':name,'vertices':len(obj.data.vertices),'quads':len(obj.data.polygons),'uv_layers':len(obj.data.uv_layers),'bounds_blender':[list(min(v.co[i] for v in obj.data.vertices) for i in range(3)),list(max(v.co[i] for v in obj.data.vertices) for i in range(3))]})
    bpy.data.objects.remove(obj,do_unlink=True)
for report in reports:
    bpy.ops.import_scene.fbx(filepath=str(out/report['file']))
    obj=bpy.context.selected_objects[0]
    assert len(obj.data.vertices)==report['vertices']
    assert len(obj.data.polygons)==report['quads']
    assert len(obj.data.uv_layers)==2
    assert all(len(p.vertices)==4 for p in obj.data.polygons)
    bounds=[[min(v.co[i] for v in obj.data.vertices) for i in range(3)],[max(v.co[i] for v in obj.data.vertices) for i in range(3)]]
    assert max(abs(a-b) for aa,bb in zip(bounds,report['bounds_blender']) for a,b in zip(aa,bb))<.001
    report['fbx_roundtrip']='PASS'
    bpy.data.objects.remove(obj,do_unlink=True)
(out/'validation.json').write_text(json.dumps(reports,indent=2))
print(json.dumps(reports))
