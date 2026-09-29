"""One walk cycle of CMU 02_01 (free for any use) as DATA for march.py, in the
soldier's own frame (he faces -Y, his left is +X, up +Z), N frames:
  hip      the mid-hip point's offset from its cycle mean (lateral x, surge y, bob z)
  pelvis   the unit vector from the right hip joint to the left
  chest    the unit vector from the right shoulder to the left, and the spine's up
  ank_L/R  ankle minus that side's hip joint;  toe_L/R  the foot's direction (ankle to toe)
  arm_L/R  the upper arm's direction;  fore_L/R the forearm's
  leg      the take's leg length (hip joint to knee to ankle, at rest)
  blender -b --factory-startup --python mocap_extract.py -- BVH OUT.json [N]
"""
import bpy, sys, json, math
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
BVH, OUT = a[0], a[1]
N = int(a[2]) if len(a) > 2 else 32
bpy.ops.import_anim.bvh(filepath=BVH, global_scale=0.055, use_fps_scale=False,
                        update_scene_fps=False, update_scene_duration=True)
mo = next(o for o in bpy.data.objects if o.type == "ARMATURE")
sc = bpy.context.scene
pb = mo.pose.bones
mw = mo.matrix_world


def P(name, tail=False):
    b = pb[name]
    return mw @ (b.tail if tail else b.head)


# the cycle: two successive peaks of the left ankle ahead of the hips (as mocap_march.py)
f0, f1 = sc.frame_start, sc.frame_end - 1
hip, lt = [], []
for f in range(f0, f1 + 1):
    sc.frame_set(f)
    hip.append(P("Hips")); lt.append(P("LeftFoot"))
d = hip[-1] - hip[0]; d.z = 0; d.normalize()
ahead = [(lt[i] - hip[i]).dot(d) for i in range(len(hip))]
peaks = [i for i in range(2, len(ahead) - 2) if ahead[i] == max(ahead[i - 2:i + 3]) and ahead[i] > 0]
clean = []
for p in peaks:
    if not clean or p - clean[-1] > 40:
        clean.append(p)
clean = [c for c in clean if c > 25]
A, Bf = f0 + clean[0], f0 + clean[1]
d = hip[clean[1]] - hip[clean[0]]; d.z = 0; d.normalize()
left = Vector((0, 0, 1)).cross(d)


def mine(v):
    """take's frame -> the soldier's: forward d -> -Y, left -> +X"""
    return Vector((v.dot(left), -v.dot(d), v.z))


sc.frame_set(A)
rest = {}
for n in ("LeftUpLeg", "LeftLeg", "LeftFoot"):
    rest[n] = mo.data.bones[n].length * 0.055 if False else None
leg = ((P("LeftLeg") - P("LeftUpLeg")).length + (P("LeftFoot") - P("LeftLeg")).length)
frames = []
for i in range(N):
    t = A + (Bf - A) * i / N
    sc.frame_set(int(math.floor(t)), subframe=t - math.floor(t))
    hl, hr = P("LeftUpLeg"), P("RightUpLeg")
    mid = (hl + hr) / 2
    fr = {"mid": list(mine(mid)), "pelvis": list(mine(hl - hr).normalized()),
          "chest": list(mine(P("LeftArm") - P("RightArm")).normalized()),
          "up": list(mine(P("Neck") - P("Spine1")).normalized()) if "Neck" in pb else list(mine(P("Head") - P("Spine")).normalized())}
    for sd, nm in (("L", "Left"), ("R", "Right")):
        fr["ank_" + sd] = list(mine(P(nm + "Foot") - P(nm + "UpLeg")))
        toe = P(nm + "ToeBase") if (nm + "ToeBase") in pb else P(nm + "Foot", tail=True)
        fr["toe_" + sd] = list(mine(toe - P(nm + "Foot")).normalized())
        fr["arm_" + sd] = list(mine(P(nm + "ForeArm") - P(nm + "Arm")).normalized())
        fr["fore_" + sd] = list(mine(P(nm + "Hand") - P(nm + "ForeArm")).normalized())
    frames.append(fr)
# the hip point relative to its cycle mean, with the steady forward travel taken out
mids = [Vector(f["mid"]) for f in frames]
travel = (mine(hip[clean[1]] - hip[clean[0]])).y
for i, f in enumerate(frames):
    m = mids[i] - Vector((0, travel * i / N, 0))
    f["mid_rel"] = list(m)
mean = sum((Vector(f["mid_rel"]) for f in frames), Vector()) / N
for f in frames:
    f["hip"] = list(Vector(f["mid_rel"]) - mean)
# the ground: the lowest ankle over the cycle, relative to the mean hip height
ground = min(min(Vector(f["mid_rel"]).z + f["ank_L"][2], Vector(f["mid_rel"]).z + f["ank_R"][2]) for f in frames)
json.dump({"frames": frames, "leg": leg, "hip_h": mean.z - ground, "cycle": [A, Bf], "stride": abs(travel)},
          open(OUT, "w"), indent=0)
print("MOCAP cycle", A, Bf, "leg %.3f hip_h %.3f stride %.3f" % (leg, mean.z - ground, abs(travel)))
