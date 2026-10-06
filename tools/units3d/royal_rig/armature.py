"""Phase 3C: the custom armature `royal_rig` for the king on his horse, from MEASURED joints
(Phase 2). Frame (Gate 1): the piece faces -Y, its left is +X, hooves on z = 0, metres.

How each landmark was found (see the skill's Phase 2):
  * horse legs -- 2.5 cm horizontal slices per leg quadrant on the full-res mesh: hoof =
    the ground slice's centroid, fetlock / knee (carpus) / hock = the width minima and bulges
    along the leg (front: cannon narrowest at z 0.30-0.35, carpus bulge 0.45-0.55; hind:
    cannon 0.23-0.40, hock bulge 0.50-0.60), centroids at those heights;
  * elbow, point of shoulder, stifle, hip, scapula top, spine depth, poll -- read off the
    gridded x-ray orthographic renders (shots/grid_side_g.png, grid_front_g.png), cross-checked
    against the top / bottom line profile of the mount-labelled vertices (barrel 0.82-1.52 at
    the croup: the spine 25 % of that below the top line);
  * tail -- the centroid of the tail part every 10 cm;
  * rider -- the Tripo parts: elbows / wrists / ankles at the junctions between neighbouring
    parts (17|16, 26|11, 16|27, 13|22, 20|21), knees between the poleyn's centroid and its
    junction with the greave, the hands and toes at the parts' far ends, the spine on the
    torso part's section centroids.
"""

V = Vector

HORSE_LEGS = {   # side: x sign, then the joints top to bottom
    "L": {"front": [(0.10, -0.25, 1.45), (0.145, -0.55, 1.12), (0.155, -0.34, 0.82),
                    (0.142, -0.30, 0.48), (0.137, -0.296, 0.16), (0.150, -0.345, 0.0)],
          "hind": [(0.16, 0.90, 1.25), (0.17, 0.82, 0.93), (0.160, 0.985, 0.56),
                   (0.165, 1.010, 0.16), (0.186, 0.960, 0.0)]},
    "R": {"front": [(-0.10, -0.25, 1.45), (-0.145, -0.56, 1.12), (-0.150, -0.35, 0.82),
                    (-0.134, -0.32, 0.48), (-0.130, -0.320, 0.16), (-0.134, -0.370, 0.0)],
          "hind": [(-0.16, 0.88, 1.25), (-0.17, 0.80, 0.92), (-0.155, 0.957, 0.50),
                   (-0.159, 0.930, 0.17), (-0.169, 0.866, 0.0)]},
}
SPINE = [(0.0, 0.35, 1.35), (0.0, 0.0, 1.37), (0.0, -0.30, 1.38), (0.0, -0.40, 1.44)]
NECK = [(0.0, -0.40, 1.44), (0.02, -0.62, 1.58), (0.04, -0.86, 1.80)]
MUZZLE = (0.09, -1.20, 1.40)
TAIL = [(-0.035, 1.04, 1.44), (-0.03, 1.13, 1.25), (-0.03, 1.13, 0.95), (-0.04, 1.14, 0.65), (-0.05, 1.14, 0.30)]
PELVIS_TAIL = (0.0, 1.02, 1.42)

SEAT = (0.0, 0.17, 1.47)
RIDER_SPINE = [(0.0, 0.17, 1.47), (0.0, 0.17, 1.60), (0.0, 0.19, 1.80), (0.0, 0.22, 2.06), (0.0, 0.20, 2.17)]
RIDER_HEAD_TOP = (0.0, 0.18, 2.45)
RIDER_ARMS = {   # clavicle root, shoulder, elbow, wrist, hand tip
    "L": [(0.04, 0.21, 2.03), (0.25, 0.20, 1.99), (0.271, 0.144, 1.82), (0.150, -0.120, 1.71), (0.102, -0.186, 1.692)],
    "R": [(-0.04, 0.21, 2.03), (-0.25, 0.20, 1.99), (-0.298, 0.136, 1.814), (-0.244, -0.112, 1.745), (-0.175, -0.200, 1.715)],
}
RIDER_LEGS = {   # hip, knee, ankle, toe
    "L": [(0.12, 0.17, 1.48), (0.388, -0.030, 1.29), (0.391, -0.059, 0.886), (0.475, -0.280, 0.837)],
    "R": [(-0.12, 0.17, 1.48), (-0.395, -0.035, 1.29), (-0.388, -0.063, 0.877), (-0.471, -0.307, 0.833)],
}
SWORD = [(-0.193, -0.167, 1.725), (-0.228, -0.605, 2.496)]   # the grip (the fist's centre) and the tip


def build():
    old = bpy.data.objects.get("royal_rig")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    arm = bpy.data.armatures.new("royal_rig")
    rig = bpy.data.objects.new("royal_rig", arm)
    coll("Royal_Rig").objects.link(rig)
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
    # the rider rides a non-deform Saddle on the mount's mid-spine
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
    g, tip = V(SWORD[0]), V(SWORD[1])
    B("Sword", g, g + (tip - g).normalized() * 0.35, "R_Hand.R")
    # the reins' hand end: a bone that never turns, keyed each pose onto the rein hand's place
    # (skinned to the turning hand, the far rein ends swung a metre out when he dismounted)
    rh = V(RIDER_ARMS["L"][3])
    B("Reins", rh, rh + V((0, 0, 0.1)), "root")
    # roll: mostly horizontal bones about +Z, mostly vertical about -Y, so bends are about local X
    for b in eb:
        d = (b.tail - b.head).normalized()
        b.align_roll(V((0, 0, 1)) if abs(d.z) < 0.7 else V((0, -1, 0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    # one bone collection per character
    cols = {n: arm.collections.new(n) for n in ("Horse", "Rider", "Props")}
    for b in arm.bones:
        k = "Rider" if b.name.startswith("R_") or b.name == "Saddle" else "Props" if b.name in ("Sword", "Reins") else "Horse"
        cols[k].assign(b)
    rig.show_in_front = True
    arm.display_type = "STICK"
    return {"bones": len(arm.bones), "deform": sum(1 for b in arm.bones if b.use_deform)}


def bone_lines():
    """[name, head, tail, colour] for the Gate 3 overlay: horse red (.R darker), rider blue
    (.R darker), non-deform magenta."""
    rig = bpy.data.objects["royal_rig"]
    out = []
    for b in rig.data.bones:
        h = rig.matrix_world @ b.head_local
        t = rig.matrix_world @ b.tail_local
        rider = b.name.startswith("R_") or b.name == "Sword"
        if not b.use_deform:
            col = (255, 0, 255)
        elif rider:
            col = (40, 90, 255) if not b.name.endswith(".R") else (20, 40, 150)
        else:
            col = (255, 60, 40) if not b.name.endswith(".R") else (150, 20, 10)
        out.append([b.name, list(h), list(t), col])
    return out
