"""Phase 5: numeric gates, the stretch metric over test poses, the weight map and test-pose shots."""
import math
from mathutils import Euler

TEST_POSES = {   # name -> [(bone, (x, y, z) local Euler degrees) | (bone, "loc", (x, y, z))]
    # on these bones +X swings the far end FORWARD (-Y), +Z out to the side (rolls: armature.py)
    "arm_raise": [("UpperArm.R", (85, 0, 0)), ("Forearm.R", (80, 0, 0)), ("UpperArm.L", (50, 0, 0)), ("Forearm.L", (40, 0, 0))],
    "knee": [("Thigh.L", (60, 0, 0)), ("Shin.L", (-85, 0, 0)), ("Thigh.R", (-25, 0, 0)), ("Shin.R", (-30, 0, 0))],
    "twist": [("Spine", (0, 15, 0)), ("Chest", (0, 15, 0)), ("head", (0, 40, 0))],
    "draw": [("String", "loc", (0, 0.45, 0)), ("BowLimb.U", (-8, 0, 0)), ("BowLimb.D", (8, 0, 0))],
}


def numeric():
    o = mesh()
    names = {g.index: g.name for g in o.vertex_groups}
    deform = {b.name for b in rig().data.bones if b.use_deform}
    zero = over4 = unnorm = 0
    for v in o.data.vertices:
        ws = [g.weight for g in v.groups if names[g.group] in deform and g.weight > 0]
        if not ws:
            zero += 1
        if len(ws) > 4:
            over4 += 1
        if ws and abs(sum(ws) - 1) > 0.02:
            unnorm += 1
    return {"zero": zero, "over4": over4, "unnormalised": unnorm, "verts": len(o.data.vertices)}


def set_pose(entries):
    a = rig()
    for pb in a.pose.bones:
        pb.rotation_mode = "XYZ"; pb.rotation_euler = (0, 0, 0); pb.location = (0, 0, 0)
    for e in entries:
        if e[1] == "loc":
            PB(a)[e[0]].location = e[2]
        else:
            PB(a)[e[0]].rotation_euler = Euler([math.radians(x) for x in e[1]])
    bpy.context.view_layer.update()


def _edges(o):
    E = np.empty(len(o.data.edges) * 2, int)
    o.data.edges.foreach_get("vertices", E)
    return E.reshape(-1, 2)


def stretched(entries, k=4.0, floor=0.03):
    o = mesh()
    E = _edges(o)
    P0 = co(o)
    set_pose(entries)
    dg = bpy.context.evaluated_depsgraph_get()
    me = o.evaluated_get(dg).to_mesh()
    P1 = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P1); P1 = P1.reshape(-1, 3)
    o.evaluated_get(dg).to_mesh_clear()
    l0 = np.linalg.norm(P0[E[:, 0]] - P0[E[:, 1]], axis=1)
    l1 = np.linalg.norm(P1[E[:, 0]] - P1[E[:, 1]], axis=1)
    bad = (l1 > k * np.maximum(l0, 1e-6)) & (l1 > floor)
    set_pose([])
    return int(bad.sum()), E[bad]


def stretch_table():
    return {n: stretched(p)[0] for n, p in TEST_POSES.items()}


def pose_shots(prefix, views=(("q", (0.6, 1, -0.25)), ("s", (1, 0.05, -0.1)))):
    o = mesh()
    out = []
    for n, p in TEST_POSES.items():
        set_pose(p)
        for vn, look in views:
            path = "%s%s_%s.png" % (prefix, n, vn)
            shot(path, (0.05, -0.05, 0.95), look, 2.1, res=480, objs=[o])
            out.append(path)
    set_pose([])
    return out


def weight_map(prefix):
    o = mesh()
    names = [g.name for g in o.vertex_groups]
    n = len(names)
    pal = np.array([[(0.5 + 0.5 * math.cos(2 * math.pi * (i * 0.618 + c / 3))) for c in range(3)] for i in range(n)])
    W = np.zeros((len(o.data.vertices), n))
    for v in o.data.vertices:
        for g in v.groups:
            W[v.index, g.group] = g.weight
    C = W @ pal
    ca = o.data.color_attributes.get("wmap") or o.data.color_attributes.new("wmap", "FLOAT_COLOR", "POINT")
    ca.data.foreach_set("color", np.c_[C, np.ones(len(C))].ravel())
    o.data.color_attributes.active_color = ca
    for vn, look in (("front", (0.3, 1, -0.1)), ("back", (-0.3, -1, -0.1))):
        shot(prefix + vn + ".png", (0.05, 0, 0.92), look, 2.0, res=600, objs=[o], color="VERTEX")


# ---- the clips (blender-natural-animation Phase 6) ----
END = {"Foot.L": True, "Foot.R": True, "Hand.L": True, "Hand.R": True, "head": True, "BowLimb.U": True}


