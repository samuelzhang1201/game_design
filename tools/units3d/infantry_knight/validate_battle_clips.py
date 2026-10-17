"""Round-trip checks and 21-frame equipped review strips for the infantry battle clips.
Blender --background --factory-startup --python THIS.py -- INFANTRY.glb REVIEW_DIR
"""
import bpy,os,json,math,sys
import numpy as np
from mathutils import Vector
source,out=sys.argv[sys.argv.index('--')+1:];os.makedirs(out,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=30;bpy.ops.import_scene.gltf(filepath=os.path.abspath(source))
s=bpy.context.scene;s.render.fps=30;r=bpy.data.objects['inf_rig'];m=bpy.data.objects['infantry'];ad=r.animation_data
for t in ad.nla_tracks:t.mute=True
s.render.engine='BLENDER_WORKBENCH';s.display.shading.light='STUDIO';s.display.shading.color_type='TEXTURE';s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.world=bpy.data.worlds.new('Review');s.world.color=(.12,.12,.12);s.render.film_transparent=False
s.render.resolution_x=560;s.render.resolution_y=560;s.render.resolution_percentage=100
cam=bpy.data.objects.new('cam',bpy.data.cameras.new('cam'));s.collection.objects.link(cam);s.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=3.6
checks={}
for clip in ('ATTACK','DEFEND'):
 ad.action=bpy.data.actions[clip];ad.action_slot=ad.action.slots[0]
 p={n:[] for n in ('LeftFoot','RightFoot','RightHand','LeftHand','head')};grip={n:[] for n in ('spear','shield')};mins=[]
 for f in range(61):
  s.frame_set(f);bpy.context.view_layer.update()
  for n in p:p[n].append(tuple(r.pose.bones[n].head))
  for prop,hand in [('spear','RightHand'),('shield','LeftHand')]:
   mat=r.pose.bones[hand].matrix.inverted()@r.pose.bones[prop].matrix;grip[prop].append(list(mat.translation))
  em=m.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh();mins.append(min(v.co.z for v in em.vertices));m.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
 checks[clip]={'ground_min_m':min(mins),'duration_s':ad.action.frame_range[1]/30,'motion':{}}
 for n,v in p.items():
  a=np.array(v);checks[clip]['motion'][n]={'max_frame_m':float(np.linalg.norm(np.diff(a,axis=0),axis=1).max()),'seam_m':float(np.linalg.norm(a[-1]-a[0]))}
 for n,v in grip.items():
  a=np.array(v);checks[clip][n+'_grip_deviation_m']=float(np.linalg.norm(a-a[0],axis=1).max())
 for view,eye in [('front',(0,6,2.0)),('side',(6,0,2.0)),('quarter',(4,5,2.0))]:
  cam.location=eye;cam.rotation_euler=(Vector((-.05,.35,.95))-cam.location).to_track_quat('-Z','Y').to_euler()
  for f in range(0,61,3):
   s.frame_set(f);s.render.filepath=out+'/'+clip+'-'+view+'-%02d.png'%f;bpy.ops.render.render(write_still=True)
for stats in checks.values():
 assert abs(stats['duration_s']-2)<.0001
 assert stats['spear_grip_deviation_m']<.0002 and stats['shield_grip_deviation_m']<.0002
 for foot in ('LeftFoot','RightFoot'):assert stats['motion'][foot]['max_frame_m']<.002
 assert all(v['seam_m']<.00001 for v in stats['motion'].values())
json.dump(checks,open(out+'/roundtrip.json','w'),indent=2);print('ROUNDTRIP',checks)
