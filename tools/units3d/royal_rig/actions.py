"""The king's five clips (owner 2026-10-06), keyed on `royal_rig` at 30 fps from frame 0:

  MARCH     骑马飞奔 -- a four-beat gallop, the king holding his sword one-handed (a loop)
  GARRISON  驻防     -- the horse halted, the king's sword raised and pointed forward (a loop)
  ATTACK    攻击     -- the horse rears, the king cuts forward with the sword (one shot)
  DEFEND    被攻击   -- the horse rears, the king parries above his head (one shot)
  STANDBY   待命     -- the king on foot at the horse's head, holding the reins (a loop)

A pose is a list of ops applied in order from the rest pose (each sees its parents' result):
  ("rot", bone, (x, y, z))   local Euler degrees, composed onto what the bone has
  ("aim", bone, dir)         turn the bone so its axis points along a world direction
  ("ik", bone, target, n)    an n-bone IK reach of `bone`'s tail to a world point, baked
  ("rear", deg, pivot)       the whole piece pitched nose-up about a ground point (the hind hooves)
  ("place", bone, pos, yaw)  a root-of-character bone moved to a world point, turned about Z
  ("loc", bone, (x, y, z))   a world-space offset of a bone (its head)

Local axes (from the rolls armature.py sets): on a mostly VERTICAL bone (a leg, the rider's
spine) +X swings the far end FORWARD (-Y); on a mostly HORIZONTAL bone (the horse's spine,
neck) +X lifts the far end; local Z on a horizontal bone is up, so +Z turns it to the
piece's left (+X).
"""
import math
from mathutils import Euler, Quaternion

FPS = 30
CLIP_PREFIX = "royal_"


def rigo():
    return bpy.data.objects["royal_rig"]


def reset(a=None):
    a = a or rigo()
    for pb in a.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
        pb.scale = Vector((1, 1, 1))
    bpy.context.view_layer.update()


def _upd():
    bpy.context.view_layer.update()


def op_rot(a, bone, xyz):
    pb = a.pose.bones[bone]
    q = Euler([math.radians(v) for v in xyz]).to_quaternion()
    pb.rotation_quaternion = pb.rotation_quaternion @ q
    _upd()


def op_aim(a, bone, d):
    pb = a.pose.bones[bone]
    M = pb.matrix.copy()
    y = M.to_3x3().col[1].normalized()
    q = y.rotation_difference(Vector(d).normalized())
    R = q.to_matrix() @ M.to_3x3()
    N = R.to_4x4()
    N.translation = M.translation
    pb.matrix = N
    _upd()


def op_ik(a, bone, target, n=2):
    pb = a.pose.bones[bone]
    tgt = bpy.data.objects.get("ik_target") or bpy.data.objects.new("ik_target", None)
    if tgt.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(tgt)
    tgt.location = a.matrix_world @ Vector(target)
    c = pb.constraints.new("IK")
    c.target = tgt
    c.chain_count = n
    _upd()
    chain = [pb]
    p = pb
    for _ in range(n - 1):
        p = p.parent; chain.append(p)
    mats = {x.name: x.matrix.copy() for x in chain}
    pb.constraints.remove(c)
    for x in reversed(chain):
        x.matrix = mats[x.name]
        _upd()


def op_rear(a, deg, pivot):
    """The root pitched nose-up by `deg` about the world point `pivot` (the root's rest frame is
    the armature's own, so its location is a world offset)."""
    pb = a.pose.bones["root"]
    q = Quaternion((1, 0, 0), math.radians(-deg))
    pb.rotation_quaternion = q @ pb.rotation_quaternion
    P = Vector(pivot)
    pb.location = pb.location + (P - q @ P)
    _upd()


def op_place(a, bone, pos, yaw):
    pb = a.pose.bones[bone]
    R = Matrix.Rotation(math.radians(yaw), 4, "Z") @ pb.bone.matrix_local.to_3x3().to_4x4()
    R.translation = Vector(pos)
    pb.matrix = R
    _upd()


def op_loc(a, bone, d):
    pb = a.pose.bones[bone]
    M = pb.matrix.copy()
    M.translation = M.translation + Vector(d)
    pb.matrix = M
    _upd()


HOOVES = ("FrontHoof.L", "FrontHoof.R", "HindHoof.L", "HindHoof.R")


