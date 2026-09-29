"""GARRISON: standing guard behind the shield (owner 2026-09-29: 重新设计驻防动作，士兵把盾牌立在
胸前，右手抬起，把长矛架在盾牌上并指向前方，身体略微前倾; then 我希望驻防动作如上图中间那个人动作所示 —
a crouched hoplite; then 长矛…和士兵的视线方向平齐 — the spear level with his eyes). The shield stands upright before
the chest, its face to the front and a touch to the left, the left arm holding it where it must
be (the arm is solved FROM the shield); the right fist raised above the shoulder, overhand, the
shaft laid over the shield's top rim and the head pointing ahead and a little down; the body
leant forward, the feet side by side, the knees soft. Everything above the
hips is placed in the CHEST's frame, so the breath and the sway carry shield and spear with it.
120 frames (4 s) at 30 fps, a seamless loop. The old garrison stance is baked as STANDBY.

    exec(open(".../infantry_tripo/guard.py").read(), dict(inputs, SHIELD=[part objects]))
"""
import bpy, math
import numpy as np
from mathutils import Vector, Matrix

BLUEPRINT = "/Users/samuelzhang/game_design/tools/units3d/infantry_blueprint/"
G = {"BAKE": False, **{k: globals()[k] for k in ("R", "A_REST", "SH_GRIP", "SH_REST") if k in globals()}}
exec(open(BLUEPRINT + "march.py").read(), G)
REST, rot, two_bone, ik, frame = G["REST"], G["rot"], G["two_bone"], G["ik"], G["frame"]
R, A_REST, HB_REST = G["R"], G["A_REST"], G["HB_REST"]
NF = 120

P = {  # every number of the stance, in the REST body's frame (metres, degrees); -Y is forward, +X his left
    # after the owner's reference (2026-09-29, the middle hoplite): crouched low on wide-set feet, the
    # shield square before the body from chin to thigh, the spear held high by the head and driven
    # down across the front of the shield, its head low before him
    "lean": 12.0, "spine_lean": 6.0, "crouch": 0.14,
    # (owner 2026-09-30: 盾牌抬起到下巴附近) the rim at his chin; the face turned back against the
    # chest's own turn, so it faces straight ahead
    "shield_c": (0.02, -0.33, 1.27),
    "shield_face": (0.17, -1.0, 0.08),
    "rim_side": 0.04, "via_up": 0.45, "via_front": 0.24,   # the shaft passes before the shield's upper face
    # (owner 2026-09-30: 右手举矛的地方需要在修复的合理些) overhand, the upper arm raised out to the side
    # and the elbow out, the fist beside and outside the helmet at eye height
    "grip": (-0.34, 0.12, 1.70),
    "slide": 0.35,                           # the spear pushed forward through the fist
    # level (owner 2026-09-30): the shaft level with his eyes, straight ahead; else through the point above
    "level": True, "eye_up": 0.12, "pitch": 0.0, "yaw": 6.0,
    "elbow_pole_R": (-1.0, 0.3, 0.3),
    "elbow_pole_L": (1.0, 0.1, -0.7),         # the shield elbow down and out
    "grip_back": 0.07,                        # the left fist this far behind the shield's face...
    "grip_shift_L": (0.0, 0.0, 0.02),         # ...and nudged from its centre
    "twist_share_ua": 0.6,
    # the feet wide, the left a little forward, the knees out over the toes
    # (owner 2026-09-30: 左腿弯曲向前，右腿在后，侧向打开，身体压低) the left foot forward under a bent
    # knee, the right back and wide, turned out; the hips turned left-side forward, the chest part back
    "foot_L": (0.20, -0.32), "foot_R": (-0.24, 0.48), "foot_out_L": 10.0, "foot_out_R": 45.0,
    "knee_pole_L": (0.25, -1.0, 0.0), "knee_pole_R": (-0.35, -1.0, 0.2),
    "hip_turn": -22.0, "chest_turn": 12.0,
    "breath": 0.8, "sway": 1.2, "bob": 0.8, "look": 6.0,
}
P.update(globals().get("GUARD", {}))


def shield_frame(objs):
    """The shield's centre, its long axis (top up) and its face normal (away from the body), at rest."""
    co = np.concatenate([np.array([o.matrix_world @ v.co for v in o.data.vertices]) for o in objs])
    c = co.mean(0)
    _, _, vt = np.linalg.svd(co - c)
    up, nrm = Vector(vt[0].tolist()), Vector(vt[2].tolist())
    if up.z < 0:
        up = -up
    body = Vector((0.0, 0.02, c[2]))
    if nrm.dot(Vector(c.tolist()) - body) < 0:
        nrm = -nrm
    half = float(((co - c) @ vt[0]).max())
    return Vector(c.tolist()), up.normalized(), nrm.normalized(), half


def basis(up, nrm):
    """A rotation whose columns are: side, normal, up (orthonormalised on up)."""
    n = (nrm - up * nrm.dot(up)).normalized()
    return Matrix((n.cross(up), n, up)).transposed()


