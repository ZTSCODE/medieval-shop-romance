"""Editable single-shot, stylized motion study. Run with Blender --background --python."""
import bpy, math, random, os
from mathutils import Vector, Quaternion

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '../..'))
OUT = os.path.join(ROOT, 'outputs/opening-blender-animatic-20261003')
os.makedirs(os.path.join(OUT, 'frames'), exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x = 640; scene.render.resolution_y = 360
scene.render.resolution_percentage = 100
scene.render.fps = 24; scene.frame_start = 1; scene.frame_end = 120
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = os.path.join(OUT, 'frames/frame_')
scene.world.color = (0.06, 0.07, 0.09)
shade = scene.display.shading
shade.light = 'STUDIO'; shade.color_type = 'MATERIAL'
shade.show_shadows = True; shade.show_cavity = True
shade.cavity_type = 'BOTH'; shade.show_object_outline = True
shade.background_type = 'WORLD'
scene.view_settings.view_transform = 'Standard'

def mat(name, color):
    m = bpy.data.materials.new(name); m.diffuse_color = (*color, 1); return m
coat = mat('Coat - charcoal', (.085,.10,.12))
skin = mat('Skin - warm clay', (.66,.43,.27))
shirt = mat('Shirt - linen', (.72,.65,.49))
boots = mat('Boots - leather', (.17,.10,.065))
earth = mat('Earth', (.16,.14,.12))
wood = mat('Blackthorn trunks', (.08,.11,.115))
fogmat = mat('Distant mist', (.32,.40,.43))
torch = mat('Pursuit embers', (.94,.30,.045))

def sphere(name, material, radius=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius)
    o=bpy.context.object; o.name=name; o.data.materials.append(material); return o
def key(o, pos, scale, frame):
    o.location=pos; o.scale=scale
    o.keyframe_insert('location', frame=frame); o.keyframe_insert('scale', frame=frame)
def segment(name, material, radius):
    o=sphere(name, material); o['radius']=radius; return o
def segpose(o,a,b,f):
    a,b=Vector(a),Vector(b); d=b-a
    key(o,(a+b)*.5,(o['radius'],o['radius'],d.length*.56),f)
    o.rotation_mode='QUATERNION'; o.rotation_quaternion=d.to_track_quat('Z','Y')
    o.keyframe_insert('rotation_quaternion',frame=f)

body=sphere('Hero torso - squash stretch',coat)
chest=sphere('Linen chest',shirt)
pelvis=sphere('Hips',coat)
head=sphere('Head',skin)
hair=sphere('Hair silhouette',coat)
nose=sphere('Face direction',skin)
limbs={}
for side in [-1,1]:
    for part,material,radius in [('thigh',coat,.115),('shin',coat,.085),('upper_arm',coat,.09),('forearm',coat,.075)]:
        limbs[(side,part)]=segment(f'{side}_{part}',material,radius)
    limbs[(side,'foot')]=sphere(f'{side}_boot',boots)
    limbs[(side,'hand')]=sphere(f'{side}_hand',skin)

# Separate editable coat-tail meshes with keyed shape deformation.
tails=[]
for side in [-1,1]:
    mesh=bpy.data.meshes.new(f'CoatTail_{side}')
    verts=[(0,side*.15,1),(-.4,side*.2,.6),(-.9,side*.26,.45),(-.85,side*.02,.4),(-.35,side*.02,.65),(0,0,1)]
    mesh.from_pydata(verts,[],[(0,1,4,5),(1,2,3,4)])
    o=bpy.data.objects.new(f'Coat tail {side} - animated cloth silhouette',mesh)
    scene.collection.objects.link(o); mesh.materials.append(coat); tails.append(o)
    o.shape_key_add(name='Basis')
    shape=o.shape_key_add(name='Whip stretch')
    for i in [1,2,3,4]:
        shape.data[i].co.x *= 1.65
        shape.data[i].co.z += .22 if i in [2,3] else .1

bpy.ops.mesh.primitive_plane_add(size=200); ground=bpy.context.object
ground.name='Forest floor'; ground.data.materials.append(earth)
random.seed(103)
for i in range(48):
    x=random.uniform(-12,25); y=random.choice([-1,1])*random.uniform(2.3,10)
    h=random.uniform(3,7); r=random.uniform(.12,.32)
    bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=r, radius2=r*.5, depth=h, location=(x,y,h*.5))
    o=bpy.context.object; o.name='Blackthorn %02d'%i; o.data.materials.append(wood)
    o.rotation_euler[1]=random.uniform(-.15,.15)
    branch=segment('Branch %02d'%i,wood,r*.5)
    segpose(branch,(x,y,h*.62),(x+random.uniform(-1.8,1.8),y-.3,h*.9),1)
