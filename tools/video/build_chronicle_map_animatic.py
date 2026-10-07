"""Single 2.5s Blender animatic for the actual opening chronicle map page."""
import bpy, math, os, random
from mathutils import Vector
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../..'))
OUT=os.path.join(ROOT,'outputs/chronicle-map-animatic-20261003')
os.makedirs(os.path.join(OUT,'frames'),exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
s=bpy.context.scene; s.render.engine='BLENDER_WORKBENCH'
s.render.resolution_x=640; s.render.resolution_y=360; s.render.resolution_percentage=100
s.render.fps=24; s.frame_start=1; s.frame_end=60
s.render.image_settings.file_format='PNG'; s.render.filepath=OUT+'/frames/frame_'
s.world.color=(.025,.04,.045); sh=s.display.shading
sh.light='STUDIO'; sh.color_type='MATERIAL'; sh.show_shadows=True
sh.show_cavity=True; sh.cavity_type='BOTH'; sh.show_object_outline=True; sh.background_type='WORLD'
s.view_settings.view_transform='Standard'
def mat(name,c):
 m=bpy.data.materials.new(name); m.diffuse_color=(*c,1); return m
paper=mat('Parchment placeholder',(.62,.43,.21)); ink=mat('Ink',(.035,.055,.054))
board=mat('Writing desk',(.075,.085,.08)); red=mat('Imperial mark',(.47,.085,.03))
gold=mat('Quill',(.86,.70,.40))
def cube(name,loc,scale,m):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object
 o.name=name; o.scale=scale; o.data.materials.append(m); return o
cube('Desk',(0,0,-.24),(14,10,.4),board)
cube('Atlas cover',(0,0,-.02),(8.6,5.5,.12),ink)
def ease(t):
 t=max(0,min(1,t)); return 1-(1-t)**3
def point(x,y,f):
 t=(f-1)/59; opening=ease(t/.30)
 # Two pages unfold with travelling elastic curl; deliberate animated deformation.
 a=(1-opening)*1.10
 px=x*math.cos(a); pz=abs(x)*math.sin(a)
 pz+=.36*math.sin(x*2.1-t*21)*math.exp(-t*6)*opening
 pz+=.075*math.cos(x*.65)+.025*math.sin(y*2+x)
 return Vector((px,y,pz+.28))
nx,ny=48,28
coords=[(-4+8*i/nx,-2.5+5*j/ny) for j in range(ny+1) for i in range(nx+1)]
verts=[point(x,y,60) for x,y in coords]
faces=[(j*(nx+1)+i,j*(nx+1)+i+1,(j+1)*(nx+1)+i+1,(j+1)*(nx+1)+i) for j in range(ny) for i in range(nx)]
mesh=bpy.data.meshes.new('Subdivided unfolding atlas'); mesh.from_pydata(verts,[],faces)
o=bpy.data.objects.new('Atlas paper - editable frame shapes',mesh); s.collection.objects.link(o); mesh.materials.append(paper)
o.shape_key_add(name='Basis')
for f in range(1,61):
 key=o.shape_key_add(name='Unfold_%02d'%f)
 for v,(x,y) in zip(key.data,coords):v.co=point(x,y,f)
 key.value=0; key.keyframe_insert('value',frame=max(0,f-1))
 key.value=1; key.keyframe_insert('value',frame=f)
 key.value=0; key.keyframe_insert('value',frame=f+1)
def line(name,xy,m,width=.018,draw=False):
 c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.bevel_depth=width; c.bevel_resolution=0
 p=c.splines.new('POLY'); p.points.add(len(xy)-1)
 ob=bpy.data.objects.new(name,c); s.collection.objects.link(ob); c.materials.append(m)
 for f in range(1,61):
  for v,(x,y) in zip(p.points,xy):
   q=point(x,y,f)+Vector((0,0,.025)); v.co=(*q,1); v.keyframe_insert('co',frame=f)
  if draw:
   c.bevel_factor_end=max(.001,min(1,(f-13)/33)); c.keyframe_insert('bevel_factor_end',frame=f)
 return ob
# Border, river and small angular relief symbols stay attached to deforming paper.
line('Map frame',[(-3.8,-2.3),(3.8,-2.3),(3.8,2.3),(-3.8,2.3),(-3.8,-2.3)],ink,.012)
line('River',[(x,math.sin(x*1.7)*.35+.9) for x in [i/10 for i in range(-35,36)]],ink,.024)
route=[(-3.3+6.2*i/50,-1+.27*math.sin(i*.19)) for i in range(51)]
line('Ink advance - animated reveal',route,red,.047,True)
random.seed(42)
for i in range(25):
 x=random.uniform(-3.5,3.5); y=random.choice([-1.8,1.7])+random.uniform(-.2,.2)
 line('Mountain glyph %02d'%i,[(x-.13,y),(x,y+.24),(x+.17,y),(x,y+.14)],ink,.018)
for x in [-2.8,-.8,1.2,2.8]:
 line('Settlement %.1f'%x,[(x-.16,-.1),(x-.16,.2),(x,.4),(x+.16,.2),(x+.16,-.1),(x-.16,-.1)],ink,.025)
# Pencil/quill is a blockout prop, not a final character/hand.
bpy.ops.mesh.primitive_cone_add(vertices=8,radius1=.065,radius2=.03,depth=1.6)
pen=bpy.context.object; pen.name='Drawing quill'; pen.data.materials.append(gold)
pen.rotation_euler=(0,-.65,-.2)
bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=1)
feather=bpy.context.object; feather.name='Quill plume'; feather.data.materials.append(gold); feather.parent=pen
feather.location=(0,0,.85); feather.scale=(.16,.04,.55)
stamp=cube('Imperial map marker',(2.9,-1,3),(.6,.6,.2),red)
bpy.ops.object.camera_add(); cam=bpy.context.object; s.camera=cam; cam.name='PV shot 01 - fast push and settle'; cam.data.lens=42
for f in range(1,61):
 t=(f-1)/59; draw=max(0,min(1,(f-13)/33)); idx=min(50,int(draw*50))
 q=point(*route[idx],f)
 pen.location=q+Vector((-.48,0,.65+max(0,(f-46)/14)*3))
 pen.keyframe_insert('location',frame=f)
 impact=ease((f-44)/7); rebound=.10*math.sin(max(0,f-51)*1.0)*math.exp(-max(0,f-51)*.35)
 stamp.location=point(2.9,-1,f)+Vector((0,0,2.8*(1-impact)+.14+rebound))
 stamp.scale=(.6*(1+.18*math.exp(-((f-51)/2)**2)),.6,.2*(1-.3*math.exp(-((f-51)/2)**2)))
 stamp.keyframe_insert('location',frame=f);stamp.keyframe_insert('scale',frame=f)
 push=ease(t/.83);cam.location=(-3.2+4.1*push,-7.9+2.5*push,8.7-2.9*push)
 target=Vector((-.7+2.3*push,0,.15))
 cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
 cam.rotation_euler.z+=.045*math.sin(t*math.pi)
 cam.keyframe_insert('location',frame=f);cam.keyframe_insert('rotation_euler',frame=f)
s.timeline_markers.new('Paper snap open',frame=1);s.timeline_markers.new('Ink advance',frame=14)
s.timeline_markers.new('Mark lands',frame=51);s.timeline_markers.new('Hard-cut endpoint',frame=60)
s.frame_set(30);bpy.ops.wm.save_as_mainfile(filepath=OUT+'/map-shot01.blend')
bpy.ops.render.render(animation=True)
