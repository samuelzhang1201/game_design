"""The cavalry's five clips (owner 2026-10-06: 和国王一样五个，换成长枪版), keyed on `cavalry_rig` at 30 fps
from frame 0, through the royal rig's pose ops (royal_rig/actions.py: rot / aim / ik / rear / place /
loc / ground / plant, and Reins following the left hand) plus this rig's own:

  ("gait", u)          the canter's legs at phase u: each hoof's fetlock on its generated path by
                       IK (stance: on the ground, travelling back at the body's speed -- no slide;
                       swing: a smoothstep forward with a sine lift), the hoof aimed planted / folded
  ("shield_arm",)      the shield taken off the back onto the left forearm (owner 2026-09-30: 用第一种)

Brief (blender-natural-animation Phase 1): a 0.8 t warhorse and an armoured lancer, game clips at
30 fps, in place (the map moves the piece; `stride_m` comes from the canter's measured stance speed).

  MARCH     骑马飞奔  16 f loop: the king's right-lead 3-beat canter -- LH; RH + LF; RF; suspension --
                     the lance upright in the right fist, the shield on his back
  GARRISON  驻防     120 f loop: halted; the shield on his left arm before him, the lance couched level
  ATTACK    攻击     75 f: gather and couch (0-10), two canter strides, the thrust at 34, the halt, settle
  DEFEND    被攻击   80 f: the horse shies and rears, the shield thrown up over his head, the blow at 32
  STANDBY   待命     120 f loop: dismounted at the horse's head, reins in the left hand, the lance
                     grounded upright in the right
Overlap: the rider follows the saddle 2 f late (his hips) and counters with the torso; the neck and
tail chains are phase-offset down their length (Phase 4).
"""
CLIP_PREFIX = "cavalry_"


def rigo():
    return bpy.data.objects[RIG_NAME]


# ------------------------------------------------------------------ the gait ----
CANTER_FRAMES = 16
CANTER = {"HindHoof.L": 0.00, "HindHoof.R": 0.26, "FrontHoof.L": 0.27, "FrontHoof.R": 0.45}
DUTY = 0.31
STRIDE = 2.4                      # metres a loop: the speed a planted hoof travels back
LIFT = {"Front": 0.30, "Hind": 0.20}


def op_gait(a, u, stride=STRIDE, lift=1.0):
    for hoof, ph in CANTER.items():
        kind, s = hoof[:5] if hoof.startswith("Front") else hoof[:4], hoof[-1]
        cb = a.data.bones[("FrontCannon." if kind == "Front" else "HindCannon.") + s]
        home = Vector(cb.tail_local)
        p = (u - ph) % 1.0
        if p < DUTY:
            k = p / DUTY
            y = home.y + stride * DUTY * (k - 0.5)
            z = home.z
            fold = 0.0
        else:
            k = (p - DUTY) / (1 - DUTY)
            e = k * k * (3 - 2 * k)
            y = home.y + stride * DUTY * 0.5 - stride * DUTY * e
            z = home.z + LIFT[kind] * lift * math.sin(math.pi * k)
            fold = math.sin(math.pi * k)
        # pre-bend the way the joint folds, so the IK keeps the knee / hock the right way round
        if kind == "Front":
            op_rot(a, "FrontForearm." + s, (10 + 25 * fold, 0, 0))
            op_rot(a, "FrontCannon." + s, (-20 - 60 * fold, 0, 0))
            # 4 bones: the scapula swings too (a stance foreleg is longer than the leg below the shoulder)
            op_ik(a, "FrontCannon." + s, a.matrix_world @ Vector((home.x, y, z)), 4)
            hb = a.data.bones["FrontHoof." + s]
            rest = (hb.tail_local - hb.head_local).normalized()
            op_aim(a, "FrontHoof." + s, rest.lerp(Vector((0, 0.9, 0.45)), fold * 0.9))
        else:
            op_rot(a, "HindShin." + s, (-8 * fold, 0, 0))
            op_ik(a, "HindCannon." + s, a.matrix_world @ Vector((home.x, y, z)), 3)
            hb = a.data.bones["HindHoof." + s]
            rest = (hb.tail_local - hb.head_local).normalized()
            op_aim(a, "HindHoof." + s, rest.lerp(Vector((0, 0.85, 0.5)), fold * 0.8))


# --------------------------------------------------------------- the shield ----
GUARD_Y = Vector((0.08, 0.05, 1.0)).normalized()        # the shield's long axis on guard (up, a little back)
GUARD_FACE = Vector((0.55, -0.83, 0.0)).normalized()    # its painted face out to the front-left
GUARD_AT = Vector((0.07, -0.02, 0.02))                  # its centre from the forearm's middle, outward