def clip_metrics(name, belt=None):
    """Per clip: loop closure (max bone matrix difference, frame 0 vs N), the worst single-frame
    turn of any bone (deg), jerk spike ratio per end effector, ground penetration of the toes and,
    for an in-place run, the stance toes' slip against the belt speed `belt` (m/frame)."""
    a = rig()
    act = bpy.data.actions[PREFIX + name]
    a.animation_data_create(); a.animation_data.action = act
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    sc = bpy.context.scene
    mats, pos = [], {b: [] for b in END}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        mats.append({pb.name: pb.matrix.copy() for pb in a.pose.bones})
        for b in END:
            pb = PB(a)[b]
            pos[b].append(np.array(pb.tail if END[b] else pb.head))
    loop = max(max(abs(x - y) for rx, ry in zip(mats[0][n], mats[-1][n]) for x, y in zip(rx, ry)) for n in mats[0])
    jump, worst = 0.0, ""
    for i in range(1, len(mats)):
        for n in mats[i]:
            d = math.degrees(mats[i][n].to_quaternion().rotation_difference(mats[i - 1][n].to_quaternion()).angle)
            d = min(d, 360 - d)
            if d > jump and n not in ("Arrow",):
                jump, worst = d, "%s@%d" % (n, i)
    jerk = {}
    for b, p in pos.items():
        p = np.array(p)
        j = np.linalg.norm(np.diff(p, n=3, axis=0), axis=1)
        jerk[b] = (round(float(j.max() / (np.median(j) + 1e-6)), 1), round(float(j.max()) * 1000, 1))   # ratio, mm/f^3
    toes = {s: np.array(pos["Foot." + s]) for s in "LR"}
    pen = round(float(-min(0.0, min(t[:, 2].min() for t in toes.values()))), 4)
    out = {"loop": round(loop, 4), "max_turn_deg": round(jump, 1), "at": worst, "jerk": jerk, "toe_penetration_m": pen}
    if belt:
        slip = []
        for s, t in toes.items():
            v = np.diff(t, axis=0)
            planted = (t[:-1, 2] < 0.045) & (t[1:, 2] < 0.045)
            if planted.any():
                slip.append(float(np.abs(np.linalg.norm(v[planted][:, :2], axis=1) - belt).max()))
        out["stance_slip_m_per_f"] = round(max(slip), 4) if slip else None
    a.animation_data.action = None
    return out


def limb_twist(name, chains=(("UpperArm.L", "Forearm.L", "Hand.L"), ("UpperArm.R", "Forearm.R", "Hand.R"))):
    """Per clip, the worst twist (deg) of each forearm against its upper arm and of each hand against
    its forearm, about the lower bone's own axis, measured from the rest relation (swing-twist): a
    twisted wrist or a candy-wrapper elbow shows here before it shows on the mesh."""
    a = rig()
    act = bpy.data.actions[PREFIX + name]
    ad = a.animation_data or a.animation_data_create()
    held = ad.action
    ad.action = act
    B = DB(a)
    out = {}
    for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1):
        bpy.context.scene.frame_set(f)
        for chain in chains:
            for up, lo in zip(chain, chain[1:]):
                rel = PB(a)[up].matrix.to_3x3().inverted() @ PB(a)[lo].matrix.to_3x3()
                rel0 = B[up].matrix_local.to_3x3().inverted() @ B[lo].matrix_local.to_3x3()
                q = (rel0.inverted() @ rel).to_quaternion()          # in the lower bone's rest frame
                tw = math.degrees(2 * math.atan2(q.y, q.w))
                tw = (tw + 180) % 360 - 180
                k = "%s>%s" % (up, lo)
                if abs(tw) > abs(out.get(k, (0, 0))[0]):
                    out[k] = (round(tw, 1), f)
    ad.action = held
    return out


def clearance(name, step=1, parts=("bow", "string", "quiver")):
    """Per clip, the closest any prop vertex comes to the body (m), and where: the bow and string
    beyond the fist (16 cm off the left wrist), the quiver itself."""
    from mathutils.kdtree import KDTree
    a = rig(); o = mesh()
    act = bpy.data.actions[PREFIX + name]
    ad = a.animation_data or a.animation_data_create()
    held = ad.action; ad.action = act
    part = np.empty(len(o.data.vertices), np.int32)
    o.data.attributes["part"].data.foreach_get("value", part)
    body = np.nonzero(part == PARTS.index("body"))[0]
    out = {}
    for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1, step):
        bpy.context.scene.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get(); me = o.evaluated_get(dg).to_mesh()
        P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
        o.evaluated_get(dg).to_mesh_clear()
        kd = KDTree(len(body))
        for i, k in enumerate(body):
            kd.insert(P[k], i)
        kd.balance()
        hand = np.array(PB(a)["Hand.L"].head)
        for pn in parts:
            sel = np.nonzero(part == PARTS.index(pn))[0]
            if pn != "quiver":
                sel = sel[np.linalg.norm(P[sel] - hand, axis=1) > 0.16]
            d = min((kd.find(P[k])[2], f) for k in sel[::2])
            if pn not in out or d[0] < out[pn][0]:
                out[pn] = (round(d[0], 3), d[1])
    ad.action = held
    return out
