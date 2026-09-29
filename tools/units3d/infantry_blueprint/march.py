"""MARCH from real motion capture (owner 2026-09-28: 走路动作太像一个机器人了，双腿
弯曲程度不自然。双手摆动也不自然，要真实双手可以自然下垂，身体随走路动作自然晃动).
One cycle of CMU 02_01 (walk_02_01.json, by mocap_extract.py) drives `inf_rig`:
the pelvis's bob, sway, turn and roll, the chest's counter-turn, each ankle's
path (scaled to this soldier's legs, the knee solved by two-bone IK so it
bends straight forward), the foot's pitch, and each arm's swing and elbow.
The arms HANG: the right carries the spear low, the wrist cocked so the tip
leans a little forward; the left carries the shield hanging along it. The
cycle stays in place (the game moves the piece). 32 frames at 30 fps.
    exec(open(".../march.py").read(), {})
"""
import bpy, json, math
from mathutils import Vector, Matrix, Quaternion

HERE = "/Users/samuelzhang/game_design/tools/units3d/infantry_blueprint/"
R = {}
exec(open(HERE + "rig.py").read().split("\nrig = build_rig()")[0], R)
DATA = json.load(open(HERE + "walk_02_01.json"))
FR = DATA["frames"]
N = 32
ANK_Z = R["ANKLE"].z
TOE_DOWN_MAX = math.radians(35)
HIP_LIFT = globals().get("HIP_LIFT", 0.022)  # the pelvis higher than the take's ratio, the feet where they were:
                                             # this soldier's long thigh bent the stance knee ~30 deg
TORSO = globals().get("TORSO", 1.0)          # the take's pelvis / chest turn and roll, x this
SWAY = globals().get("SWAY", 1.0)            # the take's side-to-side, x this
KIT = {  # side: (upper arm forward, elbow, abduction, wrist, swing scale, elbow swing scale)
    "R": (8.0, 34.0, 4.0, 30.0, 0.7, 0.45),     # the spear hand, hanging a little off the body
    "L": (4.0, 14.0, 4.0, 0.0, 0.7, 0.45),      # the shield arm, hanging and swinging with the walk
}

rig = bpy.data.objects["inf_rig"]
pb = rig.pose.bones
REST = {b.name: b.matrix_local.copy() for b in rig.data.bones}

# owner 2026-09-29: 走路的时候，长矛应该扛在肩上，茅尖指向斜后上方. The right fist holds the
# shaft before the right shoulder, the shaft laid over the pauldron, its tip up and behind, its
# butt down in front; both points ride the chest, so the spear sways with the body.
SHOULDER = globals().get("SHOULDER", True)
SH_GRIP = Vector(globals().get("SH_GRIP", (-0.215, -0.255, 1.225)))   # the fist, at rest (chest frame): before the pauldron's front wing
SH_REST = Vector(globals().get("SH_REST", (-0.210, 0.030, 1.620)))    # where the shaft lies on the pauldron (4 mm clear, measured)
SH_SLIDE = globals().get("SH_SLIDE", 0.32)   # the spear slid back through the fist: its butt ~0.45 m before it
SH_POLE = Vector((-0.55, 0.15, -1.0))        # the elbow down, out and a touch back


def _spear_axis():
    """The spear mesh's own axis at rest, butt -> tip (it is the fist's grip channel)."""
    sp = bpy.data.objects["inf_spear"]
    vs = [v.co.copy() for v in sp.data.vertices]
    ax = max(((a - b) for a in vs[:40] for b in vs[-40:]), key=lambda d: d.length).normalized()
    return ax if ax.z > 0 else -ax


A_REST = _spear_axis()
HB_REST = (REST["hand.R"] @ Vector((0, 1, 0)) - REST["hand.R"].translation).normalized()


def frame(a, b):
    """An orthonormal frame whose first axis is a and whose second lies toward b."""
    a = a.normalized()
    b = (b - a * b.dot(a)).normalized()
    return Matrix((a, b, a.cross(b))).transposed()