def op_shield_arm(a, raise_=0.0):
    """The Shield bone placed on the left forearm: centre just outside the forearm's middle, the long
    axis up, the face to the front-left (turned with the forearm about the vertical)."""
    fa = a.pose.bones["R_Forearm.L"]
    mid = (fa.head + fa.tail) / 2
    yaw = math.atan2(-(fa.tail - fa.head).x, -(fa.tail - fa.head).y)
    R = Matrix.Rotation(yaw * 0.5, 3, "Z")
    Y = (R @ GUARD_Y).normalized()
    Zl = -(R @ GUARD_FACE)                               # the bone's Z points into the shield's back
    Zl = (Zl - Y * Zl.dot(Y)).normalized()
    X = Y.cross(Zl)
    M = Matrix((X, Y, Zl)).transposed().to_4x4()
    centre = mid + R @ GUARD_AT + Vector((0, 0, raise_))
    M.translation = centre - Y * 0.12
    a.pose.bones["Shield"].matrix = M
    _upd()


OPS.update({"gait": op_gait, "shield_arm": op_shield_arm})


HIND_PIVOT = (0.03, 0.75, 0.0)        # between this horse's hind hooves


def wave(u, lag=0.0):
    return math.sin(2 * math.pi * (u - lag))


# -------------------------------------------------------------------- MARCH ----
def canter_pose(u, lance=True, amp=1.0):
    """`amp` 0..1 scales the whole gait (stride, lift, rocking): a charge eases into and out of it."""
    lag = 2.0 / CANTER_FRAMES                        # the rider 2 f behind the saddle
    pitch = 4.0 * amp * wave(u, -0.05)
    bob = amp * (0.03 * math.cos(2 * math.pi * (u - 0.85)) - 0.06)   # low enough that a stance leg always reaches
    ops = [("rear", pitch, (0.0, 0.15, 0.9)), ("loc", "root", (0, 0, bob))]
    ops += [("rot", "Spine1", (1.5 * amp * wave(u, 0.1), 0, 0)),
            ("rot", "Neck1", (-9 * amp * wave(u, 0.08), 0, 0)), ("rot", "Neck2", (-6 * amp * wave(u, 0.14), 0, 0)),
            ("rot", "Head", (7 * amp * wave(u, 0.2), 0, 0)),     # the nod (critic 2026-10-06: 6 deg read mechanical)
            ("rot", "Tail1", (amp * (-14 + 6 * wave(u, 0.2)), 0, 0)), ("rot", "Tail2", (8 * amp * wave(u, 0.3), 0, 0)),
            ("rot", "Tail3", (10 * amp * wave(u, 0.4), 0, 0)), ("rot", "Tail4", (12 * amp * wave(u, 0.5), 0, 0)),
            ("gait", u, STRIDE * amp, amp)]   # LAST of the horse: the forelegs hang from the spine the ops above turn
    pl = 4.0 * amp * wave(u - lag, -0.05)
    ops += [("rot", "R_Hips", (-0.8 * pl + 6, 0, 0)), ("rot", "R_Spine", (2 + 2.5 * wave(u, 0.25), 0, 0)),
            ("rot", "R_Chest", (1.5 * wave(u, 0.32), 0, 0)),
            ("rot", "R_Head", (-0.6 * pl - 3 * wave(u, 0.4), 0, 0)),
            ("rot", "R_Shin.L", (-4, 0, 0)), ("rot", "R_Shin.R", (-4, 0, 0)),
            ("rot", "R_UpperArm.L", (3 * wave(u, 0.3), 0, 0))]
    if lance:
        ops += [("rot", "R_UpperArm.R", (4 * wave(u, 0.3), 0, 0)),
                ("aim", "Lance", (0.06 * wave(u, 0.45), -0.10 + 0.04 * wave(u, 0.4), 1.0))]
    return ops


def march():
    n = CANTER_FRAMES
    return clip("MARCH", [(f, canter_pose(f / n)) for f in range(0, n + 1)])


# ----------------------------------------------------------------- GARRISON ----
# 驻防: halted; the shield off his back onto the left arm before him, the lance couched under the
# right arm, level, its point across the horse's neck to the front-left (how a lance was couched).
GARRISON_FRAMES = 120
COUCH = {"upper": (-0.10, 0.25, -0.96), "fore": (0.10, -0.99, 0.04), "hand": (0.12, -0.99, 0.0),
         "lance": (0.16, -0.99, 0.02)}
