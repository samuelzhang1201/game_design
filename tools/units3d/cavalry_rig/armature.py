"""Phase 3C: the cavalry's armature `cavalry_rig`, the king's bone set (the skill's horse template,
`Saddle` -> the R_ rider) with the knight's own props: `Lance` on the right hand, `Shield` on the
chest (keyed onto the left arm by the clips that take it there), `Reins` (the rein hand's place).
Frame (Gate 1): faces -Y, left +X, hooves on z = 0, metres.

How each joint was measured (shots/grid_side_g.png, grid_front_g.png):
  * horse legs -- 2.5 cm slices of each leg's own Tripo parts (11/40, 8/19, 7/22, 6/23): hoof,
    fetlock, carpus, hock centroids; elbow, point of shoulder, stifle, hip read off the gridded
    x-ray side render; the spine 25 % of the barrel (0.84-1.52) below the top line;
  * tail -- the tail part's centroid every 10 cm; head -- the poll and the muzzle tip of 30/31;
  * rider -- junctions between neighbouring plates (rerebrace|vambrace, poleyn|greave,
    greave|sabaton), the pauldrons' centroids, the torso part's sections; the right fist lies on
    the lance's own axis (checked: 7 mm off it), so the Lance bone runs from it along the shaft;
  * shield -- its own long axis (the back plate's end points).
"""

V = Vector

HORSE_LEGS = {
    "L": {"front": [(0.10, -0.22, 1.45), (0.16, -0.64, 1.13), (0.17, -0.44, 0.84),
                    (0.17, -0.38, 0.45), (0.168, -0.37, 0.16), (0.174, -0.43, 0.0)],
          "hind": [(0.16, 0.80, 1.17), (0.19, 0.74, 0.86), (0.165, 0.94, 0.55),
                   (0.18, 0.925, 0.16), (0.168, 0.86, 0.0)]},
    "R": {"front": [(-0.08, -0.22, 1.45), (-0.12, -0.64, 1.13), (-0.12, -0.46, 0.84),
                    (-0.12, -0.44, 0.45), (-0.12, -0.43, 0.16), (-0.103, -0.47, 0.0)],
          "hind": [(-0.13, 0.78, 1.17), (-0.15, 0.68, 0.84), (-0.105, 0.80, 0.53),
                   (-0.118, 0.69, 0.16), (-0.11, 0.635, 0.0)]},
}
SPINE = [(0.0, 0.40, 1.36), (0.0, 0.0, 1.37), (0.0, -0.30, 1.40), (0.0, -0.42, 1.46)]
NECK = [(0.0, -0.42, 1.46), (0.02, -0.68, 1.62), (0.04, -0.92, 1.83)]
MUZZLE = (0.14, -1.24, 1.44)
TAIL = [(0.022, 0.97, 1.44), (0.01, 1.07, 1.25), (0.03, 1.09, 0.95), (0.045, 1.13, 0.62), (0.05, 1.135, 0.28)]
PELVIS_TAIL = (0.0, 0.95, 1.42)

SEAT = (0.0, 0.08, 1.56)
RIDER_SPINE = [(0.0, 0.08, 1.56), (0.02, 0.03, 1.70), (0.02, 0.02, 1.86), (0.01, 0.10, 2.08), (0.02, 0.08, 2.18)]
RIDER_HEAD_TOP = (0.03, 0.06, 2.48)
RIDER_ARMS = {   # clavicle root, shoulder, elbow, wrist, hand tip
    "L": [(0.04, 0.10, 2.05), (0.20, 0.10, 2.03), (0.28, 0.02, 1.80), (0.20, -0.15, 1.75), (0.15, -0.24, 1.72)],
    "R": [(-0.02, 0.10, 2.05), (-0.17, 0.08, 2.03), (-0.28, 0.06, 1.80), (-0.22, -0.18, 1.85), (-0.16, -0.30, 1.87)],
}
RIDER_LEGS = {   # hip, knee, ankle, toe
    "L": [(0.11, 0.08, 1.57), (0.35, -0.15, 1.30), (0.37, -0.146, 0.922), (0.42, -0.33, 0.85)],
    "R": [(-0.09, 0.08, 1.57), (-0.30, -0.16, 1.29), (-0.34, -0.18, 0.94), (-0.40, -0.37, 0.85)],
}
LANCE = [(-0.169, -0.264, 1.871), (-0.011, -0.413, 3.214)]       # the grip (on the axis) and the tip
SHIELD = [(0.0, 0.457, 1.553), (0.0, 0.291, 2.185)]             # its long axis, bottom to top


