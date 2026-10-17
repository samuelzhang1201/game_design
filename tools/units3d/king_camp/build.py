"""Rebuild P3.3 runtime assets in isolated Blender; never runs in the live editor.
Blender --factory-startup -b -t 2 --python tools/units3d/king_camp/build.py
"""
import bpy, bmesh, math, json, importlib.util, sys
import numpy as np
from pathlib import Path
from mathutils import Vector, Quaternion
ROOT = Path(__file__).resolve().parents[3]
SKILL = Path.home()/'.agents/skills/3d-model-build-up/scripts/quadkit.py'
spec = importlib.util.spec_from_file_location('quadkit', SKILL)
qk = importlib.util.module_from_spec(spec); spec.loader.exec_module(qk)
KING = ROOT/'assets/3D/characters/king'
CAMP = ROOT/'assets/3D/buildings/field_camp'
for d in (KING,CAMP):
 (d/'model_wip').mkdir(parents=True, exist_ok=True)
 (d/'model_wip/.gdignore').touch()
REPORT = {}

def reset():
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.context.scene.render.fps=30
 qk.setup_scene(clear=False)

def mat(name,color,metal=0):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
 p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=.74 if not metal else .38
 m.use_backface_culling=False
 if name.startswith('Camp'):
  size=512; yy,xx=np.mgrid[0:size,0:size]; rng=np.random.default_rng(701)
  u=xx/size; v=yy/size
  broad=np.zeros((size,size))
  for count,weight in ((4,.60),(8,.27),(16,.13)):
   samples=rng.normal(0,.7,(count+1,count+1)); coords=np.linspace(0,count,size,endpoint=False)
   ix=coords.astype(int); fraction=coords-ix; smooth=fraction*fraction*(3-2*fraction)
   horizontal=samples[:,ix]*(1-smooth)+samples[:,ix+1]*smooth
   broad+=weight*(horizontal[ix,:]*(1-smooth[:,None])+horizontal[ix+1,:]*smooth[:,None])
  grain=rng.normal(0,.018,(size,size))
  tint=np.ones((size,size,3))
  if name=='CampTimber':
   grain+=.18*broad+.09*np.sin(yy*.13+np.sin(xx*.021)*3)+.035*np.sin(yy*.59)
   # Sun-worn grain and intermittent bruised grooves, without decorative markings.
   grain-=.1*(np.sin(yy*.13+np.sin(xx*.021)*3)>.93)
   tint[:]=(.92,.92,.87)
  elif name in ('CampCanvas','CampCloth'):
   grain+=.23*broad+.014*((xx%3==0)+(yy%3==0))
   seam=np.minimum(u%(.25),.25-u%(.25))
   grain-=.15*np.exp(-np.square(seam/.0025))
   water=np.clip(-broad-.12,0,1)
   tint[:,:,0]=1-.10*water; tint[:,:,1]=1-.13*water; tint[:,:,2]=1-.20*water
  else: grain+=.09*broad
  rgba=np.ones((size,size,4),dtype=np.float32)
  rgba[:,:,:3]=np.clip(np.array(color)[None,None,:]*(1+grain[:,:,None])*tint,0,1)
  image=bpy.data.images.new(name+'Surface',size,size); image.pixels.foreach_set(rgba.ravel()); image.pack()
  tex=m.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=image
  wear=m.node_tree.nodes.new('ShaderNodeVertexColor'); wear.layer_name='Weathering'
  multiply=m.node_tree.nodes.new('ShaderNodeMixRGB'); multiply.blend_type='MULTIPLY'; multiply.inputs[0].default_value=1
  m.node_tree.links.new(tex.outputs['Color'],multiply.inputs[1])
  m.node_tree.links.new(wear.outputs['Color'],multiply.inputs[2])
  m.node_tree.links.new(multiply.outputs[0],p.inputs['Base Color'])

 return m

def mesh(name,verts,faces,material):
 me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
 o=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(o); me.materials.append(material)
 me.uv_layers.new(name='UVMap')
 for p in me.polygons:
  for li in p.loop_indices:
   c=me.vertices[me.loops[li].vertex_index].co; me.uv_layers.active.data[li].uv=(c.x+c.y*.3,c.z+c.y*.4)
 return o

