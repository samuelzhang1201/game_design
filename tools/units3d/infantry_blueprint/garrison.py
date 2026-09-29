"""GARRISON: standing guard (owner 2026-09-28: 再做驻防动作). The spear's butt
grounded beside the right foot, the shaft upright, the right hand holding it at
chest height (the spear slides in the fist so the butt stays on the ground);
the shield hanging on the relaxed left arm; the feet planted, the knees soft,
the weight drifting from foot to foot, the chest breathing, the head looking
slowly left and right. 120 frames (4 s) at 30 fps, a seamless loop.
    exec(open(".../garrison.py").read(), {})
"""
import bpy, math
from mathutils import Vector, Matrix, Quaternion

HERE = "/Users/samuelzhang/game_design/tools/units3d/infantry_blueprint/"
G = {"BAKE": False}
exec(open(HERE + "march.py").read(), G)
REST, rot, two_bone, R = G["REST"], G["rot"], G["two_bone"], G["R"]
rig = G["rig"]
NF = 120
SHIELD_TURN = globals().get("SHIELD_TURN", 40.0)   # degrees the left upper arm turns in: the shield's face to the front-left (measured clear of the tassets)
SHIELD_ABD = globals().get("SHIELD_ABD", 8.0)      # and out from the body, so it clears the tassets
SHIELD_BEND = globals().get("SHIELD_BEND", 6.0)   # the elbow bent a little more, the shield carried
SHIELD_FWD = globals().get("SHIELD_FWD", 10.0)      # the upper arm a little forward: the shield before the tassets
ANK_Z = R["ANKLE"].z

# the spear's axis and its butt, in the spear bone's rest frame
_sp = bpy.data.objects["inf_spear"]
_vs = [v.co.copy() for v in _sp.data.vertices]
_c = sum(_vs, Vector()) / len(_vs)
_ax = max(((a - b) for a in _vs[:40] for b in _vs[-40:]), key=lambda d: d.length).normalized()
if _ax.z < 0:
    _ax = -_ax                                            # butt -> tip
_head = REST["spear"].translation
BUTT = min((v - _head).dot(_ax) for v in _vs)             # the butt's distance along the axis from the grip
AX_REST = _ax


def arm_ik(S_, target, L1a, L2a, pole):
    d = target - S_
    dl = min(d.length, (L1a + L2a) * 0.999)
    u = d.normalized()
    a = (L1a * L1a - L2a * L2a + dl * dl) / (2 * dl)
    h = math.sqrt(max(0.0, L1a * L1a - a * a))
    w = (pole - u * pole.dot(u)).normalized()
    return S_ + u * a + w * h, S_ + u * dl