GUARD = {"upper": (0.12, -0.42, -0.90), "fore": (-0.38, -0.92, 0.08)}


def couch(u=0.0, amp=1.0, dip=0.0):
    w = 0.02 * amp * wave(u * 2, 0.35)
    return [("aim", "R_UpperArm.R", COUCH["upper"]),
            ("aim", "R_Forearm.R", Vector(COUCH["fore"]) + Vector((0, 0, w))),
            ("aim", "R_Hand.R", COUCH["hand"]),
            ("aim", "Lance", Vector(COUCH["lance"]) + Vector((0, 0, w * 0.6 - dip)))]


def guard(u=0.0, raise_=0.0):
    w = 0.015 * wave(u * 2, 0.6)
    return [("aim", "R_UpperArm.L", GUARD["upper"]),
            ("aim", "R_Forearm.L", Vector(GUARD["fore"]) + Vector((0, 0, w))),
            ("shield_arm", raise_)]


def garrison_pose(u):
    return (horse_idle(u) + breathe(u) + [("rot", "R_Spine", (3, 0, 0)), ("rot", "R_Head", (-3, 4 * wave(u, 0.3), 0))]
            + couch(u) + guard(u))


def garrison():
    n = GARRISON_FRAMES
    return clip("GARRISON", [(f, garrison_pose(f / n)) for f in range(0, n + 1, 4)])


# ------------------------------------------------------------------- ATTACK ----
# 攻击: the charge -- gather and couch the lance (0-10), two canter strides with it level (10-42),
# the thrust at 34 (he leans into it) and the recoil at 37, the horse braking onto its haunches,
# the lance raised again and the pair settled. The shield stays on his back (it goes to the arm
# only on guard, GARRISON / DEFEND).
ATTACK_FRAMES = 75


def charge_pose(u, lean=0.0, dip=0.0, amp=1.0):
    ops = canter_pose(u % 1.0, lance=False, amp=amp)
    if lean:      # before the couch: the lance is aimed in the world, the lean must not tip it down
        ops += [("rot", "R_Spine", (lean, 0, 0)), ("rot", "R_Chest", (lean * 0.5, 0, 0)), ("rot", "R_Head", (-lean, 0, 0))]
    return ops + couch(u, 0.6, dip)


def brake(k):
    """Haunches under, forelegs braced forward, head up (k 0..1)."""
    ops = [("rear", 5 * k, HIND_PIVOT), ("loc", "root", (0, 0.02 * k, -0.06 * k)), ("plant",)]
    for s in "LR":
        ops += [("rot", "FrontUpperArm." + s, (14 * k, 0, 0)), ("rot", "FrontCannon." + s, (-6 * k, 0, 0))]
    ops += [("rot", "Neck1", (8 * k, 0, 0)), ("rot", "Head", (-6 * k, 0, 0)), ("rot", "R_Hips", (-6 * k, 0, 0))]
    return ops


def attack():
    k = [(0, [])]
    k.append((4, [("rear", -2, HIND_PIVOT), ("loc", "root", (0, 0, -0.05)), ("plant",), ("rot", "R_Spine", (4, 0, 0)),
                  ("aim", "Lance", (0.05, -0.35, 0.94))]))
    k.append((8, [("rear", -3, HIND_PIVOT), ("loc", "root", (0, 0, -0.08)), ("plant",), ("rot", "R_Spine", (6, 0, 0))]
              + couch(0.0, 0.0)))
    for f in range(9, 44):
        u = (f - 10) / CANTER_FRAMES
        amp = smooth((f - 8) / 10.0) * (1 - smooth((f - 36) / 8.0))     # into the canter, and out of it
        lean = 14.0 * env(f, 28, 40)
        dip = 0.06 * env(f, 33, 39)
        crouch = 1 - smooth((f - 8) / 6.0)       # the gather's sink let go over the first strides
        k.append((f, [("rear", -3 * crouch, HIND_PIVOT), ("loc", "root", (0, 0, -0.08 * crouch))]
                  + charge_pose(u, lean, dip, amp)))
    k.append((50, brake(1.0) + couch(0.0, 0.0)))
    k.append((56, brake(0.6) + [("aim", "Lance", (0.08, -0.6, 0.8))]))
    k.append((64, brake(0.15)))
    k.append((ATTACK_FRAMES, []))
    return clip("ATTACK", k)