C_R, U_R, N_R, HALF = shield_frame(SHIELD)
F_R = basis(U_R, N_R)
U_T = Vector((0, 0, 1))
F_T = basis(U_T, Vector(P["shield_face"]).normalized())
W0 = Matrix.Translation(Vector(P["shield_c"])) @ (F_T @ F_R.transposed()).to_4x4() @ Matrix.Translation(-C_R)

# the shield has its own bone (tripo.py): it stands where W0 puts it, and the left arm reaches in
# behind it to the grip, the forearm across its back, the elbow down and out
S_L = REST["upperarm.L"].translation
GRIP_L = W0 @ (C_R - N_R * P["grip_back"]) + Vector(P["grip_shift_L"])
# where the shaft passes: on the rim (via_up ~1, via_front 0), or before the shield's face (the owner's
# reference, 2026-09-29: the spear held high and driven down across the front of the shield)
RIM = W0 @ (C_R + U_R * (HALF * P["via_up"]) + N_R * P["via_front"] + (F_R @ Vector((1, 0, 0))) * P["rim_side"])
print("guard: shield centre %s, rim %s, left grip %s" % (tuple(round(x, 3) for x in (W0 @ C_R)), tuple(round(x, 3) for x in RIM), tuple(round(x, 3) for x in GRIP_L)))


def untwist(M, ua, fa, hd, share_ua):
    """Hand the wrist's twist about the forearm to the forearm (pronation) and part of it on to the
    upper arm, as a real arm does: aligned to the spear, a fist left alone was wrung ~90 degrees."""
    def twist():
        loc = (M[fa].to_3x3().inverted() @ M[hd].to_3x3())
        rest = REST[fa].to_3x3().inverted() @ REST[hd].to_3x3()
        return (rest.inverted() @ loc).to_quaternion().to_swing_twist("Y")[1]
    tw = twist()
    best = None
    for sgn in (1.0, -1.0):
        keep = {k: M[k].copy() for k in (ua, fa)}
        for name, share in ((fa, 1.0), (ua, share_ua)):
            ax = (M[name].to_3x3() @ Vector((0, 1, 0))).normalized()
            head = M[name].translation.copy()
            M[name] = Matrix.Translation(head) @ Matrix.Rotation(sgn * tw * share, 4, ax) @ Matrix.Translation(-head) @ M[name]
        left = abs(twist())
        if best is None or left < best[0]:
            best = (left, {k: M[k].copy() for k in (ua, fa)})
        for k in (ua, fa):
            M[k] = keep[k]
    M.update(best[1])
    return math.degrees(tw), math.degrees(best[0])


