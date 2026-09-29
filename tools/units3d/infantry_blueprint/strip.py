import bpy, math, sys, mathutils
a = sys.argv[sys.argv.index("--")+1:]
OUT, YAW, N = a[0], float(a[1]), int(a[2])
exec(open("/Users/samuelzhang/game_design/tools/units3d/infantry_blueprint/shots.py").read().split("cam = bpy.data.objects.new")[0].replace("a = sys.argv[sys.argv.index(\"--\")+1:]\nOUT, VIEWS = a[0], a[1:]", ""))
sc = bpy.context.scene
sc.render.resolution_x, sc.render.resolution_y = 380, 620
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 3.0
tv = mathutils.Vector((0, 0, 1.2)); ya = math.radians(YAW)
cam.location = tv + mathutils.Vector((math.sin(ya), -math.cos(ya), 0.12)) * 5
cam.rotation_euler = (tv - cam.location).to_track_quat("-Z", "Y").to_euler()
plane = bpy.ops.mesh.primitive_plane_add(size=6)
import os
LEN = 32
if os.environ.get("ACT"):
    _r = bpy.data.objects["inf_rig"]; _r.animation_data.action = bpy.data.actions[os.environ["ACT"]]
    LEN = int(_r.animation_data.action.frame_range[1]) - 1
for k in range(N):
    f = 1 + round(k * LEN / N)
    sc.frame_set(f)
    sc.render.filepath = "%s_%02d.png" % (OUT, f); bpy.ops.render.render(write_still=True)
