"""Phase 5: the numeric gates, the stretch metric over a test-pose set, the weight map.
Exec after common, labels, weights."""
import math
from mathutils import Euler

GOLD = 0.618033988749895


def numeric():
    o = mesh()
    names = {g.index: g.name for g in o.vertex_groups}
    region, anchor = read_int(o, "region"), read_int(o, "anchor")
    zero = over4 = unnorm = leak = 0
    for v in o.data.vertices:
        ws = [(names[g.group], g.weight) for g in v.groups if g.weight > 1e-6]
        s = sum(w for _, w in ws)
        if not ws:
            zero += 1
        if len(ws) > 4:
            over4 += 1
        if ws and abs(s - 1) > 0.02:
            unnorm += 1
        if region[v.index] == RIDER and anchor[v.index] < 0 and any(not is_rider_bone(n) for n, _ in ws):
            leak += 1
    return {"zero_weight": zero, "over_4": over4, "not_normalised": unnorm, "cross_region_leak": leak}


POSES = {   # name: {bone: (x, y, z) degrees}
    "front_leg_lift": {"FrontUpperArm.L": (-35, 0, 0), "FrontForearm.L": (80, 0, 0), "FrontCannon.L": (-30, 0, 0)},
    "hind_leg_flex": {"HindThigh.R": (25, 0, 0), "HindShin.R": (-40, 0, 0), "HindCannon.R": (35, 0, 0)},
    "head_down": {"Neck1": (-35, 0, 0), "Neck2": (-25, 0, 0), "Head": (-20, 0, 0)},
    "neck_turn": {"Neck1": (0, 0, 20), "Neck2": (0, 0, 15)},
    "tail_swing": {"Tail1": (0, 0, 25), "Tail2": (0, 0, 20)},
    "back_bend": {"Spine1": (8, 0, 0), "Spine2": (8, 0, 0)},
    "arm_raise": {"R_UpperArm.R": (0, 0, -70), "R_Forearm.R": (-60, 0, 0)},
    "elbow": {"R_Forearm.L": (-80, 0, 0)},
    "torso_twist": {"R_Spine": (0, 0, 15), "R_Chest": (0, 0, 10)},
    "head_turn": {"R_Head": (0, 0, 40)},
    "knee": {"R_Shin.L": (40, 0, 0)},
}


def set_pose(entries):
    arm = rig()
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"       # the clips key quaternions: never leave a bone on Euler
        pb.matrix_basis.identity()
    for n, (x, y, z) in entries.items():
        pb = arm.pose.bones[n]
        pb.rotation_quaternion = Euler((math.radians(x), math.radians(y), math.radians(z))).to_quaternion()
    bpy.context.view_layer.update()


def stretched(pose=None, k=4.0, floor=0.03):
    """Edges longer than k x rest and longer than `floor` metres in the evaluated mesh."""
    if pose is not None:
        set_pose(POSES[pose] if isinstance(pose, str) else pose)
    o = mesh()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    n = len(me.vertices)
    A = np.empty(n * 3); me.vertices.foreach_get("co", A); A = A.reshape(n, 3)
    ev.to_mesh_clear()
    R = co(o)
    E = np.array([e.vertices[:] for e in o.data.edges])
    rest = np.linalg.norm(R[E[:, 0]] - R[E[:, 1]], axis=1)
    now = np.linalg.norm(A[E[:, 0]] - A[E[:, 1]], axis=1)
    bad = (now > k * np.maximum(rest, 1e-6)) & (now > floor)
    return int(bad.sum()), E[bad]


def stretch_table():
    out = {}
    for p in POSES:
        out[p] = stretched(p)[0]
    set_pose({})
    return out


def stretch_causes(pose, top=8):
    """The stretched edges of a pose grouped by (part, part) with the ends' top bones."""
    n, E = stretched(pose)
    o = mesh()
    lab = read_int(o, "part")
    names = {g.index: g.name for g in o.vertex_groups}
    def top_b(i):
        ws = sorted(((g.weight, names[g.group]) for g in o.data.vertices[i].groups), reverse=True)
        return ws[0][1] if ws else None
    agg = {}
    for a, b in E:
        key = (int(lab[a]), int(lab[b]), top_b(a), top_b(b))
        agg[key] = agg.get(key, 0) + 1
    set_pose({})
    return sorted(agg.items(), key=lambda kv: -kv[1])[:top]


def weight_map():
    """Each vertex coloured W @ palette (one golden-ratio hue per bone)."""
    import colorsys
    o = mesh()
    gs = list(o.vertex_groups)
    pal = np.array([colorsys.hsv_to_rgb((k * GOLD) % 1.0, 0.75, 0.95) for k in range(len(gs))])
    cols = np.zeros((len(o.data.vertices), 3))
    for v in o.data.vertices:
        for g in v.groups:
            cols[v.index] += g.weight * pal[g.group]
    return paint(np.clip(cols, 0, 1), "weight_col")