# ------------------------------------------------------------------- DEFEND ----
# 被攻击: struck at, the horse shies and rears; the shield thrown up over his head on the left arm,
# the lance held up and back out of the way; the blow lands on the shield at 32; the horse comes down.
DEFEND_FRAMES = 80
HIGH = {"upper": (0.30, -0.25, 0.92), "fore": (-0.55, -0.45, 0.70)}


def high_guard(raise_=0.06):
    return [("aim", "R_UpperArm.L", HIGH["upper"]), ("aim", "R_Forearm.L", HIGH["fore"]), ("shield_arm", raise_)]


def defend():
    lance_up = [("aim", "R_UpperArm.R", (-0.2, 0.15, -0.97)), ("aim", "R_Forearm.R", (-0.05, -0.6, 0.8)),
                ("aim", "Lance", (-0.05, 0.35, 0.94))]
    k = [
        (0, []),
        (10, rear_body(6, 0.2, 0.2, 14) + [("rot", "Head", (10, 0, 12)), ("rot", "R_Spine", (-6, 0, 0))] + lance_up + guard()),
        (24, rear_body(28, 0.85, 0.55, 18) + [("rot", "Head", (14, 0, 15)), ("rot", "R_Spine", (-8, 0, 6))] + lance_up + high_guard()),
        (32, rear_body(30, 0.9, 0.6, 16) + [("rot", "Head", (12, 0, 10)), ("rot", "R_Spine", (-14, 0, 8))] + lance_up + high_guard(0.0)),
        (42, rear_body(24, 0.75, 0.5, 12) + [("rot", "Head", (10, 0, 6)), ("rot", "R_Spine", (-6, 0, 4))] + lance_up + high_guard()),
        (56, rear_body(-2, 0.0, 0.1, -6) + [("rot", "R_Spine", (4, 0, 0))] + guard()),
        (68, rear_body(1, 0.0, 0.0, -1)),
        (DEFEND_FRAMES, []),
    ]
    return clip("DEFEND", k)


# ------------------------------------------------------------------ STANDBY ----
# 待命 (owner 2026-10-06: 骑兵还是骑在马上，不要下来，来回看，长矛自然的拿在手上): mounted at ease, looking
# about -- left, a held look, right, a held look, back -- the head leading, the neck 2 f and the chest
# 4 f behind it with less of the turn; the lance upright in his right fist, swaying with him; the
# shield on his back; the horse idling and turning its head a little after him. A loop.
STANDBY_FRAMES = 120


def plateau(u, a_, b_, c_, d_):
    """0 -> 1 eased over a..b, held, 1 -> 0 eased over c..d."""
    return smooth((u - a_) / (b_ - a_)) * (1 - smooth((u - c_) / (d_ - c_)))


def look(u):
    """The head's turn in degrees (+ = to his left), with a moving hold: it drifts on while held."""
    return (34 * plateau(u, 0.05, 0.19, 0.33, 0.45) + 4 * env(u, 0.19, 0.33)
            - 30 * plateau(u, 0.50, 0.63, 0.77, 0.90) - 4 * env(u, 0.63, 0.77))


def stand_pose(u):
    n = STANDBY_FRAMES
    head, neck, chest = look(u), look(u - 2.0 / n), look(u - 4.0 / n)
    tilt = 3 * env(u, 0.19, 0.33) - 2 * env(u, 0.63, 0.77)        # a slight cock of the head as he looks
    ops = horse_idle(u) + [("rot", "Neck2", (0, 0, 0.15 * look(u - 10.0 / n))),
                           ("rot", "Head", (0, 0, 0.12 * look(u - 12.0 / n)))]
    ops += breathe(u, 1.2)
    ops += [("rot", "R_Chest", (0, 0.22 * chest, 0)), ("rot", "R_Neck", (0, 0.35 * neck, 0)),
            ("rot", "R_Head", (tilt, 0.55 * head, 0))]
    # the lance upright and easy in the right fist: it leans a touch forward, swaying with his breath
    sway = wave(u * 2, 0.15)
    ops += [("rot", "R_UpperArm.R", (2 + 1.5 * sway, 0, 0)),
            ("aim", "Lance", (0.03 * wave(u, 0.3) + 0.004 * chest, -0.10 + 0.02 * sway, 1.0))]
    return ops


def standby():
    n = STANDBY_FRAMES
    return clip("STANDBY", [(f, stand_pose(f / n)) for f in range(0, n + 1, 4)])


def all_clips():
    return [march(), garrison(), attack(), defend(), standby()]
