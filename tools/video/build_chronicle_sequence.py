"""Editable low-resolution chronicle blocking. No generated/final character art.

Run with Blender --background --python this_file -- [shot ids].
Each camera, limb and cloth deformation is keyed explicitly for deterministic review.
"""
import bpy, math, random, os, sys, json
from mathutils import Vector
ROOT=os.path.abspath(os.path.join(os.path.dirname(__file__),'../..'))
OUT=ROOT+'/outputs/chronicle-full-animatic-20261003'
SHOTS=[('03',36,'收税：伸来的铁手','page1'),('04',48,'失守：王冠坠地','page2'),
 ('05',36,'易帜：旧旗被扯下','page2'),('06',48,'边界：队长勒令停步','page3'),
 ('07',60,'深入：队伍被雾吞没','page3'),('08',48,'迷途：又走回同一棵树','page3'),
 ('09',36,'失踪：落地的提灯','page3'),('10',60,'逃亡：跃过倒木','page4'),
 ('11',48,'追兵：骑手与猎犬','page4'),('12',36,'回望：藏住左手','page4'),
 ('13',48,'抉择：扑进雾林','page4'),('14',60,'余波：林中骤静','page4')]

def material(name,rgb):
 m=bpy.data.materials.new(name);m.diffuse_color=(*rgb,1);return m
def box(name,loc,sc,m):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=sc;o.data.materials.append(m);return o
def ball(name,loc,sc,m):
 bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=loc);o=bpy.context.object;o.name=name;o.scale=sc;o.data.materials.append(m);return o
def link(name,a,b,r,m):
 a,b=Vector(a),Vector(b);o=ball(name,(a+b)/2,(r,r,(b-a).length/2),m);o.rotation_mode='QUATERNION';o.rotation_quaternion=(b-a).to_track_quat('Z','Y');return o
def key(o,f):
 for prop in ['location','rotation_euler','scale']:o.keyframe_insert(prop,frame=f)
def aim(cam,pos,target,f):
 cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();key(cam,f)
def ease(t):return max(0,min(1,t))**2*(3-2*max(0,min(1,t)))
def mesh(name,v,faces,m):
 me=bpy.data.meshes.new(name);me.from_pydata(v,[],faces);o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);me.materials.append(m);return o
def reset():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 s=bpy.context.scene;s.compositing_node_group=None;s.render.engine='BLENDER_WORKBENCH';s.render.resolution_x=640;s.render.resolution_y=360;s.render.resolution_percentage=100;s.render.fps=24
 s.render.image_settings.file_format='PNG';s.world.color=(.034,.055,.071);s.view_settings.view_transform='Standard'
 sh=s.display.shading;sh.light='STUDIO';sh.color_type='MATERIAL';sh.show_shadows=True;sh.show_cavity=True;sh.cavity_type='BOTH';sh.show_object_outline=True;sh.background_type='WORLD'
 global iron,red,skin,coat,paper,wood,ground,leaf,mist,gold,black
 iron=material('Empire blue iron',(.09,.145,.17));red=material('Empire crimson',(.44,.045,.028));skin=material('Skin proxy',(.64,.40,.26));coat=material('Hero charcoal coat',(.075,.095,.1));paper=material('Warm linen',(.62,.57,.42));wood=material('Dead wood',(.14,.13,.105));ground=material('Earth',(.095,.135,.14));leaf=material('Forest silhouette',(.07,.14,.15));mist=material('Distant mist blue',(.29,.40,.44));gold=material('Brass',(.82,.51,.12));black=material('Hair / boots',(.02,.025,.03))
 bpy.ops.object.camera_add();cam=bpy.context.object;cam.name='SHOT camera';cam.data.lens=38;s.camera=cam
 box('Ground',(0,0,-.13),(70,70,.2),ground)
 return s,cam
def tree(x,y,size=1,pale=False):
 m=mist if pale else wood
 link('Twisted trunk',(x,y,0),(x+.3*size,y,5*size),.22*size,m)
 for side in [-1,1]:
  link('Branch',(x+.1,y,2*size),(x+side*1.4*size,y+.1,4.5*size),.12*size,m)
  if not pale:ball('Canopy',(x+side*.9*size,y,5*size),(1.3*size,.9*size,.8*size),leaf)
