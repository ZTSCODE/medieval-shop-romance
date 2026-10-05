"""Shot 02: actual occupation action, 2 seconds, deformable Blender blockout."""
import bpy, math, os
from mathutils import Vector
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../..'))
OUT=ROOT+'/outputs/chronicle-soldiers-animatic-20261003'
os.makedirs(OUT+'/frames',exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
s=bpy.context.scene;s.render.engine='BLENDER_WORKBENCH'
s.render.resolution_x=640;s.render.resolution_y=360;s.render.resolution_percentage=100
s.render.fps=24;s.frame_start=1;s.frame_end=48;s.render.image_settings.file_format='PNG'
s.render.filepath=OUT+'/frames/frame_';s.world.color=(.035,.05,.055)
sh=s.display.shading;sh.light='STUDIO';sh.color_type='MATERIAL';sh.show_shadows=True
sh.show_cavity=True;sh.cavity_type='BOTH';sh.show_object_outline=True;sh.background_type='WORLD'
s.view_settings.view_transform='Standard'
def mat(name,c):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);return m
iron=mat('Imperial iron',(.10,.14,.155));trim=mat('Worn brass',(.61,.40,.15))
cloth=mat('Imperial crimson',(.37,.07,.045));dark=mat('Visor',(.012,.017,.02))
stone=mat('Village gate',(.23,.26,.235));groundmat=mat('Road',(.14,.135,.115))
def box(name,loc,scale,m):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=scale;o.data.materials.append(m);return o
def ball(name,m):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2);o=bpy.context.object;o.name=name;o.data.materials.append(m);return o
def pose(o,loc,scale,f):
 o.location=loc;o.scale=scale;o.keyframe_insert('location',frame=f);o.keyframe_insert('scale',frame=f)
def limb(o,a,b,r,f):
 a,b=Vector(a),Vector(b);d=b-a;pose(o,(a+b)/2,(r,r,d.length*.56),f)
 o.rotation_mode='QUATERNION';o.rotation_quaternion=d.to_track_quat('Z','Y');o.keyframe_insert('rotation_quaternion',frame=f)
box('Road',(0,0,-.18),(40,24,.3),groundmat)
for y in [-3,3]:
 box('Gate pillar',(-4,y,2),(1.4,1.4,4),stone)
 for z in [.5,1.5,2.5,3.5]:box('Stone courses',(-3.26,y,z),(.035,1.42,.045),dark)
box('Gate lintel',(-4,0,4.1),(1.4,7.4,.8),stone)
for y in [-6,6]:box('Town wall',(-4,y,1.7),(1,5,3.4),stone)
for i in range(8):
 box('Paving',(-3+i*1.4,0,-.02),(1.15,2.2,.045),stone)
# Empty spear/helmet silhouette is deliberately a motion proxy, not final art.
soldiers=[]
for n in range(4):
 parts={k:ball(f'Soldier {n} {k}',m) for k,m in [('body',iron),('head',iron),('hip',iron),('visor',dark),('bootL',dark),('bootR',dark),('thighL',iron),('thighR',iron),('shinL',iron),('shinR',iron),('armL',iron),('armR',iron)]}
 parts['shield']=box(f'Soldier {n} shield',(0,0,0),(.13,.62,.9),cloth)
 parts['boss']=ball(f'Soldier {n} shield boss',trim)
 parts['spear']=ball(f'Soldier {n} spear',trim)
 verts=[(0,-.23,1.7),(0,.23,1.7),(-.5,.35,1),(-1,.32,.6),(-1,-.32,.6),(-.5,-.35,1)]
 me=bpy.data.meshes.new('Cape');me.from_pydata(verts,[],[(0,1,2,5),(5,2,3,4)])
 cape=bpy.data.objects.new(f'Soldier {n} cape',me);s.collection.objects.link(cape);me.materials.append(cloth)
 cape.shape_key_add(name='Basis');whip=cape.shape_key_add(name='Whip / smear')
 for i in [2,3,4,5]:whip.data[i].co.x*=1.8;whip.data[i].co.z+=.32
 parts['cape']=cape;soldiers.append(parts)
bpy.ops.object.camera_add();cam=bpy.context.object;cam.name='Low occupation reveal camera';s.camera=cam;cam.data.lens=30
for f in range(1,49):
 t=(f-1)/24
 for n,p in enumerate(soldiers):
  x=-3.4+5.1*t-n*1.6;y=-.55 if n==0 else .8+(n%2)*.75
  ph=t*math.tau*2.5+n*.9;bounce=.09*abs(math.sin(ph))
  z=1.0+bounce; stretch=1+.13*math.sin(ph*2)
  pose(p['hip'],(x,y,z),(.22,.22,.19),f)
  pose(p['body'],(x+.20,y,z+.40),(.26/stretch,.29,.43*stretch),f)
  p['body'].rotation_euler[1]=.35;p['body'].keyframe_insert('rotation_euler',frame=f)
  pose(p['head'],(x+.4,y,z+.86),(.22,.21,.245),f)
  pose(p['visor'],(x+.57,y-.07,z+.85),(.075,.17,.055),f)
  for side,suffix in [(-1,'L'),(1,'R')]:
   swing=math.sin(ph+(0 if side<0 else math.pi));yy=y+side*.17
   knee=(x+swing*.43,yy,z-.42+max(0,swing)*.15)
   ankle=(x-swing*.45,yy,.14+max(0,-swing)*.38)
   limb(p['thigh'+suffix],(x,yy,z),knee,.12,f);limb(p['shin'+suffix],knee,ankle,.09,f)
   pose(p['boot'+suffix],Vector(ankle)+Vector((.10,0,-.04)),(.22,.12,.09),f)
   limb(p['arm'+suffix],(x+.12,y+side*.3,z+.62),(x+.5,y+side*.37,z+.28),.1,f)
  pose(p['shield'],(x+.47,y-.43,z+.27),(.55,.12,.84),f)
  pose(p['boss'],(x+.48,y-.51,z+.29),(.15,.045,.15),f)
  limb(p['spear'],(x+.35,y+.33,z+.12),(x+1.85,y+.33,z+1.15),.023,f)
  pose(p['cape'],(x,y,bounce),(1,1,1),f)
  v=p['cape'].data.shape_keys.key_blocks['Whip / smear'];v.value=.5+.5*math.sin(ph-1);v.keyframe_insert('value',frame=f)
 # Fast low pull-back reveals depth; tiny single impact kick, not constant shake.
 progress=min(1,t/.7);progress=1-(1-progress)**3
 cam.location=(1.5,-4.4-1.7*progress,.78+.45*progress)
 target=Vector((-1.1+.35*t,.45,1.12))
 cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
 cam.rotation_euler.z+=.065*math.exp(-((f-17)/2.5)**2)
 cam.keyframe_insert('location',frame=f);cam.keyframe_insert('rotation_euler',frame=f)
s.timeline_markers.new('Foreground charge',frame=1);s.timeline_markers.new('Impact / reveal',frame=17)
s.timeline_markers.new('Column occupies gate',frame=40);s.timeline_markers.new('Hard cut',frame=48)
s.frame_set(20);bpy.ops.wm.save_as_mainfile(filepath=OUT+'/soldiers-shot02.blend');bpy.ops.render.render(animation=True)
