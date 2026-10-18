"""Add equipped spear ATTACK and shield DEFEND to the installed knight, without re-exporting art.

Run in isolated Blender CLI (never load into the owner's live file):
  Blender --background --factory-startup --python tools/units3d/infantry_knight/battle_clips.py -- SOURCE.glb OUTPUT.glb REVIEW_DIR
Uses the installed GARRISON's fitted guard and exact equipment/rig. Appends new
animation buffers only; all existing JSON sections and binary bytes are retained.
"""
import bpy
import copy
import json
import math
import os
import struct
import sys
import numpy as np
from mathutils import Matrix, Quaternion, Vector

source, output, review = sys.argv[sys.argv.index('--') + 1:]
os.makedirs(review, exist_ok=True)
raw = open(source, 'rb').read()
jlen = struct.unpack_from('<I', raw, 12)[0]
g = json.loads(raw[20:20+jlen])
assert not any(a['name'] in ('ATTACK', 'DEFEND') for a in g['animations']), 'already has battle clips'
blob = bytearray(raw[28+jlen:])
original = copy.deepcopy(g)
parents = {c: i for i, n in enumerate(g['nodes']) for c in n.get('children', [])}
ids = {n['name']: i for i, n in enumerate(g['nodes'])}

def values(i):
    a = g['accessors'][i]; v = g['bufferViews'][a['bufferView']]
    width = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[a['type']]
    assert a['componentType'] == 5126 and not v.get('byteStride')
    return np.frombuffer(blob, '<f4', a['count']*width, v.get('byteOffset', 0)+a.get('byteOffset', 0)).reshape(-1,width).copy()

def local(n):
    q=n.get('rotation',[0,0,0,1]);return Matrix.LocRotScale(Vector(n.get('translation',[0,0,0])), Quaternion((q[3],q[0],q[1],q[2])),Vector(n.get('scale',[1,1,1])))

base_nodes=copy.deepcopy(g['nodes'])
for ch in next(a for a in g['animations'] if a['name']=='GARRISON')['channels']:
    s=next(a for a in g['animations'] if a['name']=='GARRISON')['samplers'][ch['sampler']]
    base_nodes[ch['target']['node']][ch['target']['path']]=values(s['output'])[0].tolist()
world={}
def global_matrix(i):
    if i not in world:world[i]=(global_matrix(parents[i]) if i in parents else Matrix.Identity(4))@local(base_nodes[i])
    return world[i]
for i in range(len(g['nodes'])):global_matrix(i)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(source))
scene=bpy.context.scene;scene.render.fps=30
rig=bpy.data.objects['inf_rig'];mesh=bpy.data.objects['infantry'];ad=rig.animation_data
for t in ad.nla_tracks:t.mute=True
ad.action=bpy.data.actions['GARRISON'];ad.action_slot=ad.action.slots[0]
scene.frame_set(0);bpy.context.view_layer.update()
base={p.name:p.matrix.copy() for p in rig.pose.bones}
basis={p.name:p.matrix_basis.copy() for p in rig.pose.bones}
# glTF Y-up -> Blender Z-up. Per-joint corrections preserve importer bone rolls.
convert=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
correction={n:base[n].inverted()@convert@world[ids[n]] for n in base}
ad.action=None
order=[]
def walk(b):
    order.append(b.name)
    for c in b.children:walk(c)
for b in rig.data.bones:
    if b.parent is None:walk(b)

# Measured shaft direction from its rigidly weighted vertices in the approved guard.
e=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());em=e.to_mesh()
gi=mesh.vertex_groups['spear'].index
spear_ids=[v.index for v in mesh.data.vertices if any(w.group==gi and w.weight>.5 for w in v.groups)]
pts=np.array([tuple(em.vertices[i].co) for i in spear_ids]);_,_,vt=np.linalg.svd(pts-pts.mean(0),full_matrices=False)
forward=Vector(vt[0]);forward=forward if forward.y>0 else -forward
assert forward.y>.3 and abs(forward.z)<.3
mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()