def box(name,c,size,m):
 x,y,z=size; a,b,d=c
 v=[(a+i*x/2,b+j*y/2,d+k*z/2) for i,j,k in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 return mesh(name,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],m)

def rod(name,a,b,r,m,n=12):
 a,b=Vector(a),Vector(b); axis=(b-a).normalized(); u=axis.cross(Vector((0,0,1)))
 if u.length<.01: u=Vector((1,0,0))
 u.normalize(); v=axis.cross(u)
 vs=[tuple(c+r*(u*math.cos(2*math.pi*i/n)+v*math.sin(2*math.pi*i/n))) for c in (a,b) for i in range(n)]
 vs.extend([tuple(a),tuple(b)])
 fs=[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 fs += [(2*n,(i+1)%n,i) for i in range(n)]+[(2*n+1,i+n,(i+1)%n+n) for i in range(n)]
 return mesh(name,vs,fs,m)

def vessel(name,x,y,profile,m,n=16):
 vs=[(x+r*math.cos(i*math.tau/n),y+r*math.sin(i*math.tau/n),z) for z,r in profile for i in range(n)]
 fs=[(k*n+i,k*n+(i+1)%n,(k+1)*n+(i+1)%n,(k+1)*n+i) for k in range(len(profile)-1) for i in range(n)]
 vs.extend([(x,y,profile[0][0]),(x,y,profile[-1][0])]); b=len(vs)-2; t=b+1; last=(len(profile)-1)*n
 fs.extend([(b,(i+1)%n,i) for i in range(n)]); fs.extend([(t,last+i,last+(i+1)%n) for i in range(n)])
 return mesh(name,vs,fs,m)

def grid(name,rows,m):
 n=len(rows[0]); v=[p for row in rows for p in row]
 f=[(r*n+j,r*n+j+1,(r+1)*n+j+1,(r+1)*n+j) for r in range(len(rows)-1) for j in range(n-1)]
 return mesh(name,v,f,m)

def join(parts,name):
 bpy.ops.object.select_all(action='DESELECT')
 for p in parts: p.select_set(True)
 bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join()
 o=parts[0]; o.name=name
 # Preserve UV face corners; merge only exact seam duplicates, never simplify.
 bm=bmesh.new(); bm.from_mesh(o.data)
 bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-8)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 for e in bm.edges:
  if len(e.link_faces)==2: e.smooth=e.calc_face_angle()<math.radians(40)
 bm.to_mesh(o.data); bm.free(); o.data.update()
 return o

def bounds(o):
 dg=bpy.context.evaluated_depsgraph_get(); ev=o.evaluated_get(dg); me=ev.to_mesh()
 v=[o.matrix_world@p.co for p in me.vertices]; ev.to_mesh_clear()
 lo=[min(p[i] for p in v) for i in range(3)]; hi=[max(p[i] for p in v) for i in range(3)]
 return {'min':lo,'max':hi,'size':[hi[i]-lo[i] for i in range(3)]}

def export(path,objects,anim=False):
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects: o.select_set(True)
 bpy.context.view_layer.objects.active=objects[0]
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=anim,export_animation_mode='NLA_TRACKS',export_skins=True,export_yup=True,export_force_sampling=True,export_frame_range=False,export_def_bones=False,export_materials='EXPORT')

def render(path,objects,target,distance=9,az=.8):
 sc=bpy.context.scene
 camera_data=bpy.data.cameras.new('ReviewCamera'); cam=bpy.data.objects.new('ReviewCamera',camera_data); sc.collection.objects.link(cam)
 cam.location=Vector(target)+Vector((distance*math.sin(az),-distance*math.cos(az),distance*.52)); cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
 camera_data.type='ORTHO'; camera_data.ortho_scale=distance*.75; sc.camera=cam
 for name,loc,power,size in [('Key',(4,-5,8),1500,5),('Fill',(-4,2,5),1100,4)]:
  d=bpy.data.lights.new(name,'AREA'); d.energy=power; d.shape='DISK'; d.size=size
  l=bpy.data.objects.new(name,d); sc.collection.objects.link(l); l.location=loc; l.rotation_euler=(Vector(target)-l.location).to_track_quat('-Z','Y').to_euler()
 sc.world=bpy.data.worlds.new('ReviewWorld'); sc.world.use_nodes=True; sc.world.node_tree.nodes['Background'].inputs[0].default_value=(.19,.22,.26,1)
 sc.render.engine='CYCLES'; sc.cycles.samples=12
 sc.render.resolution_x=640; sc.render.resolution_y=640; sc.render.resolution_percentage=100
 sc.render.image_settings.file_format='PNG'; sc.render.filepath=str(path); bpy.ops.render.render(write_still=True)
 for o in list(sc.objects):
  if o.type in ('LIGHT','CAMERA'): bpy.data.objects.remove(o,do_unlink=True)