for i in range(18):
    stone=sphere('Root and rock %02d'%i,wood)
    stone.location=(random.uniform(-7,20),random.choice([-1,1])*random.uniform(.7,2),.08)
    stone.scale=(random.uniform(.3,.7),.2,.12)
# A physical root defines the single jumping obstacle.
root=segment('Jump obstacle root',wood,.11)
segpose(root,(7,-1.3,.14),(7,1.3,.14),1)
for i in range(12):
    mist=sphere('Mist mass %02d'%i,fogmat)
    mist.location=(13+random.uniform(0,6),random.uniform(-2,5),random.uniform(.2,.7))
    mist.scale=(2,.8,random.uniform(.35,.8))

bpy.ops.object.camera_add(); camera=bpy.context.object; camera.name='Shot01 tracking camera'
scene.camera=camera; camera.data.lens=38
camera.data.clip_end=200
for f in range(1,121):
    t=(f-1)/24
    # 0-.65 anticipation, .65-3.5 accelerating sprint, 3.5-4.15 leap, exit.
    run=max(0,t-.65); x=run*2.7
    anticipation=max(0,1-t/.65)
    phase=run*math.tau*2.7
    jump=max(0,1-abs(t-3.55)/.40)
    jump=math.sin(jump*math.pi*.5)*.58
    bounce=abs(math.sin(phase))*.075 if run>0 else -.18*math.sin(t/.65*math.pi)
    z=1.02+bounce+jump
    lean=.22 if run>0 else .32
    stretch=1+.09*math.cos(phase*2) if run>0 else 1-.16*math.sin(t/.65*math.pi)
    key(pelvis,(x,0,z),(.19,.19,.18),f)
    key(body,(x+lean,0,z+.40*stretch),(.23/stretch,.26,.46*stretch),f)
    body.rotation_euler[1]=.38 if run>0 else .5; body.keyframe_insert('rotation_euler',frame=f)
    key(chest,(x+lean+.13,-.04,z+.45*stretch),(.13,.205,.30*stretch),f)
    key(head,(x+lean+.20,0,z+.91*stretch),(.165,.155,.21),f)
    key(hair,(x+lean+.17,.02,z+1.02*stretch),(.19,.17,.16),f)
    key(nose,(x+lean+.36,-.015,z+.92*stretch),(.07,.08,.065),f)
    for side in [-1,1]:
        p=phase+(math.pi if side<0 else 0)
        swing=math.sin(p) if run>0 else -.4
        y=side*.14
        hip=(x,y,z)
        knee=(x+swing*.42,y,z-.42+max(0,swing)*.16+jump*.25)
        ankle=(x-swing*.40,y,max(.13,z-.88+max(0,-swing)*.46)+jump*.15)
        segpose(limbs[(side,'thigh')],hip,knee,f)
        segpose(limbs[(side,'shin')],knee,ankle,f)
        key(limbs[(side,'foot')],Vector(ankle)+Vector((.10,0,-.04)),(.20,.10,.085),f)
        shoulder=(x+lean,side*.25,z+.68*stretch)
        elbow=(x+lean-swing*.35,side*.29,z+.32)
        hand=(x+lean-swing*.35+.20,side*.27,z+.54)
        segpose(limbs[(side,'upper_arm')],shoulder,elbow,f)
        segpose(limbs[(side,'forearm')],elbow,hand,f)
        key(limbs[(side,'hand')],hand,(.07,.07,.09),f)
    for i,tail in enumerate(tails):
        key(tail,(x,0,bounce+jump),(1,1,1),f)
        tail.data.shape_keys.key_blocks['Whip stretch'].value=(.5+.5*math.sin(phase-1+i*.7)) if run else 0
        tail.data.shape_keys.key_blocks['Whip stretch'].keyframe_insert('value',frame=f)
    camera.location=(x-2.6,-6.6,2.2-.35*min(run/1.2,1))
    target=Vector((x+.4,0,1.15+jump*.3))
    camera.rotation_mode='QUATERNION'
    camera.rotation_quaternion=(target-camera.location).to_track_quat('-Z','Y') @ Quaternion((0,0,1),.045*min(run,1))
    camera.keyframe_insert('location',frame=f); camera.keyframe_insert('rotation_quaternion',frame=f)
for o in scene.objects:
    if o.animation_data and o.animation_data.action:
        # Dense per-frame keys keep this preview deterministic and directly editable.
        pass
scene.timeline_markers.new('Anticipation / compression',frame=1)
scene.timeline_markers.new('Launch',frame=17)
scene.timeline_markers.new('Root leap / stretch',frame=86)
scene.timeline_markers.new('Enter mist',frame=110)
scene.frame_set(48)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'shot01.blend'))
bpy.ops.render.render(animation=True)