# Brief: 30 fps, in-place, 2 s loops: committed thrust/recovery versus raised shield block.
def arm(side,target,hand_rotation):
    upper=rig.pose.bones[side+'Arm'];lower=rig.pose.bones[side+'ForeArm'];hand=rig.pose.bones[side+'Hand']
    sh=upper.head.copy();el=lower.head.copy();old=hand.head.copy()
    l1=(el-sh).length;l2=(old-el).length;axis=target-sh;dist=axis.length
    assert abs(l1-l2)+.005<dist<l1+l2-.005,(side,dist,l1+l2)
    axis.normalize();preferred=target-(hand_rotation.to_3x3()@Vector((0,1,0))).normalized()*l2;pole=preferred-sh-axis*(preferred-sh).dot(axis);pole.normalize()
    along=(l1*l1-l2*l2+dist*dist)/(2*dist)
    elbow=sh+axis*along+pole*math.sqrt(max(0,l1*l1-along*along))
    q=(lower.head-upper.head).rotation_difference(elbow-sh)
    upper.matrix=Matrix.Translation(sh)@q.to_matrix().to_4x4()@Matrix.Translation(-sh)@upper.matrix
    bpy.context.view_layer.update()
    q=(hand.head-lower.head).rotation_difference(target-lower.head)
    lower.matrix=Matrix.Translation(lower.head)@q.to_matrix().to_4x4()@Matrix.Translation(-lower.head)@lower.matrix
    bpy.context.view_layer.update()
    hm=hand_rotation.copy();hm.translation=hand.head;hand.matrix=hm
    bpy.context.view_layer.update()
    return (hand.head-target).length

record={};metrics={};samples={}
for clip in ('ATTACK','DEFEND'):
    wrist={sd:[] for sd in ('Right','Left')};elbows={sd:[] for sd in ('Right','Left')};frames=[];positions={n:[] for n in ('LeftFoot','RightFoot','RightHand','LeftHand','head','spear','shield')};max_ik=0
    for f in range(61):
        for n in order:rig.pose.bones[n].matrix_basis=basis[n]
        bpy.context.view_layer.update()
        # Distinct combat silhouettes: committed low thrust versus a raised protective block.
        phase=2*math.pi*f/60
        reach=.5*(1-math.cos(phase))
        amount=-.06+.32*reach if clip=='ATTACK' else .23+.025*math.sin(phase)
        turn=-8+20*reach if clip=='ATTACK' else -12+3*math.sin(phase)
        lean=8+18*reach if clip=='ATTACK' else -9+2*math.sin(phase)
        torso=rig.pose.bones['Spine1'];pivot=torso.head.copy()
        side_axis=Vector((-forward.y,forward.x,0))
        rot=Matrix.Rotation(math.radians(lean),4,side_axis)@Matrix.Rotation(math.radians(turn),4,'Z')
        move=Matrix.Translation(pivot)@rot@Matrix.Translation(-pivot)
        torso.matrix=move@torso.matrix;bpy.context.view_layer.update()
        if clip=='ATTACK':
            neck=rig.pose.bones['Neck'];at=neck.head.copy()
            neck.matrix=Matrix.Translation(at)@Matrix.Rotation(math.radians(-lean*.8),4,side_axis)@Matrix.Translation(-at)@neck.matrix
            bpy.context.view_layer.update()
        right=move@base['RightHand'];left=move@base['LeftHand']
        right.translation+=forward*amount if clip=='ATTACK' else Vector((0,-.02,.15))
        left.translation+=Vector((0,-.015,-.025)) if clip=='ATTACK' else Vector((.12,.02,amount))
        # A shield block lifts the spear clear into a diagonal guard instead of imitating a thrust.
        if clip=='DEFEND':
            grip=right.translation.copy()
            right=Matrix.Translation(grip)@Matrix.Rotation(math.radians(-46),4,side_axis)@Matrix.Translation(-grip)@right
        if clip=='ATTACK':
            grip=right.translation.copy()
            right=Matrix.Translation(grip)@Matrix.Rotation(math.radians(-lean),4,side_axis)@Matrix.Translation(-grip)@right
            # The fist rolls around the shaft continuously, keeping the extension's wrist straight.
            grip=right.translation.copy()
            roll=Matrix.Rotation(math.radians(25+45*reach),4,(Matrix.Rotation(math.radians(turn),3,'Z')@forward).normalized())
            right=Matrix.Translation(grip)@roll@Matrix.Translation(-grip)@right
        max_ik=max(max_ik,arm('Right',right.translation,right),arm('Left',left.translation,left))
        for prop,hand in [('spear','RightHand'),('shield','LeftHand')]:
            rig.pose.bones[prop].matrix=rig.pose.bones[hand].matrix@base[hand].inverted()@base[prop]
        bpy.context.view_layer.update()
        pose={n:convert.inverted()@rig.pose.bones[n].matrix@correction[n] for n in order}
        frames.append({n:((pose[rig.data.bones[n].parent.name].inverted() if rig.data.bones[n].parent else world[parents[ids[n]]].inverted())@pose[n]) for n in order})
        for n in positions:positions[n].append(tuple(rig.pose.bones[n].head))
        for sd in wrist:
            u=rig.pose.bones[sd+'Arm'];lo=rig.pose.bones[sd+'ForeArm'];h=rig.pose.bones[sd+'Hand']
            wrist[sd].append(math.degrees((lo.tail-lo.head).angle(h.tail-h.head)))
            elbows[sd].append(math.degrees((u.head-lo.head).angle(h.head-lo.head)))
    record[clip]=frames
    stats={'duration_s':2.0,'frames':61,'max_ik_error_m':max_ik,'spear_thrust_m':.32 if clip=='ATTACK' else 0,'shield_raise_m':.23 if clip=='DEFEND' else 0}
    for n,p in positions.items():
        p=np.array(p);v=np.linalg.norm(np.diff(p,axis=0),axis=1);j=np.linalg.norm(np.diff(p,n=3,axis=0),axis=1)
        stats[n]={'max_frame_travel_m':float(v.max()),'pose_seam_m':float(np.linalg.norm(p[-1]-p[0])),'velocity_seam_m_frame':float(np.linalg.norm((p[-1]-p[-2])-(p[1]-p[0]))),'jerk_ratio':float(j.max()/(np.median(j)+1e-9))}
    stats['wrist_angle_deg']={sd:[min(v),max(v)] for sd,v in wrist.items()}
    stats['elbow_angle_deg']={sd:[min(v),max(v)] for sd,v in elbows.items()}
    assert max_ik<.00001
    assert all(max(v)<50 for v in wrist.values()),stats['wrist_angle_deg']
    assert all(stats[n]['max_frame_travel_m']<.002 for n in ('LeftFoot','RightFoot'))
    assert all(stats[n]['pose_seam_m']<.00001 and stats[n]['jerk_ratio']<8 for n in positions),stats
    assert all(15<min(v)<max(v)<175 for v in elbows.values())
    metrics[clip]=stats;samples[clip]={'positions':positions,'wrist_angle_deg':wrist,'elbow_angle_deg':elbows}