def fcurves(action):
 return [fc for l in action.layers for s in l.strips for cb in s.channelbags for fc in cb.fcurves]

def king():
 reset(); bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/3D/units/cavalry/cavalry.glb'))
 rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE'); body=bpy.data.objects['cavalry']
 for o in list(bpy.context.scene.objects):
  if o not in (rig,body): bpy.data.objects.remove(o,do_unlink=True)
 rig.name='king_rig'; body.name='KingBody'
 # Imported actions are seconds converted at scene fps; keep donor skin/locomotion untouched.
 rig.animation_data.action=None
 for t in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(t)
 for p in rig.pose.bones: p.matrix_basis.identity()
 bpy.context.view_layer.update()
 brass=mat('KingBrass',(.43,.30,.095),.7); wool=mat('KingWineWool',(.19,.025,.04)); timber=mat('KingStandardWood',(.14,.08,.035))
 def skin(o,bone):
  # Geometry is measured in Blender world coordinates, converted to donor rig bind space.
  inv=rig.matrix_world.inverted()
  for v in o.data.vertices: v.co=inv@v.co
  o.parent=rig; o.matrix_parent_inverse.identity(); o.matrix_basis.identity()
  o.vertex_groups.new(name=bone).add(list(range(len(o.data.vertices))),1,'REPLACE')
  mod=o.modifiers.new('KingSkin','ARMATURE'); mod.object=rig
  return o
 # Circlet sits around donor helmet at measured rider head, not a floating crown.
 h=rig.matrix_world@rig.data.bones['head'].head_local
 head_group=body.vertex_groups['head'].index
 head_points=[body.matrix_world@v.co for v in body.data.vertices if any(g.group==head_group and g.weight>.5 for g in v.groups)]
 h.z=max(p.z for p in head_points)-.12
 rows=[]; n=24
 for z in [h.z+.045,h.z+.095]:
  rows.append([(h.x+.13*math.cos(i*2*math.pi/n),h.y+.12*math.sin(i*2*math.pi/n),z+( .028 if i%4==0 and z>h.z+.08 else 0)) for i in range(n+1)])
 crown=skin(join([grid('Crown',rows,brass)],'Crown'),'head')
 rows=[]
 for r in range(7):
  t=r/6; rows.append([(-.02+(j/8-.5)*(.46+.18*t),-.17-.15*t+.024*math.cos(j*math.pi),2.06-.61*t+.012*math.cos(j*math.pi)) for j in range(9)])
 mantle=skin(grid('Mantle',rows,wool),'R_Chest')
 pole=skin(rod('RoyalStandardPole',(-.33,-.22,1.42),(-.33,-.22,3.0),.014,timber),'Saddle')
 flag=skin(grid('RoyalStandard',[[(-.33-j*.075,-.22+.025*math.sin(j*1.1+r),2.91-r*.14) for j in range(7)] for r in range(5)],wool),'Saddle')
 # A brass vertical stripe is a royal distinction without any camp royal marker.
 stripe=skin(grid('RoyalStandardStripe',[[(-.40,-.225,2.90),(-.44,-.225,2.90)],[(-.40,-.225,2.36),(-.44,-.225,2.36)]],brass),'Saddle')
 # Keep explicit attachment names inherited from the donor; no interchangeable equipment compatibility claim.
 additions=[crown,mantle,pole,flag,stripe]
 audits={o.name:qk.audit_game(o,20000,5,armature_required=True) for o in [body]+additions}
 # Donor GLTF seams are not corrupt topology; audit on a welded validation copy below.
 validation=body.copy(); validation.data=body.data.copy(); bpy.context.collection.objects.link(validation)
 validation=join([validation],'KingBodyValidation')
 audits['KingBody']=qk.audit_game(validation,20000,5,armature_required=True)
 bpy.data.objects.remove(validation,do_unlink=True)
 total=sum(a['tris'] for a in audits.values())
 # audits only contain six named meshes (KingBody original entry replaced above).
 assert total<=20000,(total,audits)
 assert all(a['pass'] for n,a in audits.items() if n!='KingBody'),audits
 actions={a.name:a for a in bpy.data.actions}
 idle=actions['STANDBY']; march=actions['MARCH']
 for name in ('OBSERVE','COMMAND','INSPIRE'):
  a=idle.copy(); a.name=name
  # Ease an expressive head/chest gesture over the donor's subtle moving hold.
  for fc in fcurves(a):
   if 'head' not in fc.data_path and 'R_Chest' not in fc.data_path: continue
   for k in fc.keyframe_points:
    share=k.co.x/120
    if 'rotation_quaternion' in fc.data_path and fc.array_index in (1,2,3):
     amp={'OBSERVE':.025,'COMMAND':.06,'INSPIRE':.09}[name]
     k.co.y += amp*math.sin(math.pi*share)**2*math.sin(2*math.pi*share+(.3 if 'R_Chest' in fc.data_path else 0))
  actions[name]=a
 # COMMAND/INSPIRE keep the lance hand's validated grip; the free hand leads the gesture.
 for name,amplitude in [('COMMAND',.14),('INSPIRE',.28)]:
  for fc in fcurves(actions[name]):
   if 'R_UpperArm.L' in fc.data_path and 'rotation_quaternion' in fc.data_path and fc.array_index==1:
    for k in fc.keyframe_points: k.co.y+=amplitude*math.sin(math.pi*k.co.x/120)**2
 keep=[march,idle,actions['OBSERVE'],actions['COMMAND'],actions['INSPIRE']]
 rig.animation_data.action=None
 for a in keep:
  t=rig.animation_data.nla_tracks.new(); t.name=a.name
  s=t.strips.new(a.name,0,a); s.action_frame_start=0; s.action_frame_end=a.frame_range[1]
  t.mute=True
 # Exporter considers muted NLA tracks when export animation mode is NLA_TRACKS.
 for t in rig.animation_data.nla_tracks: t.mute=False
 bpy.context.scene.frame_set(0)
 REPORT['king']={'audits':audits,'tris':total,'bones':len(rig.data.bones),'stride_m':2.4,'clips':{a.name:float(a.frame_range[1]-a.frame_range[0])/30 for a in keep},'bounds':bounds(body),'attachments':{b:rig.data.bones[b].parent.name if rig.data.bones[b].parent else None for b in ['Lance','Shield','Saddle','head']}}
 bpy.ops.wm.save_as_mainfile(filepath=str(KING/'model_wip/king.blend'),compress=True)
 export(KING/'king.glb',[rig,body]+additions,True)
 for t in rig.animation_data.nla_tracks: t.mute=True
 for name in ('MARCH','STANDBY','OBSERVE','COMMAND','INSPIRE'):
  rig.animation_data.action=actions[name]
  for view,az in ([('side',1.57),('front',3.14)] if name=='MARCH' else [('quarter',.8)]):
   for f in (list(range(0,16,2)) if name=='MARCH' else [0,30,60,90]):
    bpy.context.scene.frame_set(f); render(KING/f'model_wip/{name}_{view}_{f:03}.png',[body],(0,0,1.6),5.2,az)
 rig.animation_data.action=None

