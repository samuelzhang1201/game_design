"""Phase 3C: the courier's armature `courier_rig`, the cavalry's bone set (the skill's horse template,
`Saddle` -> the R_ rider, five tail bones) with the herald's own props: `Pole` the staff in his right
fist, `Pennon1` / `Pennon2` the pennant hanging from its head, `Case` the dispatch case on the near
side of the saddle, `Reins.L` / `Reins.R` the two reins' hand ends (one rein runs to each hand: the
right fist holds the staff and its rein together).
Frame (Gate 1): faces -Y, left +X, hooves on z = 0, metres.

How each joint was measured (shots/legs_side_g.png, grid_side_g.png, grid_front_g.png):
  * horse legs -- 5 cm slices of each leg's own Tripo part (off fore 8, near fore 4 + 19, off hind 6,
    near hind 1 at x > -0.02): hoof, fetlock (the narrowest slice above it), carpus / hock centroids;
    elbow, point of shoulder, stifle and hip read off the leg-coloured gridded x-ray side render.
    The mesh walks: the near fore is raised (knee forward, hoof folded back), the off hind swings
    forward with its toe 5 cm up -- the bones follow the legs as they are;
  * spine -- 25 % of the barrel (0.75-1.33) below the top line; neck and head through the poll
    (under the ears) to the muzzle part's tip (the head is turned a little to its left);
  * tail -- the tail part's centroid every 6 cm;
  * rider -- the coat's sections (torso +-0.25 m to 1.88; shoulders at the gold pieces), the
    outer-arm slices for the elbows, the cuffs and hand parts for the wrists; thighs / boots from
    their parts; the staff's own axis (its part's end points, extended to the finial at 2.56).
"""

V = Vector

HORSE_LEGS = {   # front: scapula top, point of shoulder, elbow, carpus, fetlock, hoof sole
                 # hind: hip, stifle, hock, fetlock, hoof sole
    "L": {"front": [(0.09, -0.36, 1.33), (0.19, -0.68, 1.06), (0.17, -0.58, 0.80),
                    (0.185, -0.89, 0.59), (0.175, -0.855, 0.40), (0.14, -0.73, 0.18)],
          "hind": [(0.12, 0.60, 1.10), (0.12, 0.48, 0.84), (0.07, 0.76, 0.55),
                   (0.047, 0.805, 0.23), (0.046, 0.73, 0.0)]},
    "R": {"front": [(-0.07, -0.36, 1.33), (-0.11, -0.68, 1.06), (-0.07, -0.46, 0.80),
                    (-0.04, -0.49, 0.48), (-0.02, -0.465, 0.22), (-0.005, -0.545, 0.0)],
          "hind": [(-0.11, 0.60, 1.10), (-0.10, 0.27, 0.85), (-0.06, 0.41, 0.53),
                   (-0.02, 0.155, 0.22), (-0.007, 0.08, 0.05)]},
}
SPINE = [(0.0, 0.42, 1.16), (0.0, 0.02, 1.19), (0.0, -0.30, 1.22), (0.0, -0.48, 1.28)]
NECK = [(0.0, -0.48, 1.28), (0.03, -0.74, 1.50), (0.06, -0.99, 1.68)]
MUZZLE = (0.09, -1.19, 1.31)
TAIL = [(-0.03, 0.64, 1.29), (-0.06, 0.74, 1.17), (-0.07, 0.83, 1.03), (-0.075, 0.91, 0.86),
        (-0.078, 0.97, 0.68), (-0.06, 1.15, 0.47)]
PELVIS_TAIL = (0.0, 0.66, 1.26)

SEAT = (0.02, -0.03, 1.36)
RIDER_SPINE = [(0.02, -0.03, 1.36), (0.02, -0.05, 1.52), (0.02, -0.07, 1.66), (0.02, -0.10, 1.86), (0.02, -0.11, 1.97)]
RIDER_HEAD_TOP = (0.02, -0.10, 2.17)
RIDER_ARMS = {   # clavicle root, shoulder, elbow, wrist, hand tip
    "L": [(0.05, -0.08, 1.80), (0.19, -0.07, 1.79), (0.21, -0.12, 1.49), (0.14, -0.31, 1.50), (0.09, -0.42, 1.48)],
    "R": [(-0.01, -0.09, 1.80), (-0.16, -0.10, 1.79), (-0.19, -0.14, 1.49), (-0.09, -0.35, 1.57), (-0.02, -0.44, 1.60)],
}
RIDER_LEGS = {   # hip, knee, ankle, toe
    "L": [(0.13, -0.04, 1.33), (0.325, -0.33, 1.18), (0.335, -0.28, 0.87), (0.41, -0.45, 0.79)],
    "R": [(-0.09, -0.02, 1.33), (-0.275, -0.34, 1.18), (-0.29, -0.29, 0.87), (-0.355, -0.46, 0.79)],
}
POLE = [(-0.046, -0.41, 1.60), (-0.02, -0.575, 2.56)]          # the grip (on the staff's axis) and the finial
PENNON = [(-0.03, -0.555, 2.44), (-0.03, -0.56, 2.24), (-0.03, -0.56, 2.02)]   # hanging from the staff's head
CASE = [(0.26, 0.0, 1.43), (0.26, 0.0, 1.25)]                  # the hinge at its top, down its face

PROPS = ("Pole", "Pennon1", "Pennon2", "Case", "Reins.L", "Reins.R")


def build():
    old = bpy.data.objects.get(RIG_NAME)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    arm = bpy.data.armatures.new(RIG_NAME)
    rig = bpy.data.objects.new(RIG_NAME, arm)
    coll("Courier_Rig").objects.link(rig)
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
    for i in range(len(TAIL) - 1):
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
    B("Pole", POLE[0], POLE[1], "R_Hand.R")
    B("Pennon1", PENNON[0], PENNON[1], "Pole")
    B("Pennon2", PENNON[1], PENNON[2], "Pennon1", True)
    B("Case", CASE[0], CASE[1], "Spine1")
    for s in "LR":
        w = V(RIDER_ARMS[s][3])
        B("Reins." + s, w, w + V((0, 0, 0.1)), "root")
    for b in eb:
        d = (b.tail - b.head).normalized()
        b.align_roll(V((0, 0, 1)) if abs(d.z) < 0.7 else V((0, -1, 0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    cols = {n: arm.collections.new(n) for n in ("Horse", "Rider", "Props")}
    for b in arm.bones:
        k = "Rider" if b.name.startswith("R_") or b.name == "Saddle" else "Props" if b.name in PROPS else "Horse"
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
        rider = b.name.startswith("R_") or b.name in ("Pole", "Pennon1", "Pennon2")
        if not b.use_deform:
            col = (255, 0, 255)
        elif rider:
            col = (40, 90, 255) if not b.name.endswith(".R") else (20, 40, 150)
        else:
            col = (255, 60, 40) if not b.name.endswith(".R") else (150, 20, 10)
        out.append([b.name, list(h), list(t), col])
    return out