def ik(H, T, l1, l2, pole):
    d = T - H
    dl = min(d.length, (l1 + l2) * 0.999)
    u = d.normalized()
    a = (l1 * l1 - l2 * l2 + dl * dl) / (2 * dl)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    w = (pole - u * pole.dot(u)).normalized()
    return H + u * a + w * h
L1 = (R["KNEE"] - R["HIP"]).length
L2 = (R["ANKLE"] - R["KNEE"]).length
K = (L1 + L2) / DATA["leg"]
V = lambda a: Vector(a)


def rot(axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, axis)


def sample(t):
    """The take's frame data at cycle time t (0..1), linearly between its samples."""
    x = (t % 1.0) * len(FR)
    i = int(math.floor(x)) % len(FR)
    j = (i + 1) % len(FR)
    w = x - math.floor(x)
    out = {}
    for k in FR[0]:
        a, b = V(FR[i][k]), V(FR[j][k])
        out[k] = a.lerp(b, w)
    return out


def swing_of(u):
    """An arm segment's angle forward of hanging straight down, in the sagittal plane."""
    return math.degrees(math.atan2(-u.y, -u.z))


MEAN = {}
for sd in ("L", "R"):
    MEAN["sw_" + sd] = sum(swing_of(V(f["arm_" + sd])) for f in FR) / len(FR)
    MEAN["el_" + sd] = sum(math.degrees(V(f["arm_" + sd]).angle(V(f["fore_" + sd]))) for f in FR) / len(FR)
    MEAN["ax_" + sd] = sum(f["ank_" + sd][0] for f in FR) / len(FR)


# the take's flat foot: its pitch when that ankle is lowest
FLAT = {}
for sd in ("L", "R"):
    low = min(FR, key=lambda f: f["hip"][2] + f["ank_" + sd][2])
    t_ = V(low["toe_" + sd])
    FLAT[sd] = math.atan2(t_.z, Vector((t_.x, t_.y)).length)


def two_bone(H, A, fwd):
    d = A - H
    dl = min(d.length, (L1 + L2) * 0.9995)
    u = d.normalized()
    a = (L1 * L1 - L2 * L2 + dl * dl) / (2 * dl)
    h = math.sqrt(max(0.0, L1 * L1 - a * a))
    w = fwd - u * fwd.dot(u)
    w.normalize()
    return H + u * a + w * h, H + u * dl


def turn(axis_rest, now, k):
    """The rotation taking axis_rest to `now`, scaled by k."""
    q = axis_rest.rotation_difference(now)
    ax, ang = q.to_axis_angle()
    return Quaternion(ax, ang * k).to_matrix()