def pose_g(t):
    M = {}
    w = 2 * math.pi * t
    rest_h = REST["hips"].translation

    def put(name, Rw, head):
        M[name] = Matrix.Translation(head) @ (Rw @ REST[name].to_3x3()).to_4x4()

    shift = 0.025 * math.sin(w)                           # the weight from foot to foot
    breath = math.sin(2 * w)                              # two breaths a loop
    hips_head = rest_h + Vector((shift, 0.0, -0.022 + 0.003 * abs(math.sin(w))))
    Rh = rot("Y", -1.6 * math.sin(w)) @ rot("Z", 1.5 * math.sin(w + 0.6))
    put("hips", Rh, hips_head)
    Rs = rot("Y", 0.9 * math.sin(w)) @ rot("X", -0.6 * breath)
    spine_head = hips_head + Rh @ (REST["spine"].translation - rest_h)
    put("spine", Rs, spine_head)
    Rc = rot("Y", 1.2 * math.sin(w)) @ rot("X", -1.0 * breath) @ rot("Z", -2.0 * math.sin(w + 0.6))
    chest_head = spine_head + Rs @ (REST["chest"].translation - REST["spine"].translation)
    put("chest", Rc, chest_head)
    neck_head = chest_head + Rc @ (REST["neck"].translation - REST["chest"].translation)
    put("neck", Rc, neck_head)
    look = 20.0 * math.sin(w - 0.8) ** 3                  # a slow look left, then right, pausing ahead
    head_head = neck_head + Rc @ (REST["head"].translation - REST["neck"].translation)
    put("head", rot("Z", look) @ rot("X", 2.0 * math.sin(w + 1.3)), head_head)
    for sd in ("L", "R"):
        cl = "clavicle." + sd
        cl_head = chest_head + Rc @ (REST[cl].translation - REST["chest"].translation)
        put(cl, Rc, cl_head)
        ua, fa, hd = "upperarm." + sd, "forearm." + sd, "hand." + sd
        ua_head = cl_head + Rc @ (REST[ua].translation - REST[cl].translation)
        if sd == "L":                                       # relaxed, the shield hanging
            Rab = Rc @ rot("Y", 5.0 + SHIELD_ABD)
            Rua = Rab @ rot("X", -(3.0 + SHIELD_FWD + 0.8 * breath))
            # the upper arm turned in about its own length so the shield's face comes round to the
            # front: standing square to the camera, a piece showed its shield edge-on and lost its
            # colour (independent critic, 2026-09-29)
            Rtw = Matrix.Rotation(math.radians(SHIELD_TURN), 3, Rua @ (REST[fa].translation - REST[ua].translation).normalized())
            Rua = Rtw @ Rua
            put(ua, Rua, ua_head)
            fa_head = ua_head + Rua @ (REST[fa].translation - REST[ua].translation)
            Rfa = Rtw @ Rab @ rot("X", -(3.0 + SHIELD_FWD + 10.0 + SHIELD_BEND))
            put(fa, Rfa, fa_head)
            put(hd, Rfa, fa_head + Rfa @ (REST[hd].translation - REST[fa].translation))
            continue
        # the right hand holds the grounded spear at chest height, out beside the body
        grip = Vector((-0.29, -0.26, 1.26)) + Vector((0.0, 0.0, 0.004 * breath))
        L1a = (REST[fa].translation - REST[ua].translation).length
        L2a = (REST[hd].translation - REST[fa].translation).length + 0.058
        El, Wt = arm_ik(ua_head, grip, L1a, L2a, Vector((-0.6, 0.5, -0.4)).normalized())
        r_ua = (REST[fa].translation - REST[ua].translation).normalized()
        Rua = r_ua.rotation_difference((El - ua_head).normalized()).to_matrix()
        put(ua, Rua, ua_head)
        r_fa = (REST[hd].translation - REST[fa].translation).normalized()
        Rfa = (Rua @ r_fa).rotation_difference((Wt - El).normalized()).to_matrix() @ Rua
        put(fa, Rfa, El)
        hd_head = El + Rfa @ (REST[hd].translation - REST[fa].translation)
        # the fist turned so the spear stands upright, leaning a hair out and forward
        up = Vector((-0.04, -0.03, 1.0)).normalized()
        Rhd = (Rfa @ AX_REST).rotation_difference(up).to_matrix() @ Rfa
        put(hd, Rhd, hd_head)
        Msp = M[hd] @ REST[hd].inverted() @ REST["spear"]
        g = Msp.translation
        slide = (0.012 - g.z) / up.z - BUTT                # the butt on the ground
        M["spear"] = Matrix.Translation(up * slide) @ Msp
    # the legs: the feet planted a little apart, turned out a touch
    for sd, sg in (("L", 1), ("R", -1)):
        th, sh, ft = "thigh." + sd, "shin." + sd, "foot." + sd
        H = hips_head + Rh @ (REST[th].translation - rest_h)
        A = REST[ft].translation + Vector((0.02 * sg, 0.0, 0.0))
        Kn, A = two_bone(H, A, Vector((0.12 * sg, -1, 0)).normalized())
        r_th = (REST[sh].translation - REST[th].translation).normalized()
        Rth = r_th.rotation_difference((Kn - H).normalized()).to_matrix()
        put(th, Rth, H)
        r_sh = (REST[ft].translation - REST[sh].translation).normalized()
        Rsh = (Rth @ r_sh).rotation_difference((A - Kn).normalized()).to_matrix() @ Rth
        put(sh, Rsh, Kn)
        r_ft = (R["TOE"] - R["ANKLE"]).normalized()
        want = rot("Z", -6.0 * sg) @ r_ft
        put(ft, (Rsh @ r_ft).rotation_difference(want).to_matrix() @ Rsh, A)
    return M


G["bake"]("GARRISON", pose_g, NF)
# leave MARCH on the rig for the viewer
rig.animation_data.action = bpy.data.actions["MARCH"]
bpy.context.scene.frame_start, bpy.context.scene.frame_end = 1, G["N"]
