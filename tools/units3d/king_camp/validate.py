"""Isolated Blender round-trip and numeric asset checks (no game/editor writes)."""
import bpy,json,struct,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
KING=ROOT/'assets/3D/characters/king'; CAMP=ROOT/'assets/3D/buildings/field_camp'

def glb(path):
 b=path.read_bytes(); n=struct.unpack_from('<I',b,12)[0]; return json.loads(b[20:20+n])

def load(path):
 bpy.ops.wm.read_factory_settings(use_empty=True); bpy.context.scene.render.fps=30
 bpy.ops.import_scene.gltf(filepath=str(path))
 return [o for o in bpy.context.scene.objects if o.type=='MESH' and o.name!='Icosphere']

def box(o):
 bpy.context.view_layer.update(); dg=bpy.context.evaluated_depsgraph_get(); ev=o.evaluated_get(dg); m=ev.to_mesh()
 v=[o.matrix_world@p.co for p in m.vertices]; ev.to_mesh_clear()
 return {'min':[min(p[i] for p in v) for i in range(3)],'max':[max(p[i] for p in v) for i in range(3)]}

j=glb(KING/'king.glb'); meshes=load(KING/'king.glb'); rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
names={a['name'] for a in j['animations']}; assert names=={'MARCH','STANDBY','OBSERVE','COMMAND','INSPIRE'},names
assert len(j['materials'])<=5
assert len(j['skins'])==1
tris=sum(j['accessors'][p['indices']]['count']//3 for m in j['meshes'] for p in m['primitives']); assert tris<=20000
assert {'KingBody','Crown','Mantle','RoyalStandardPole','RoyalStandard','RoyalStandardStripe'}<={o.name for o in meshes}
weights={}
for o in meshes:
 zeros=many=bad=0
 for v in o.data.vertices:
  w=[g.weight for g in v.groups if g.weight>1e-5]; zeros+=not w; many+=len(w)>4; bad+=abs(sum(w)-1)>.02
 weights[o.name]={'zero_weights':zeros,'over_four':many,'unnormalized':bad}; assert zeros==many==bad==0,weights
for t in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(t)
actions={a.name:a for a in bpy.data.actions}
loops={}; foot_samples={}; observed_motion={}; king_march={}
for name in sorted(names):
 a=actions[name]; rig.animation_data.action=a; first,last=map(float,a.frame_range)
 endpoints=[]; heads=[]
 for f in (first,last):
  bpy.context.scene.frame_set(int(f),subframe=f-int(f)); bpy.context.view_layer.update()
  endpoints.append({p.name:p.matrix.copy() for p in rig.pose.bones})
 delta=max(max(abs(endpoints[0][b][i][k]-endpoints[1][b][i][k]) for i in range(4) for k in range(4)) for b in endpoints[0])
 loops[name]={'duration_s':(last-first)/30,'endpoint_matrix_max_error':delta}
 if name in ('MARCH','STANDBY','OBSERVE'): assert delta<.001,(name,delta)
 for f in (first,(first+last)/2,last*.75):
  bpy.context.scene.frame_set(int(f),subframe=f-int(f)); bpy.context.view_layer.update()
  heads.append(list(rig.matrix_world@rig.pose.bones['head'].head))
 observed_motion[name]=heads
 if name=='MARCH':
  for b in ('FrontHoof.L','FrontHoof.R','HindHoof.L','HindHoof.R'):
   if b not in rig.pose.bones: continue
   points=[]
   for f in range(17):
    bpy.context.scene.frame_set(f); bpy.context.view_layer.update(); points.append(list(rig.matrix_world@rig.pose.bones[b].head))
   if not king_march:
    for f in range(17):
     bpy.context.scene.frame_set(f); bpy.context.view_layer.update()
     king_march[f]={p.name:p.matrix.copy() for p in rig.pose.bones}
   low=min(p[2] for p in points); steps=[points[i+1][1]-points[i][1] for i in range(16) if points[i][2]<low+.035 and points[i+1][2]<low+.035]
   foot_samples[b]={'anchor_height_min':low,'stance_forward_steps_m':steps,'implied_stride_m':[abs(v)*16 for v in steps]}
king={'tris':tris,'materials':len(j['materials']),'bones':len(rig.data.bones),'skin_checks':weights,'clips':loops,'foot_anchors':foot_samples,'head_motion':observed_motion,'bounds':{o.name:box(o) for o in meshes}}
# Verify retained gait against the committed donor after separate reimport.
assert j['animations'][0]['channels']
load(ROOT/'assets/3D/units/cavalry/cavalry.glb'); donor=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
for t in list(donor.animation_data.nla_tracks): donor.animation_data.nla_tracks.remove(t)
donor.animation_data.action=bpy.data.actions['MARCH']; max_error=0
for f,poses in king_march.items():
 bpy.context.scene.frame_set(f); bpy.context.view_layer.update()
 max_error=max(max_error,max(abs(donor.pose.bones[b].matrix[i][k]-p[i][k]) for b,p in poses.items() for i in range(4) for k in range(4)))
assert max_error<.00001,max_error
king['donor_march_matrix_max_error']=max_error
meshes=load(CAMP/'field_camp.glb'); j=glb(CAMP/'field_camp.glb')
assert {o.name for o in meshes}=={'CommandTent','TentA','TentB','SupplyCart','Stores','Watch'}
assert len(j['materials'])<=5
tris=sum(j['accessors'][p['indices']]['count']//3 for m in j['meshes'] for p in m['primitives']); assert tris<=11000
bounds={o.name:box(o) for o in meshes}; assert all(v['min'][2]>=-1e-5 for v in bounds.values()),bounds
camp={'tris':tris,'materials':len(j['materials']),'bounds':bounds,'nodes':[o.name for o in meshes]}
report={'king':king,'camp':camp,'limits':['Preserved donor GLTF seam splits; welded donor audit has 15 inherited non-manifold edges.','Foot anchors are bone heads, not hoof sole surface; do not interpret their height as ground penetration.','In-place stride inferred from low-phase anchors; runtime 2.4 m gait distance, not old map display calibration 5.9 m.','No game-window flat/slope/near-water review performed by this asset task.']}
(KING/'model_wip/roundtrip.json').write_text(json.dumps(report,indent=2)); (CAMP/'model_wip/roundtrip.json').write_text(json.dumps(report,indent=2))
print('P33_ROUNDTRIP',json.dumps(report))