def op_ground(a, lift=0.0):
    """The root raised or lowered so the lowest hoof tip stands `lift` above z = 0."""
    z = min((a.matrix_world @ a.pose.bones[h].tail).z for h in HOOVES)
    pb = a.pose.bones["root"]
    pb.location = pb.location + Vector((0, 0, lift - z))
    _upd()


def op_plant(a, legs=("L", "R")):
    """Each hind leg's fetlock pulled back by IK (thigh, shin, cannon) to where it stands at
    rest, the hoof turned back to its rest direction: the hind hooves stay where they stood."""
    for s in legs:
        cb = a.data.bones["HindCannon." + s]
        op_ik(a, "HindCannon." + s, a.matrix_world @ cb.tail_local, 3)
        hb = a.data.bones["HindHoof." + s]
        op_aim(a, "HindHoof." + s, hb.tail_local - hb.head_local)


OPS = {"follow": None, "plant": op_plant, "ground": op_ground, "rot": op_rot, "aim": op_aim, "ik": op_ik, "rear": op_rear, "place": op_place, "loc": op_loc}


def op_follow(a, bone, target):
    """`bone` moved onto `target`'s head, keeping its rest orientation (the reins' end)."""
    pb, tb = a.pose.bones[bone], a.pose.bones[target]
    M = pb.bone.matrix_local.copy()
    M.translation = tb.matrix.translation
    pb.matrix = M
    _upd()


def pose(ops, a=None):
    a = a or rigo()
    reset(a)
    for o_ in ops:
        OPS[o_[0]](a, *o_[1:])
    if "Reins" in a.pose.bones:
        op_follow(a, "Reins", "R_Hand.L")