def forest():
 random.seed(20261003)
 for i in range(30):
  x=random.uniform(-17,17);y=random.choice([random.uniform(3,11),random.uniform(-9,-4)])
  tree(x,y,random.uniform(.7,1.4),y>7)
 for i in range(13):
  x=random.uniform(-12,12);y=random.uniform(2,6)
  ball('Distant low foliage',(x,y,.4),(1.5,.7,.5),leaf)
def actor(name,cloth=None,soldier=False):
 bpy.ops.object.empty_add();root=bpy.context.object;root.name=name
 parts={}
 for label,loc,sc,ma in [('torso',(0,0,1.3),(.3,.21,.47),cloth or coat),('hip',(0,0,.9),(.24,.18,.2),cloth or coat),('head',(0,0,1.96),(.22,.20,.28),iron if soldier else skin),('hair',(-.035,.015,2.11),(.23,.21,.17),iron if soldier else black),('nose',(.215,-.025,1.95),(.085,.065,.06),skin),('eye',(.17,-.174,2.0),(.04,.018,.025),black)]:
  o=ball(name+' '+label,loc,sc,ma);o.parent=root;parts[label]=o
 for label in ['hair','nose','eye']:
  parts[label].parent=parts['head'];parts[label].location-=parts['head'].location
  # Head scale is a mesh size, not a transform to inherit into facial features.
  parts[label].matrix_parent_inverse=parts['head'].matrix_basis.inverted()
  parts[label].location+=parts['head'].location
 for side,suf in [(-1,'L'),(1,'R')]:
  for part in ['thigh','shin','upper','fore']:
   o=ball(name+' '+part+suf,(0,0,0),(.1,.1,.4),cloth or coat);o.parent=root;parts[part+suf]=o
  for part,ma in [('hand',skin),('boot',black)]:
   o=ball(name+' '+part+suf,(0,0,0),(.1,.1,.1),ma);o.parent=root;parts[part+suf]=o
 cap=mesh(name+' deforming coat',[(-.15,-.24,1.5),(-.15,.24,1.5),(-.3,.32,.45),(-.3,-.32,.45)],[(0,1,2,3)],red if soldier else (cloth or coat));cap.parent=root
 cap.shape_key_add(name='Basis');sm=cap.shape_key_add(name='Anime trailing smear')
 for i in [2,3]:sm.data[i].co.x-=.95;sm.data[i].co.z+=.3
 parts['cape']=cap;parts['root']=root
 if soldier:
  sh=box(name+' shield',(.18,-.32,1.15),(.5,.11,.72),red);sh.parent=root
  sp=link(name+' spear',(.35,.25,.8),(.85,.25,3),.018,gold);sp.parent=root
 return parts
def bone(o,a,b,r,f):
 a,b=Vector(a),Vector(b);o.location=(a+b)/2;o.scale=(r,r,(b-a).length/2);o.rotation_mode='QUATERNION';o.rotation_quaternion=(b-a).to_track_quat('Z','Y')
 o.keyframe_insert('location',frame=f);o.keyframe_insert('scale',frame=f);o.keyframe_insert('rotation_quaternion',frame=f)
def animate_actor(p,f,t,pos=(0,0,0),run=0,rot=0,jump=0,reach=None):
 ph=t*math.tau*2.6;root=p['root'];root.location=Vector(pos)+Vector((0,0,jump+.055*abs(math.sin(ph))*run));root.rotation_euler.z=rot
 stretch=1+.08*math.sin(2*ph)*run;root.scale=(1/stretch,1,stretch);key(root,f)
 for side,suf in [(-1,'L'),(1,'R')]:
  v=math.sin(ph+(0 if side<0 else math.pi))*run;y=side*.16
  hip=(0,y,.91);knee=(.42*v,y,.5+max(0,v)*.16);ankle=(-.48*v,y,.13+max(0,-v)*.3)
  bone(p['thigh'+suf],hip,knee,.115,f);bone(p['shin'+suf],knee,ankle,.085,f)
  p['boot'+suf].location=Vector(ankle)+Vector((.06,0,0));p['boot'+suf].scale=(.18,.115,.1);key(p['boot'+suf],f)
  shoulder=(0,side*.27,1.58);elbow=(-v*.3,side*.31,1.28);hand=(.22-v*.28,side*.31,1.1+abs(v)*.24)
  if reach and suf=='L':hand=reach;elbow=((hand[0]+shoulder[0])*.5,side*.32,(hand[2]+shoulder[2])*.5-.09)
  bone(p['upper'+suf],shoulder,elbow,.09,f);bone(p['fore'+suf],elbow,hand,.075,f)
  p['hand'+suf].location=hand;p['hand'+suf].scale=(.11,.09,.11);key(p['hand'+suf],f)
 sm=p['cape'].data.shape_keys.key_blocks[1];sm.value=(.5+.5*math.sin(ph-.5))*run;sm.keyframe_insert('value',frame=f)