def build():
    old = bpy.data.objects.get(RIG_NAME)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    arm = bpy.data.armatures.new(RIG_NAME)
    rig = bpy.data.objects.new(RIG_NAME, arm)
    coll("Cavalry_Rig").objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones

    def B(n, h, t, par=None, con=False, deform=True):
        b = eb.new(n); b.head = V(h); b.tail = V(t)
        if par:
            b.parent = eb[par]; b.use_connect = con
        b.use_deform = deform
        return b

    B("root", (0, 0, 0), (0, 0.3, 0), deform=False)
    B("Spine1", SPINE[0], SPINE[1], "root")
    B("Spine2", SPINE[1], SPINE[2], "Spine1", True)
    B("Chest", SPINE[2], SPINE[3], "Spine2", True)
    B("Neck1", NECK[0], NECK[1], "Chest", True)
    B("Neck2", NECK[1], NECK[2], "Neck1", True)
    B("Head", NECK[2], MUZZLE, "Neck2", True)
    B("Pelvis", SPINE[0], PELVIS_TAIL, "root")
    for i in range(4):
        B("Tail%d" % (i + 1), TAIL[i], TAIL[i + 1], "Pelvis" if i == 0 else "Tail%d" % i, i > 0)
    for s in "LR":
        f, h = HORSE_LEGS[s]["front"], HORSE_LEGS[s]["hind"]
        names = ["FrontScapula", "FrontUpperArm", "FrontForearm", "FrontCannon", "FrontHoof"]
        for i, n in enumerate(names):
            B("%s.%s" % (n, s), f[i], f[i + 1], "Chest" if i == 0 else "%s.%s" % (names[i - 1], s), i > 0)
        names = ["HindThigh", "HindShin", "HindCannon", "HindHoof"]
        for i, n in enumerate(names):
            B("%s.%s" % (n, s), h[i], h[i + 1], "Pelvis" if i == 0 else "%s.%s" % (names[i - 1], s), i > 0)
    B("Saddle", SEAT, (SEAT[0], SEAT[1], SEAT[2] + 0.1), "Spine1", deform=False)
    rs = RIDER_SPINE
    B("R_Hips", rs[0], rs[1], "Saddle")
    B("R_Spine", rs[1], rs[2], "R_Hips", True)
    B("R_Chest", rs[2], rs[3], "R_Spine", True)
    B("R_Neck", rs[3], rs[4], "R_Chest", True)
    B("R_Head", rs[4], RIDER_HEAD_TOP, "R_Neck", True)
    for s in "LR":
        a = RIDER_ARMS[s]
        B("R_Clavicle.%s" % s, a[0], a[1], "R_Chest")
        B("R_UpperArm.%s" % s, a[1], a[2], "R_Clavicle.%s" % s, True)
        B("R_Forearm.%s" % s, a[2], a[3], "R_UpperArm.%s" % s, True)
        B("R_Hand.%s" % s, a[3], a[4], "R_Forearm.%s" % s, True)
        lg = RIDER_LEGS[s]
        B("R_Thigh.%s" % s, lg[0], lg[1], "R_Hips")
        B("R_Shin.%s" % s, lg[1], lg[2], "R_Thigh.%s" % s, True)
        B("R_Foot.%s" % s, lg[2], lg[3], "R_Shin.%s" % s, True)
    g, tip = V(LANCE[0]), V(LANCE[1])
    B("Lance", g, g + (tip - g).normalized() * 0.35, "R_Hand.R")
    lo, hi = V(SHIELD[0]), V(SHIELD[1])
    c = (lo + hi) / 2
    B("Shield", c - (hi - lo).normalized() * 0.12, c + (hi - lo).normalized() * 0.12, "R_Chest")
    rh = V(RIDER_ARMS["L"][3])
    B("Reins", rh, rh + V((0, 0, 0.1)), "root")
    for b in eb:
        d = (b.tail - b.head).normalized()
        b.align_roll(V((0, 0, 1)) if abs(d.z) < 0.7 else V((0, -1, 0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    cols = {n: arm.collections.new(n) for n in ("Horse", "Rider", "Props")}
    for b in arm.bones:
        k = "Rider" if b.name.startswith("R_") or b.name == "Saddle" else \
            "Props" if b.name in ("Lance", "Shield", "Reins") else "Horse"
        cols[k].assign(b)
    rig.show_in_front = True
    arm.display_type = "STICK"
    return {"bones": len(arm.bones), "deform": sum(1 for b in arm.bones if b.use_deform)}


def bone_lines():
    rig = bpy.data.objects[RIG_NAME]
    out = []
    for b in rig.data.bones:
        h = rig.matrix_world @ b.head_local
        t = rig.matrix_world @ b.tail_local
        rider = b.name.startswith("R_") or b.name in ("Lance", "Shield")
        if not b.use_deform:
            col = (255, 0, 255)
        elif rider:
            col = (40, 90, 255) if not b.name.endswith(".R") else (20, 40, 150)
        else:
            col = (255, 60, 40) if not b.name.endswith(".R") else (150, 20, 10)
        out.append([b.name, list(h), list(t), col])
    return out