def key(a, frame):
    for pb in a.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def new_action(a, name):
    ad = a.animation_data or a.animation_data_create()
    old = bpy.data.actions.get(CLIP_PREFIX + name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(CLIP_PREFIX + name)
    act.use_fake_user = True
    ad.action = act
    return act


def clip(name, keys):
    """keys: [(frame, ops)] -- every bone keyed at every key frame (no stray carry-over)."""
    a = rigo()
    act = new_action(a, name)
    for frame, ops in keys:
        pose(ops, a)
        key(a, frame)
    a.animation_data.action = None
    reset(a)
    return act


def show(name, frame):
    a = rigo()
    a.animation_data.action = bpy.data.actions[CLIP_PREFIX + name]
    bpy.context.scene.frame_set(frame)


# ------------------------------------------------------------------ helpers ----

def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


HIND_PIVOT = (0.0, 0.97, 0.0)   # between the hind hooves (armature.py HORSE_LEGS hoof points)


def plant_hind(deg, crouch=0.0):
    """Ops that keep the hind legs under a body pitched `deg` nose-up: each thigh turned back
    by the pitch, the hocks sunk by `crouch` (0..1)."""
    ops = []
    for s in "LR":
        ops += [("rot", "HindThigh." + s, (-deg + 20 * crouch, 0, 0)),
                ("rot", "HindShin." + s, (-30 * crouch, 0, 0)),
                ("rot", "HindCannon." + s, (25 * crouch, 0, 0))]
    return ops


def front_tuck(k, s):
    """A foreleg folded up under the chest (k 0..1), the rearing horse's."""
    return [("rot", "FrontUpperArm." + s, (55 * k, 0, 0)),
            ("rot", "FrontForearm." + s, (40 * k, 0, 0)),
            ("rot", "FrontCannon." + s, (-120 * k, 0, 0)),
            ("rot", "FrontHoof." + s, (-30 * k, 0, 0))]


def breathe(u, amp=1.0):
    b = math.sin(2 * math.pi * u * 2) * amp
    return [("rot", "R_Spine", (0.8 * b, 0, 0)), ("rot", "R_Chest", (0.8 * b, 0, 0))]


def horse_idle(u):
    """A halted horse: the weight shifting between the hind legs, a nod, a swish."""
    shift = math.sin(2 * math.pi * u)
    rest_l, rest_r = max(0.0, shift), max(0.0, -shift)
    sw = math.sin(2 * math.pi * u * 2)
    return [("rot", "HindShin.L", (6 * rest_l, 0, 0)), ("rot", "HindCannon.L", (-10 * rest_l, 0, 0)),
            ("rot", "HindShin.R", (6 * rest_r, 0, 0)), ("rot", "HindCannon.R", (-10 * rest_r, 0, 0)),
            ("rot", "Spine1", (0, 0, 1.0 * shift)),
            ("rot", "Neck1", (2.5 * math.sin(2 * math.pi * u + 1.0), 0, 2.0 * shift)),
            ("rot", "Head", (-3.0 * math.sin(2 * math.pi * u + 1.0), 0, 0)),
            ("rot", "Tail1", (0, 0, 10 * sw)), ("rot", "Tail2", (0, 0, 12 * sw)),
            ("rot", "Tail3", (0, 0, 14 * sw))]


# -------------------------------------------------------------------- MARCH ----
# 骑马飞奔: a transverse four-beat gallop -- near hind, off hind, near fore, off fore, then the
# suspension -- each leg on the ground for STANCE of the stride, swinging back under the body;
# the body pitching and bobbing with it, the neck nodding, the tail streaming. The king rides it
# forward-leaning with the sword held up in his right hand.
GALLOP_FRAMES = 24
STANCE = 0.36
GALLOP_PHASE = {"HindHoof.L": 0.00, "HindHoof.R": 0.10, "FrontHoof.L": 0.34, "FrontHoof.R": 0.44}


def _leg_cycle(p):
    """(swing angle -1..1: +1 reached forward, -1 pushed back; flex 0..1) at phase p."""
    p %= 1.0
    if p < STANCE:
        return lerp(1.0, -1.0, p / STANCE), 0.0
    s = (p - STANCE) / (1 - STANCE)
    return lerp(-1.0, 1.0, smooth(s)), math.sin(math.pi * s)


def gallop_pose(u):
    ops = []
    pitch = 4.0 * math.sin(2 * math.pi * (u - 0.20))           # nose up as the hinds land
    bob = 0.05 * math.sin(4 * math.pi * u)
    ops += [("rear", pitch, (0.0, 0.0, 0.0))]
    for s in "LR":
        sw, fl = _leg_cycle(u - GALLOP_PHASE["FrontHoof." + s])
        ops += [("rot", "FrontScapula." + s, (15 * sw, 0, 0)),
                ("rot", "FrontUpperArm." + s, (30 * sw + 12 * fl, 0, 0)),
                ("rot", "FrontForearm." + s, (35 * fl, 0, 0)),
                ("rot", "FrontCannon." + s, (-105 * fl, 0, 0)),
                ("rot", "FrontHoof." + s, (-25 * fl + 8 * max(0, -sw), 0, 0))]
        sw, fl = _leg_cycle(u - GALLOP_PHASE["HindHoof." + s])
        ops += [("rot", "HindThigh." + s, (32 * sw + 12 * fl, 0, 0)),
                ("rot", "HindShin." + s, (-28 * fl, 0, 0)),
                ("rot", "HindCannon." + s, (45 * fl, 0, 0)),
                ("rot", "HindHoof." + s, (-50 * fl, 0, 0))]
    nod = math.sin(2 * math.pi * (u - 0.45))
    ops += [("rot", "Spine1", (1.5 * nod, 0, 0)),
            ("rot", "Neck1", (-10 + 7 * nod, 0, 0)), ("rot", "Neck2", (4 * nod, 0, 0)),
            ("rot", "Head", (8 - 5 * nod, 0, 0)),
            ("rot", "Tail1", (-28 + 5 * nod, 0, 0)), ("rot", "Tail2", (6 + 6 * nod, 0, 0)),
            ("rot", "Tail3", (8 + 8 * math.sin(2 * math.pi * u), 0, 0)),
            ("ground", 0.0)]
    # the king: forward, riding the bob, the sword up and forward in his right fist
    ops += [("rot", "R_Hips", (10 - 6 * bob / 0.05, 0, 0)), ("rot", "R_Spine", (6, 0, 0)),
            ("rot", "R_Chest", (2 * nod, 0, 0)), ("rot", "R_Head", (-12, 0, 0)),
            ("rot", "R_UpperArm.R", (18 + 4 * nod, 0, 0)), ("rot", "R_Forearm.R", (10 - 4 * nod, 0, 0)),
            ("rot", "Sword", (-10, 0, 0)),
            ("rot", "R_Thigh.L", (0, 0, 0)), ("rot", "R_Shin.L", (-6, 0, 0)), ("rot", "R_Shin.R", (-6, 0, 0))]
    return ops


def march():
    n = GALLOP_FRAMES
    return clip("MARCH", [(f, gallop_pose(f / n)) for f in range(0, n + 1, 2)])


# ----------------------------------------------------------------- GARRISON ----
# 驻防: the horse halted and idling; the king's right arm out straight before him, the sword
# pointed forward and a little up, held there breathing.
GARRISON_FRAMES = 120
POINT = {"upper": (0.05, -0.85, 0.35), "fore": (0.08, -1.0, 0.18), "hand": (0.05, -1.0, 0.12),
         "sword": (0.0, -1.0, 0.14)}


def sword_point(u=0.0, amp=1.0):
    w = 0.02 * amp * math.sin(2 * math.pi * u * 2)
    return [("rot", "R_Spine", (4, -6, 0)), ("rot", "R_Chest", (2, -6, 0)),
            ("aim", "R_UpperArm.R", Vector(POINT["upper"]) + Vector((0, 0, w))),
            ("aim", "R_Forearm.R", Vector(POINT["fore"]) + Vector((0, 0, w))),
            ("aim", "R_Hand.R", POINT["hand"]),
            ("aim", "Sword", Vector(POINT["sword"]) + Vector((0, 0, w * 0.5))),
            ("rot", "R_Head", (-4, 0, 0))]


def garrison_pose(u):
    return horse_idle(u) + breathe(u) + sword_point(u)


def garrison():
    n = GARRISON_FRAMES
    return clip("GARRISON", [(f, garrison_pose(f / n)) for f in range(0, n + 1, 10)])


# ------------------------------------------------------------------- ATTACK ----
# 攻击: the horse gathers and rears, forelegs tucked; the king winds the sword back over his
# shoulder, raises it over his head at the top of the rear, and cuts forward and down as the
# horse comes down; the forehand lands and the pair settle. One shot.
ATTACK_FRAMES = 90


def rear_body(deg, tuck, crouch, neck=0.0):
    """The horse pitched `deg` about its hind hooves, forelegs tucked, hocks sunk; the king
    leaning into it so he stays nearly upright."""
    ops = [("rear", deg, HIND_PIVOT), ("loc", "root", (0, -0.10 * crouch, -0.12 * crouch)), ("plant",)]
    for s in "LR":
        ops += front_tuck(tuck, s)
    ops += [("rot", "Neck1", (neck, 0, 0)), ("rot", "Neck2", (neck * 0.5, 0, 0)), ("rot", "Head", (-neck * 0.6, 0, 0)),
            ("aim", "Tail1", (0, 0.45, -1.0)), ("aim", "Tail2", (0, 0.25, -1.0)), ("aim", "Tail3", (0, 0.1, -1.0)),
            ("rot", "R_Hips", (deg * 0.75, 0, 0))]
    return ops


def arm_r(upper, fore, sword, hand=None):
    return [("aim", "R_UpperArm.R", upper), ("aim", "R_Forearm.R", fore),
            ("aim", "R_Hand.R", hand or fore), ("aim", "Sword", sword)]


def attack():
    k = [
        (0, []),
        (14, rear_body(-3, 0.0, 0.5, -6) + [("rot", "R_Spine", (-4, 0, 0))] +
             arm_r((0.15, 0.35, 0.92), (0.1, 0.75, 0.66), (0.05, 0.9, -0.2))),          # gather: sword back over the shoulder
        (30, rear_body(38, 1.0, 0.65, 14) + [("rot", "R_Spine", (4, 0, 0))] +
             arm_r((0.05, 0.05, 1.0), (0.0, 0.55, 0.85), (0.0, 0.85, 0.3))),            # the top: sword raised behind his head
        (40, rear_body(34, 0.9, 0.6, 10) + [("rot", "R_Spine", (18, 0, 0)), ("rot", "R_Chest", (10, 0, 0))] +
             arm_r((0.0, -0.75, 0.66), (0.0, -0.95, 0.1), (0.0, -0.85, -0.5))),          # the cut, forward and down
        (52, rear_body(16, 0.45, 0.35, 4) + [("rot", "R_Spine", (16, 0, 0)), ("rot", "R_Chest", (6, 0, 0))] +
             arm_r((0.05, -0.6, -0.3), (0.15, -0.6, -0.75), (0.25, -0.35, -0.9))),       # follow-through low
        (64, rear_body(-2, 0.0, 0.1, -8) + [("rot", "R_Spine", (8, 0, 0))] +
             arm_r((0.0, -0.35, -0.5), (0.0, -0.9, -0.1), (0.0, -0.6, 0.8))),            # the forehand lands
        (76, rear_body(1, 0.0, 0.0, -2) + [("rot", "R_Spine", (3, 0, 0))]),
        (ATTACK_FRAMES, []),
    ]
    return clip("ATTACK", k)


# ------------------------------------------------------------------- DEFEND ----
# 被攻击: struck at, the horse shies and rears; the king throws the sword up crosswise over his
# head to parry, takes the blow, and the horse comes down. One shot.
DEFEND_FRAMES = 80
PARRY = ((-0.25, -0.05, 0.97), (0.6, -0.1, 0.8), (0.95, -0.1, 0.3))   # upper arm, forearm, the blade across above the crown


def defend():
    jolt = [("loc", "R_Hand.R", (0, 0, -0.04))]
    k = [
        (0, []),
        (10, rear_body(6, 0.2, 0.2, 14) + [("rot", "Head", (10, 0, 12)), ("rot", "R_Spine", (-6, 0, 0))] +
             arm_r((-0.35, -0.2, 0.9), (0.3, -0.35, 0.88), (0.6, -0.4, 0.7))),
        (24, rear_body(28, 0.85, 0.55, 18) + [("rot", "Head", (14, 0, 15)), ("rot", "R_Spine", (-8, 0, 6))] +
             arm_r(*PARRY)),                                                         # the parry up
        (32, rear_body(30, 0.9, 0.6, 16) + [("rot", "Head", (12, 0, 10)), ("rot", "R_Spine", (-12, 0, 6))] +
             arm_r(*PARRY) + jolt),                                                  # the blow lands
        (42, rear_body(24, 0.75, 0.5, 12) + [("rot", "Head", (10, 0, 6)), ("rot", "R_Spine", (-6, 0, 4))] +
             arm_r(*PARRY)),
        (56, rear_body(-2, 0.0, 0.1, -6) + [("rot", "R_Spine", (4, 0, 0))] +
             arm_r((-0.1, -0.3, -0.95), (0.0, -0.9, 0.2), (0.0, -0.4, 0.9))),
        (68, rear_body(1, 0.0, 0.0, -1)),
        (DEFEND_FRAMES, []),
    ]
    return clip("DEFEND", k)


# ------------------------------------------------------------------ STANDBY ----
# 待命: the king on foot at the horse's head, on its off (right) side, facing the way the horse
# faces: the reins in his left hand by the bit, the sword in his right, point down. The horse
# idles; he breathes and glances at it. A loop.
STANDBY_FRAMES = 120
STAND = {"hips": (-0.55, -0.78, 0.89), "yaw": 18.0,
         "rein_hand": (-0.26, -0.98, 1.22)}


def stand_pose(u):
    look = 14.0 * env(u, 0.15, 0.55) - 6.0 * env(u, 0.65, 0.9)
    sway = 0.012 * math.sin(2 * math.pi * u)
    ops = horse_idle(u)
    ops += [("place", "R_Hips", (STAND["hips"][0] + sway, STAND["hips"][1], STAND["hips"][2]), STAND["yaw"])]
    for s, sx in (("L", 1), ("R", -1)):
        ops += [("aim", "R_Thigh." + s, (0.03 * sx, -0.04, -1.0)), ("aim", "R_Shin." + s, (0.0, 0.03, -1.0)),
                ("aim", "R_Foot." + s, (0.12 * sx, -1.0, -0.25))]
    ops += breathe(u, 1.2) + [("rot", "R_Head", (0, look, 0)), ("rot", "R_Neck", (0, look * 0.4, 0))]
    ops += [("ik", "R_Hand.L", STAND["rein_hand"], 3)]
    ops += arm_r((-0.12, -0.05, -1.0), (0.0, -0.45, -0.9), (0.06, -0.3, -1.0), hand=(0.0, -0.6, -0.8))
    return ops


def env(u, a_, b_):
    if u <= a_ or u >= b_:
        return 0.0
    return math.sin(math.pi * (u - a_) / (b_ - a_)) ** 2


def standby():
    n = STANDBY_FRAMES
    return clip("STANDBY", [(f, stand_pose(f / n)) for f in range(0, n + 1, 10)])


def all_clips():
    return [march(), garrison(), attack(), defend(), standby()]