def pose(t):
    M = {}
    w = 2 * math.pi * t
    breath = math.sin(2 * w)
    rest_h = REST["hips"].translation

    def put(name, Rw, head):
        M[name] = Matrix.Translation(head) @ (Rw @ REST[name].to_3x3()).to_4x4()

    sway = P["sway"] * math.sin(w)
    hips_head = rest_h + Vector((0.006 * math.sin(w), 0.012, -P["crouch"]))
    Rh = rot("Z", P["hip_turn"]) @ rot("X", P["spine_lean"] * 0.5) @ rot("Y", -0.8 * math.sin(w))
    put("hips", Rh, hips_head)
    Rs = rot("Z", P["hip_turn"] + 0.5 * P["chest_turn"]) @ rot("X", P["spine_lean"]) @ rot("Y", 0.5 * math.sin(w))
    spine_head = hips_head + Rh @ (REST["spine"].translation - rest_h)
    put("spine", Rs, spine_head)
    Rc = rot("Z", P["hip_turn"] + P["chest_turn"] + 0.6 * sway) @ rot("X", P["lean"] + P["breath"] * breath)
    chest_head = spine_head + Rs @ (REST["chest"].translation - REST["spine"].translation)
    put("chest", Rc, chest_head)
    D = M["chest"] @ REST["chest"].inverted()                    # the rest body -> this frame, above the chest
    neck_head = chest_head + Rc @ (REST["neck"].translation - REST["chest"].translation)
    put("neck", Rc, neck_head)
    head_head = neck_head + Rc @ (REST["head"].translation - REST["neck"].translation)
    look = P["look"] * math.sin(w - 0.8) ** 3
    # the head faces straight ahead over the rim, whatever the hips and chest turned
    put("head", rot("Z", look) @ rot("X", -0.6 * P["lean"]), head_head)
    for sd in ("L", "R"):
        cl = "clavicle." + sd
        put(cl, Rc, chest_head + Rc @ (REST[cl].translation - REST["chest"].translation))
    # the shield stands before the chest; the left arm reaches in behind it to the grip
    Rd = D.to_3x3()
    M["shield"] = D @ W0 @ REST["shield"]
    ua, fa, hd = "upperarm.L", "forearm.L", "hand.L"
    Sl = D @ S_L
    gl = D @ GRIP_L
    l1 = (REST[fa].translation - REST[ua].translation).length
    l2 = (REST[hd].translation - REST[fa].translation).length + 0.05
    El = ik(Sl, gl, l1, l2, Rd @ Vector(P["elbow_pole_L"]).normalized())
    Rua = (REST[fa].translation - REST[ua].translation).normalized().rotation_difference((El - Sl).normalized()).to_matrix()
    put(ua, Rua, Sl)
    fdir = (gl - El).normalized()
    r_fa = (REST[hd].translation - REST[fa].translation).normalized()
    Rfa = (Rua @ r_fa).rotation_difference(fdir).to_matrix() @ Rua
    put(fa, Rfa, El)
    put(hd, Rfa, El + Rfa @ (REST[hd].translation - REST[fa].translation))
    # the spear arm: the fist overhand, the shaft over the rim, the head bobbing a little about it
    g = D @ Vector(P["grip"])
    if P["level"]:
        # LEVEL with his eyes (owner 2026-09-30: 长矛太往下了，抬起来，和士兵的视线方向平齐): the fist
        # at eye height, the shaft straight ahead in the WORLD, whatever the lean, bobbing a little
        g.z = head_head.z + P["eye_up"]
        pitch = math.radians(P["pitch"] + P["bob"] * math.sin(w + 0.4))
        yaw = math.radians(P["yaw"])
        d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), -math.sin(pitch)))
    else:
        rim = D @ RIM
        bob = rot("X", P["bob"] * math.sin(w + 0.4)).to_4x4()
        g = rim + (Rd @ bob.to_3x3()) @ (Rd.inverted() @ (g - rim))
        d = (rim - g).normalized()
    ua, fa, hd = "upperarm.R", "forearm.R", "hand.R"
    Sr = D @ REST[ua].translation
    l1 = (REST[fa].translation - REST[ua].translation).length
    l2 = (REST[hd].translation - REST[fa].translation).length
    grip_rest = REST[hd].inverted() @ REST["spear"].translation      # the grip channel in the hand's frame
    base = frame(d, Vector((0, 0, 1))) @ frame(A_REST, HB_REST).transposed()
    best = None
    for k in range(72):
        # the fist may turn about the shaft freely (the spear does not move): pick the turn that
        # leaves the wrist straightest once the arm reaches it
        Rfist = Matrix.Rotation(math.radians(k * 5), 3, d) @ base     # (not Rh: that is the hips')
        Mh = (Rfist @ REST[hd].to_3x3()).to_4x4()
        h = g - Mh.to_3x3() @ grip_rest                               # the hand's head, the grip on the shaft at g
        Mh.translation = h
        El = ik(Sr, h, l1, l2, Rd @ Vector(P["elbow_pole_R"]).normalized())
        Rua_ = (REST[fa].translation - REST[ua].translation).normalized().rotation_difference((El - Sr).normalized()).to_matrix()
        r_fa = (REST[hd].translation - REST[fa].translation).normalized()
        Rfa_ = (Rua_ @ r_fa).rotation_difference((h - El).normalized()).to_matrix() @ Rua_
        Mf = (Rfa_ @ REST[fa].to_3x3())
        rel = (REST[fa].to_3x3().inverted() @ REST[hd].to_3x3()).inverted() @ (Mf.inverted() @ Mh.to_3x3())
        sw, tw = rel.to_quaternion().to_swing_twist("Y")
        cost = abs(tw) + 0.7 * sw.angle
        if best is None or cost < best[0]:
            best = (cost, Mh, El, Rua_, Rfa_)
    _, Mh, El, Rua, Rfa = best
    put(ua, Rua, Sr)
    put(fa, Rfa, El)
    M[hd] = Mh
    M["spear"] = Matrix.Translation(d * P["slide"]) @ M[hd] @ REST[hd].inverted() @ REST["spear"]
    TWIST.append(untwist(M, ua, fa, hd, P["twist_share_ua"]))
    # the legs: the left foot forward, the right back, planted, the knees soft
    for sd, sg in (("L", 1), ("R", -1)):
        th, sh, ft = "thigh." + sd, "shin." + sd, "foot." + sd
        H = hips_head + Rh @ (REST[th].translation - rest_h)
        fx, fy = P["foot_" + sd]
        A = Vector((fx, fy, REST[ft].translation.z))
        Kn, A = two_bone(H, A, Vector(P["knee_pole_" + sd]).normalized())
        r_th = (REST[sh].translation - REST[th].translation).normalized()
        Rth = r_th.rotation_difference((Kn - H).normalized()).to_matrix()
        put(th, Rth, H)
        r_sh = (REST[ft].translation - REST[sh].translation).normalized()
        Rsh = (Rth @ r_sh).rotation_difference((A - Kn).normalized()).to_matrix() @ Rth
        put(sh, Rsh, Kn)
        r_ft = (REST[ft].to_3x3() @ Vector((0, 1, 0))).normalized()
        p_ = math.atan2(r_ft.z, Vector((r_ft.x, r_ft.y)).length)
        want = rot("Z", P["foot_out_" + sd] * sg) @ Vector((0, -math.cos(p_), math.sin(p_)))
        put(ft, (Rsh @ r_ft).rotation_difference(want).to_matrix() @ Rsh, A)
    return M


TWIST = []
G["bake"]("GARRISON", pose, NF)
print("guard: right wrist twist %.0f -> %.0f deg" % TWIST[0])