# Append packed float accessors without rewriting any pre-existing buffer/accessor.
def append(v):
    v=np.ascontiguousarray(v,dtype='<f4');width=v.shape[1] if v.ndim==2 else 1
    while len(blob)%4:blob.append(0)
    view=len(g['bufferViews']);g['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':v.nbytes});blob.extend(v.tobytes())
    a={'bufferView':view,'componentType':5126,'count':len(v),'type':{1:'SCALAR',3:'VEC3',4:'VEC4'}[width],'min':v.reshape(-1,width).min(0).tolist(),'max':v.reshape(-1,width).max(0).tolist()}
    g['accessors'].append(a);return len(g['accessors'])-1
for clip,frames in record.items():
    ai={'name':clip,'channels':[],'samplers':[]};times=append(np.arange(61)/30)
    for n in order:
        decomposed=[f[n].decompose() for f in frames]
        channels={'translation':[list(x[0]) for x in decomposed],'rotation':[[x[1].x,x[1].y,x[1].z,x[1].w] for x in decomposed],'scale':[list(x[2]) for x in decomposed]}
        q=channels['rotation']
        for i in range(1,len(q)):
            if np.dot(q[i-1],q[i])<0:q[i]=[-x for x in q[i]]
        for path,v in channels.items():
            ai['channels'].append({'sampler':len(ai['samplers']),'target':{'node':ids[n],'path':path}});ai['samplers'].append({'input':times,'output':append(v),'interpolation':'LINEAR'})
    g['animations'].append(ai)
g['buffers'][0]['byteLength']=len(blob)
for k in original:
    if k not in ('buffers','accessors','bufferViews','animations'):assert original[k]==g[k],k
assert g['animations'][:len(original['animations'])]==original['animations']
assert g['accessors'][:len(original['accessors'])]==original['accessors']
assert g['bufferViews'][:len(original['bufferViews'])]==original['bufferViews']
assert bytes(blob[:len(raw[28+jlen:])])==raw[28+jlen:]
js=json.dumps(g,separators=(',',':')).encode();js+=b' '*((-len(js))%4);blob.extend(b'\0'*((-len(blob))%4))
with open(output,'wb') as f:f.write(struct.pack('<4sII',b'glTF',2,28+len(js)+len(blob))+struct.pack('<I4s',len(js),b'JSON')+js+struct.pack('<I4s',len(blob),b'BIN\0')+blob)
json.dump(samples,open(os.path.join(review,'motion_samples.json'),'w'),indent=2)
json.dump(metrics,open(os.path.join(review,'metrics.json'),'w'),indent=2)
print('WROTE',output,json.dumps(metrics))