def pose(t):
    M = {}
    s = sample(t)
    rest_h = REST["hips"].translation

    def put(name, Rw, head):
        M[name] = Matrix.Translation(head) @ (Rw @ REST[name].to_3x3()).to_4x4()

    hip = s["hip"]
    hips_head = Vector((hip.x * K * SWAY, rest_h.y + hip.y * K, ANK_Z + (DATA["hip_h"] + hip.z) * K + HIP_LIFT))
    Rh = turn(Vector((1, 0, 0)), s["pelvis"], TORSO)
    put("hips", Rh, hips_head)
    Rchest = turn(Vector((1, 0, 0)), s["chest"], TORSO)
    Rs = Quaternion().slerp(Rh.to_quaternion(), 0.5).to_matrix() @ Quaternion().slerp(Rchest.to_quaternion(), 0.5).to_matrix()
    spine_head = hips_head + Rh @ (REST["spine"].translation - rest_h)
    put("spine", Rs, spine_head)
    chest_head = spine_head + Rs @ (REST["chest"].translation - REST["spine"].translation)
    put("chest", Rchest, chest_head)
    neck_head = chest_head + Rchest @ (REST["neck"].translation - REST["chest"].translation)
    Rn = Quaternion().slerp(Rchest.to_quaternion(), 0.4).to_matrix()
    put("neck", Rn, neck_head)
    head_head = neck_head + Rn @ (REST["head"].translation - REST["neck"].translation)
    put("head", Matrix.Identity(3), head_head)            # the head stays level, looking ahead
    for sd in ("L", "R"):
        up0, el0, abd, wrist, ks, ke = KIT[sd]
        sw = swing_of(s["arm_" + sd]) - MEAN["sw_" + sd]
        el = math.degrees(s["arm_" + sd].angle(s["fore_" + sd])) - MEAN["el_" + sd]
        up = up0 + sw * ks
        e = max(0.0, el0 + el * ke)
        cl = "clavicle." + sd
        cl_head = chest_head + Rchest @ (REST[cl].translation - REST["chest"].translation)
        put(cl, Rchest, cl_head)
        ua, fa, hd = "upperarm." + sd, "forearm." + sd, "hand." + sd
        ua_head = cl_head + Rchest @ (REST[ua].translation - REST[cl].translation)
        Rab = Rchest @ rot("Y", abd if sd == "L" else -abd)
        Rua = Rab @ rot("X", -up)
        put(ua, Rua, ua_head)
        fa_head = ua_head + Rua @ (REST[fa].translation - REST[ua].translation)
        Rfa = Rab @ rot("X", -(up + e))
        put(fa, Rfa, fa_head)
        hd_head = fa_head + Rfa @ (REST[hd].translation - REST[fa].translation)
        if sd == "R" and SHOULDER:
            to_w = lambda v: chest_head + Rchest @ (v - REST["chest"].translation)
            G, Pn = to_w(SH_GRIP), to_w(SH_REST)
            d = (Pn - G).normalized()
            l1 = (REST[fa].translation - REST[ua].translation).length
            l2 = (REST[hd].translation - REST[fa].translation).length + 0.058
            E = ik(ua_head, G, l1, l2, Rchest @ SH_POLE)
            Rua = (REST[fa].translation - REST[ua].translation).normalized().rotation_difference((E - ua_head).normalized()).to_matrix()
            put(ua, Rua, ua_head)
            fdir = (G - E).normalized()
            r_fa = (REST[hd].translation - REST[fa].translation).normalized()
            Rfa = (Rua @ r_fa).rotation_difference(fdir).to_matrix() @ Rua
            put(fa, Rfa, E)
            Rhd = frame(d, fdir) @ frame(A_REST, HB_REST).transposed()
            put(hd, Rhd, G - fdir * 0.058)
            M["spear"] = Matrix.Translation(d * SH_SLIDE) @ M[hd] @ REST[hd].inverted() @ REST["spear"]
        elif sd == "R":
            # the spear keeps its lean: the wrist takes up the arm's swing, a little sway left
            put(hd, rot("Y", -abd) @ rot("X", -(up0 + el0 + wrist)), hd_head)      # one steady lean
        else:
            put(hd, Rab @ rot("X", -(up + e + wrist)), hd_head)
        # the leg
        th, sh, ft = "thigh." + sd, "shin." + sd, "foot." + sd
        H = hips_head + Rh @ (REST[th].translation - rest_h)
        a = s["ank_" + sd]
        A = Vector((H.x + (a.x - MEAN["ax_" + sd]) * K + (REST[ft].translation.x - REST[th].translation.x),
                    H.y + a.y * K, H.z + a.z * K - HIP_LIFT))
        A.z = max(A.z, ANK_Z)
        Kn, A = two_bone(H, A, Vector((0, -1, 0)))
        r_th = (REST[sh].translation - REST[th].translation).normalized()
        Rth = r_th.rotation_difference((Kn - H).normalized()).to_matrix()
        put(th, Rth, H)
        r_sh = (REST[ft].translation - REST[sh].translation).normalized()
        Rsh = (Rth @ r_sh).rotation_difference((A - Kn).normalized()).to_matrix() @ Rth
        put(sh, Rsh, Kn)
        # the foot's pitch RELATIVE to the take's own flat foot, on this soldier's flat foot
        toe = s["toe_" + sd]
        r_ft = (R["TOE"] - R["ANKLE"]).normalized()
        rest_p = math.atan2(r_ft.z, Vector((r_ft.x, r_ft.y)).length)
        dp = math.atan2(toe.z, max(1e-6, Vector((toe.x, toe.y)).length)) - FLAT[sd]
        pitch = max(rest_p + dp, rest_p - TOE_DOWN_MAX)
        want = Vector((0, -math.cos(pitch), math.sin(pitch)))
        Rft = (Rsh @ r_ft).rotation_difference(want).to_matrix() @ Rsh
        put(ft, Rft, A)
    return M