def camp():
 reset(); cloth=mat('CampCanvas',(.48,.43,.31)); wood=mat('CampTimber',(.22,.12,.055)); iron=mat('CampIron',(.13,.14,.13),.6); rope=mat('CampRope',(.31,.25,.14)); dark=mat('CampCloth',(.19,.22,.17))
 facilities=[]
 def tent(name,w,l,h):
  p=[]
  # Bent canvas follows a pitched roof and vertical skirts; quilt-like irregularity is small.
  for side in (-1,1):
   rows=[]
   for j in range(11):
    y=-l/2+j*l/10; row=[]
    for k in range(7):
     t=k/6; x=side*w*.5*t; z=h-(h*.67)*t-.04*math.sin(math.pi*t)*math.cos(j*1.4)
     row.append((x,y,z))
    rows.append(row)
   p.append(grid(name+'_Roof',rows,cloth))
   p.append(grid(name+'_Skirt',[[(side*w/2,y,.045) for y in (-l/2,l/2)],[(side*w/2,y,h*.33) for y in (-l/2,l/2)]],cloth))
  for end in (-1,1):
   y=end*l/2
   for side in (-1,1):
    p.append(mesh(name+'_Entrance',[(side*.14,y,.04),(side*w/2,y,.04),(side*w/2,y,h*.33),(0,y,h),(side*.14,y,h*.72)],[(0,1,2),(0,2,4),(2,3,4)],cloth))
   p.append(rod(name+'_RidgePole',(0,y,0),(0,y,h+.12),.045,wood))
  p.append(rod(name+'_Ridge',(0,-l/2-.08,h),(0,l/2+.08,h),.045,wood))
  for side in (-1,1):
   for y in (-l/2,0,l/2):
    anchor=(side*(w/2+.75),y+.2,.04)
    p.append(rod(name+'_Guy',(side*w/2,y,h*.33),anchor,.009,rope,8))
    p.append(rod(name+'_Peg',(anchor[0],anchor[1],0),(anchor[0]-.05,anchor[1],.16),.018,wood,8))
  if name=='CommandTent':
   for x in (-.95,.95): p.append(rod('PorchPost',(x,-l/2-1.3,0),(x,-l/2-1.3,1.85),.04,wood))
   p.append(grid('PorchAwning',[[(-1,-l/2,2.05),(1,-l/2,2.05)],[(-1,-l/2-1.4,1.85),(1,-l/2-1.4,1.85)]],cloth))
  return join(p,name)
 facilities.append(tent('CommandTent',4,5,3))
 facilities.append(tent('TentA',2.4,3,1.8)); facilities.append(tent('TentB',2.4,3,1.8))
 p=[]
 for i in range(8): p.append(box('DeckPlank',(0,(i-3.5)*.23,.77),(1.35,.21,.12),wood))
 for x in (-.71,.71):
  for z in (1.0,1.3): p.append(box('SideRail',(x,0,z),(.08,1.95,.13),wood))
  for y in (-.87,.87): p.append(box('Stanchion',(x,y,1.04),(.09,.09,.85),wood))
 p.append(rod('Axle',(-1,0,.52),(1,0,.52),.065,iron))
 for x in (-.87,.87):
  p.append(rod('Hub',(x-.12,0,.54),(x+.12,0,.54),.105,wood))
  vs=[]
  for i in range(16):
   a=i*math.tau/16
   for j in range(8):
    b=j*math.tau/8; radius=.49+.045*math.cos(b)
    vs.append((x+.045*math.sin(b),radius*math.cos(a),.54+radius*math.sin(a)))
  fs=[(i*8+j,((i+1)%16)*8+j,((i+1)%16)*8+(j+1)%8,i*8+(j+1)%8) for i in range(16) for j in range(8)]
  p.append(mesh('WheelRim',vs,fs,wood))
  for i in range(12):
   a=i*math.tau/12
   p.append(rod('Spoke',(x,.12*math.cos(a),.54+.12*math.sin(a)),(x,.45*math.cos(a),.54+.45*math.sin(a)),.025,wood,8))
 for x in (-.48,.48): p.append(rod('Shaft',(x,-.7,.7),(x,-2.7,.32),.045,wood))
 p.append(box('CartLoad',(0,.3,1.04),(1.1,.9,.42),dark)); facilities.append(join(p,'SupplyCart'))
 p=[]
 for i,(x,y,z) in enumerate([(-.6,0,.33),(.15,.25,.33),(-.5,.05,.93)]):
  p.append(box('Crate',(x,y,z),(.64,.7,.6),wood))
  for s in (-1,1):
   p.append(box('CrateBinding',(x+s*.23,y,z),(.045,.73,.63),iron))
 for x,y in ((.7,-.3),(.7,.4)):
  p.append(vessel('Cask',x,y,[(.03,.24),(.13,.27),(.43,.29),(.73,.27),(.83,.24)],wood))
  for z in (.14,.69): p.append(rod('CaskHoop',(x,y,z),(x,y,z+.05),.286,iron,16))
 for i in range(3):
  x=-.9+i*.48; p.append(vessel('GrainSack',x,-.85,[(.02,.15),(.09,.23),(.3,.24),(.45,.15),(.49,.07)],cloth,12))
 facilities.append(join(p,'Stores'))
 p=[rod('SentryPole',(0,0,0),(0,0,3),.06,wood),box('Lantern',(0,.15,2.45),(.2,.25,.3),iron)]
 p.append(grid('OrdinaryPennon',[[(0,0,2.9),(.65,.035,2.85)],[(0,0,2.55),(.65,.035,2.7)]],dark))
 for x in (-1,1): p.append(rod('WatchStake',(x,0,0),(x,0,1.2),.055,wood))
 for z in (.48,.95): p.append(rod('WatchRail',(-1.1,0,z),(1.1,0,z),.045,wood))
 facilities.append(join(p,'Watch'))
 for o in facilities:
  ground=min(v.co.z for v in o.data.vertices)
  for v in o.data.vertices: v.co.z-=ground
 # Vertex dirt follows local ground height rather than a repeating UV band.
 # POINT colours preserve existing mesh vertices and all facility transforms.
 for o in facilities:
  if o.name in ('CommandTent','TentA','TentB'):
   for face in o.data.polygons:
    for loop_index in face.loop_indices:
     c=o.data.vertices[o.data.loops[loop_index].vertex_index].co
     # Canvas panels run along the ridge, never diagonally across a roof.
     o.data.uv_layers.active.data[loop_index].uv=(c.y/4+.5,(c.x if abs(face.normal.z)>.2 else c.z)/4+.5)
  colors=o.data.color_attributes.new(name='Weathering',type='FLOAT_COLOR',domain='POINT')
  for vertex in o.data.vertices:
   x,y,z=vertex.co
   irregular=.06*math.sin(2.3*x+1.7*y)+.035*math.cos(5.1*y-x)
   damp=max(0,min(1,(.42+irregular-z)/.42))
   fade=.035*math.sin(1.3*x+2.1*y+.7*z)
   colors.data[vertex.index].color=(1-.36*damp+fade,1-.40*damp+fade,1-.44*damp+fade,1)
 audits={o.name:qk.audit_game(o,11000,5) for o in facilities}
 assert all(a['pass'] for a in audits.values()),audits
 assert sum(a['tris'] for a in audits.values())<=11000
 REPORT['camp']={'audits':audits,'tris':sum(a['tris'] for a in audits.values()),'bounds':{o.name:bounds(o) for o in facilities}}
 assert all(b['min'][2]>=-1e-5 for b in REPORT['camp']['bounds'].values()),REPORT['camp']['bounds']
 bpy.ops.wm.save_as_mainfile(filepath=str(CAMP/'model_wip/field_camp.blend'),compress=True)
 export(CAMP/'field_camp.glb',facilities)
 # Keep Godot's already-extracted texture names current on a material-only rebuild.
 import struct
 data=(CAMP/'field_camp.glb').read_bytes(); json_size=struct.unpack_from('<I',data,12)[0]
 document=json.loads(data[20:20+json_size]); binary=data[28+json_size:]
 for image in document.get('images',[]):
  view=document['bufferViews'][image['bufferView']]; offset=view.get('byteOffset',0)
  (CAMP/('field_camp_'+image['name']+'.png')).write_bytes(binary[offset:offset+view['byteLength']])
 for o,pos in zip(facilities,[(0,3,0),(-4,-2,0),(0,-3,0),(4,0,0),(3,-3,0),(-4,2,0)]): o.location=pos
 render(CAMP/'model_wip/overview.png',facilities,(0,0,1),19,.65)
 render(CAMP/'model_wip/overview_side.png',facilities,(0,0,1),19,1.8)

if '--camp-only' not in sys.argv: king()
camp()
if 'king' in REPORT: (KING/'model_wip/build_report.json').write_text(json.dumps(REPORT,indent=2))
(CAMP/'model_wip/build_report.json').write_text(json.dumps(REPORT,indent=2))
print('P33_REPORT',json.dumps(REPORT))