def lantern(loc):
 bpy.ops.object.empty_add(location=loc);r=bpy.context.object;r.name='Lantern assembly'
 for n,p,sc,ma in [('base',(0,0,0),(.3,.3,.07),iron),('light',(0,0,.23),(.15,.15,.4),gold),('roof',(0,0,.5),(.32,.32,.09),iron)]:
  o=box(n,p,sc,ma);o.parent=r
 for x in [-.14,.14]:
  for y in [-.14,.14]:o=box('Cage',(x,y,.25),(.026,.026,.5),iron);o.parent=r
 return r

def build(sid,n):
 s,c=reset();s.frame_start=1;s.frame_end=n
 people=[];objects={}
 if sid=='03':
  box('Tax table',(0,0,.8),(2.7,1,.15),wood);people=[actor('Villager',paper),actor('Imperial collector',iron,True)]
  objects['bag']=ball('Last tax purse',(-.3,-.1,1.03),(.24,.2,.26),paper)
  for i in range(4):ball('Coin',(.15+i*.15,-.12,.92),(.065,.065,.015),gold)
 elif sid=='04':
  box('Throne seat',(-.4,.7,.5),(1.2,1.1,1),wood);box('Throne back',(-.4,1.15,1.5),(1.25,.2,2.5),wood)
  people=[actor('Deposed ruler',paper),actor('Invading guard',iron,True)]
  bpy.ops.mesh.primitive_torus_add(major_radius=.24,minor_radius=.045,location=(0,0,2));objects['crown']=bpy.context.object;objects['crown'].data.materials.append(gold)
  for i in range(5):
   a=i*math.tau/5;o=box('Crown point',(.24*math.cos(a),.24*math.sin(a),.09),(.06,.06,.18),gold);o.parent=objects['crown']
 elif sid=='05':
  box('Fort wall',(0,1,2),(10,.4,5),wood);link('Flagpole',(0,0,.1),(0,0,4.5),.06,iron)
  objects['old']=mesh('Old blue banner',[(0,0,4),(-1.7,0,3.8),(-1.6,0,2.2),(0,0,2.4)],[(0,1,2,3)],mist)
  objects['new']=mesh('New imperial banner',[(0,-.05,4),(1.8,-.05,3.9),(1.7,-.05,2.1),(0,-.05,2.4)],[(0,1,2,3)],red)
  people=[actor('Flag bearer',iron,True)]
 else:
  forest()
  if sid in ['06','07','08']:people=[actor('Expedition '+str(i),iron,True) for i in range(3)]
  if sid=='09':objects['lantern']=lantern((0,0,.04))
  if sid in ['10','12','13','14']:people=[actor('Fugitive',coat)]
  if sid=='10':link('Fallen trunk',(.2,-1,.35),(.2,2,.35),.27,wood)
  if sid in ['06','08']:
   tree(1,1,1.2);box('Same tree slash',(1,.74,1.4),(.32,.03,.08),red)
  if sid=='11':
   objects['horses']=[];objects['dogs']=[]
   for i in range(3):
    bpy.ops.object.empty_add();r=bpy.context.object;r.name='Pursuit horse '+str(i);parts=[]
    for name,loc,sc in [('body',(0,0,1),(.75,.25,.35)),('neck',(.6,0,1.4),(.22,.2,.48)),('head',(.85,0,1.8),(.35,.18,.20))]:
     o=ball(name,loc,sc,wood);o.parent=r
    for k in range(4):o=ball('Galloping leg',(0,0,0),(.07,.07,.5),black);o.parent=r;parts.append(o)
    rider=actor('Mounted imperial '+str(i),iron,True);rider['root'].scale=(.8,.8,.8)
    objects['horses'].append((r,parts,rider))
   for i in range(2):
    bpy.ops.object.empty_add();r=bpy.context.object;r.name='Hound '+str(i)
    for name,loc,sc in [('body',(0,0,.45),(.5,.15,.2)),('head',(.43,0,.6),(.22,.14,.16))]:o=ball(name,loc,sc,black);o.parent=r
    legs=[]
    for k in range(4):o=ball('Hound leg',(0,0,0),(.04,.04,.23),black);o.parent=r;legs.append(o)
    objects['dogs'].append((r,legs))
 for f in range(1,n+1):
  u=(f-1)/(n-1);t=(f-1)/24
  if sid=='03':
   q=ease((u-.2)/.45);animate_actor(people[0],f,t,(-1.15,.1,0),rot=0,reach=(.8,-.1,1))
   animate_actor(people[1],f,t,(1.3,.15,0),rot=math.pi,reach=(1.6-1.35*q,.25,1.05+.14*math.sin(q*math.pi)))
   objects['bag'].location=(-.3+1.35*q,-.1,1.04+.14*math.sin(q*math.pi));key(objects['bag'],f)
   aim(c,(.1,-3.7+u*.7,2.8),(.1,0,1.1),f)
  elif sid=='04':
   q=ease((u-.25)/.6);animate_actor(people[0],f,t,(-.5-q*.8,-.5,0),rot=.1)
   people[0]['root'].rotation_euler.y=-q*.55;key(people[0]['root'],f)
   animate_actor(people[1],f,t,(2.5-1.4*ease(u),.2,0),run=.4,rot=math.pi,reach=(.8,-.15,1.5))
   cr=objects['crown'];cr.location=(-.4+1.1*q,-.3,2.03*(1-q)+.1+.18*abs(math.sin(q*math.pi*3)));cr.rotation_euler=(q*1.5,q*2,0);key(cr,f)
   aim(c,(2.8,-5.1,1.1-.5*q),(.0,0,1.1-.5*q),f)
  elif sid=='05':
   q=ease(u/.7);objects['old'].location=(0,0,-3.8*q);objects['old'].rotation_euler.y=.25*q;key(objects['old'],f)
   objects['new'].scale=(max(.03,ease((u-.15)/.6)),1,1);key(objects['new'],f)
   animate_actor(people[0],f,t,(-.15,-.3,0),reach=(.2,-.15,2.1-1.2*q))
   aim(c,(2,-5,2.7+u*.7),(.0,0,2.4+u*.5),f)
  elif sid=='06':
   for i,p in enumerate(people):animate_actor(p,f,t,(-1.4-i*1.2+1.2*ease(u/.6),i*.5,0),run=max(0,1-u*1.7),reach=(.3,-.65,1.8) if i==0 else None)
   aim(c,(3.5,-4,1.4),(-.5,1,1.7+u*.8),f)
  elif sid=='07':
   for i,p in enumerate(people):animate_actor(p,f,t,(-1.8+i*.9,1+u*10-i*.8,0),run=.45,rot=math.pi/2)
   aim(c,(.0,-4+u,1.5),(0,4+u*3,1.5),f)
  elif sid=='08':
   for i,p in enumerate(people):animate_actor(p,f,t,(-3+2.1*ease(u/.7)-i*.85,-i*.4,0),run=max(0,.7-u),rot=0,reach=(.8,0,1.4) if i==0 else None)
   aim(c,(1,-5.3,2.3),(-.1,0,1.3),f)
  elif sid=='09':
   l=objects['lantern'];q=ease(u/.5);l.location=(.1+.6*q,0,.05+2.0*(1-q));l.rotation_euler=(0,1.4*q+.14*math.sin(t*18)*max(0,1-u*1.5),.2);key(l,f)
   aim(c,(1.8,-3.0,1.2),(.5,0,.45),f)
  elif sid=='10':
   jump=1.15*math.sin(math.pi*max(0,min(1,(u-.18)/.62)))
   animate_actor(people[0],f,t,(-2.7+5.4*u,0,0),run=1,jump=jump)
   aim(c,(-1.2+u*4.5,-4.7,.85),(-2+u*5.4,0,1.1+jump*.4),f)
  elif sid=='11':
   for i,(r,legs,rider) in enumerate(objects['horses']):
    x=-3+u*5-i*1.4;y=1+i*.8;r.location=(x,y,.1*abs(math.sin(t*15)));key(r,f)
    for k,o in enumerate(legs):
     side=-1 if k%2 else 1;phase=t*15+k*1.4;o.location=(.48*(1 if k<2 else -1)+.16*math.sin(phase),side*.2,.5);o.rotation_euler.y=.6*math.sin(phase);key(o,f)
    animate_actor(rider,f,t,(x-.2,y,.64),run=.1)
    rider['root'].scale=(.75,.75,.75);key(rider['root'],f)
    for side,suf in [(-1,'L'),(1,'R')]:
     hip=(0,side*.16,.91);knee=(.37,side*.36,.66);foot=(.28,side*.42,.18)
     bone(rider['thigh'+suf],hip,knee,.115,f);bone(rider['shin'+suf],knee,foot,.085,f)
     rider['boot'+suf].location=foot;key(rider['boot'+suf],f)
   for i,(r,legs) in enumerate(objects['dogs']):
    r.location=(-1+u*5-i*1.6,-1-i*.6,.12*abs(math.sin(t*20)));r.scale=(1+.17*math.sin(t*20),1,1-.12*math.sin(t*20));key(r,f)
    for k,o in enumerate(legs):o.location=(.28*(1 if k<2 else -1),.12*(-1 if k%2 else 1),.24);o.rotation_euler.y=.8*math.sin(t*20+k*1.5);key(o,f)
   aim(c,(-.6+u*4.5,-6,.8),(u*4-1,1,1.1),f)
  elif sid=='12':
   p=people[0];animate_actor(p,f,t,run=.35,reach=(.04,-.22,1.4))
   p['head'].rotation_euler.z=-1.5*math.sin(u*math.pi);key(p['head'],f)
   aim(c,(1.8,-2.4,2.2),(0,0,1.65),f);c.data.lens=62
  elif sid=='13':
   animate_actor(people[0],f,t,(-2.7+5.3*u,u*1.4,0),run=1,jump=.18*math.sin(math.pi*u))
   aim(c,(1,-5.8,1.0),(0+u*2,1,1.2),f)
  elif sid=='14':
   animate_actor(people[0],f,t,(-1.5+1.3*ease(u/.7),0,0),run=max(0,.8-u*1.2),reach=(.0,-.2,1.3))
   aim(c,(4,-7,3.2+u*.3),(.0,0,1.1),f)
 # Fog sheets are explicitly a compositing proxy: flat pale forest layers, not rocks.
 if sid in ['07','13']:
  nt=bpy.data.node_groups.new('Fog composite '+sid,'CompositorNodeTree');s.compositing_node_group=nt
  nt.interface.new_socket(name='Image',in_out='OUTPUT',socket_type='NodeSocketColor')
  rl=nt.nodes.new('CompositorNodeRLayers');mix=nt.nodes.new('ShaderNodeMix');mix.data_type='RGBA';mix.blend_type='MIX';mix.inputs[7].default_value=(.20,.30,.34,1)
  nt.links.new(rl.outputs['Image'],mix.inputs[6]);out=nt.nodes.new('NodeGroupOutput');nt.links.new(mix.outputs[2],out.inputs['Image'])
  for frame,val in [(1,0),(int(n*.45),.12),(n,.92)]:mix.inputs[0].default_value=val;mix.inputs[0].keyframe_insert('default_value',frame=frame)
 folder=OUT+'/shot'+sid;os.makedirs(folder+'/frames',exist_ok=True);s.render.filepath=folder+'/frames/frame_'
 s.timeline_markers.new('Action begins',frame=1);s.timeline_markers.new('Action accent',frame=max(2,n//2));s.timeline_markers.new('HARD CUT',frame=n)
 s.frame_set(n//2);bpy.ops.wm.save_as_mainfile(filepath=folder+'/shot'+sid+'.blend');bpy.ops.render.render(animation=True)

if __name__=='__main__':
 wanted=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
 os.makedirs(OUT,exist_ok=True)
 with open(OUT+'/shots.json','w',encoding='utf-8') as f:json.dump([dict(id=a,frames=b,title=c,page=d) for a,b,c,d in SHOTS],f,ensure_ascii=False,indent=2)
 for sid,n,_,_ in SHOTS:
  if not wanted or sid in wanted:build(sid,n)