ORDER = ["hips", "spine", "chest", "neck", "head",
         "clavicle.L", "upperarm.L", "forearm.L", "hand.L", "clavicle.R", "upperarm.R", "forearm.R", "hand.R",
         "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R"]


def depth(b):
    d, p = 0, b.parent
    while p:
        d, p = d + 1, p.parent
    return d


CLOAK = sorted(b.name for b in rig.data.bones if b.name.startswith("cloak."))
# the cloak's motion (owner 2026-09-29: 走路的时候披风要飘动), degrees per link of each chain, top
# link first: MARCH streams it back and swings it each step, the swing running down the chain
# and growing, the side chains swaying against each other with the hips; GARRISON a breeze
CLOAK_MOTION = {
    "MARCH": dict(back=(5.0, 6.0, 7.0), swing=(3.5, 6.0, 9.0), per_loop=2, lag=65.0, side=(1.8, 5.5, 9.0)),
    "GARRISON": dict(back=(1.0, 1.0, 1.5), swing=(0.6, 1.0, 1.6), per_loop=1, lag=50.0, side=(0.4, 0.8, 1.2)),
}


def cloak_fill(M, t, name):
    """World matrices for the cloak's chains: each link rest-relative to its parent, then turned
    about its own head — back (about the chest's X) and sideways (about the chest's forward axis)."""
    mo = CLOAK_MOTION.get(name, CLOAK_MOTION["GARRISON"])
    Rc = M["chest"].to_3x3() @ REST["chest"].to_3x3().inverted()
    ax_x, ax_y = Rc @ Vector((1, 0, 0)), Rc @ Vector((0, 1, 0))
    for nm in CLOAK:
        side, k = nm.split(".")[1], int(nm.split(".")[2])
        parent = rig.data.bones[nm].parent.name
        Mw = M[parent] @ REST[parent].inverted() @ REST[nm]
        ph = 2 * math.pi * (mo["per_loop"] * t) - math.radians(mo["lag"]) * (k - 1)
        back = mo["back"][k - 1] + mo["swing"][k - 1] * math.sin(ph)
        sway = {"C": 0.0, "L": 1.0, "R": -1.0}[side] * mo["side"][k - 1] * math.sin(2 * math.pi * t - math.radians(mo["lag"]) * 0.5 * (k - 1))   # once a loop: seamless
        Rd = Matrix.Rotation(math.radians(back), 3, ax_x) @ Matrix.Rotation(math.radians(sway), 3, ax_y)
        head = Mw.translation
        M[nm] = Matrix.Translation(head) @ (Rd @ Mw.to_3x3()).to_4x4()


def bake(name="MARCH", fn=None, frames=N):
    fn = fn or pose
    sc = bpy.context.scene
    rig.animation_data_create()
    act = bpy.data.actions.get(name)
    if act:
        bpy.data.actions.remove(act)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    for b in pb:
        b.rotation_mode = "QUATERNION"
    names = ORDER + ["spear"] + CLOAK
    order = sorted(names, key=lambda n: depth(pb[n]))
    for f in range(frames + 1):
        M = fn(f / frames)
        if "spear" not in M:          # carried: rigid in the fist
            M["spear"] = M["hand.R"] @ REST["hand.R"].inverted() @ REST["spear"]
        cloak_fill(M, f / frames, name)
        for nme in order:
            pb[nme].matrix = M[nme]
            bpy.context.view_layer.update()
        for nme in names:
            pb[nme].keyframe_insert("rotation_quaternion", frame=f + 1)
            pb[nme].keyframe_insert("location", frame=f + 1)
    sc.render.fps = 30
    sc.frame_start, sc.frame_end = 1, frames
    print("%s: %d frames" % (name, frames))
    return act


if globals().get("BAKE", True):
    bake()
