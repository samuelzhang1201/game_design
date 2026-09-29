"""Seat the CC0 base-mesh man on the scan horse (courier model v3).

The realistic male body (human.load_body: +Y forward, 1.75 m, A-pose) gets:
  1. its fingers curled into fists (a bend deformer past the knuckle line, towards the
     palm, before any rig);
  2. a temporary 17-bone armature laid on joints measured off the mesh itself (centroids
     of the limb near guessed joints), bone-heat weights;
  3. the seated pose: thighs forward and out round the barrel, shins down the flanks to
     the stirrups, feet forward, upper arms hanging a little forward, forearms to the
     reins (the LEFT hand further out, on the pennon's pole);
  4. the pose applied and the rig thrown away (the unit's own rig comes later), then the
     body moved so its seat rests on the saddle.
Knee and ankle are placed off the horse's own flank (probe), so the legs hug the saddle
cloth instead of passing through it.
"""
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree

HERE = __file__.rsplit("/", 1)[0]
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import human

SEAT_Y = 0.24            # the hip joints' y on the horse
SEAT_TOP = 1.522         # where the seat bones rest (the saddle's seat)
CURL = 3.3               # radians of finger curl, knuckle to tip


def verts(ob):
    return [v.co.copy() for v in ob.data.vertices]


def centroid_near(co, p, r, side=0):
    pts = [c for c in co if (c - p).length < r and (side == 0 or c.x * side > 0.005)]
    return sum(pts, Vector()) / len(pts) if pts else p


def measure(ob):
    co = verts(ob)
    J = {}
    # the hip joint sits inside the thigh's top: the surface centroid there is dragged
    # outward by the buttock and the flank, so take its y and z but the socket's own x
    J["hip"] = centroid_near(co, Vector((0.095, -0.05, 0.90)), 0.07, 1)
    J["hip"].x = 0.092
    J["knee"] = centroid_near(co, Vector((0.135, -0.08, 0.49)), 0.06, 1)
    J["ankle"] = centroid_near(co, Vector((0.17, -0.12, 0.09)), 0.05, 1)
    foot = [c for c in co if c.z < 0.06 and c.x > 0.05]
    J["toe"] = Vector((J["ankle"].x, max(c.y for c in foot), 0.025))
    J["shoulder"] = centroid_near(co, Vector((0.18, -0.05, 1.42)), 0.06, 1)
    J["elbow"] = centroid_near(co, Vector((0.30, -0.05, 1.145)), 0.045, 1)
    J["wrist"] = centroid_near(co, Vector((0.40, -0.02, 0.905)), 0.04, 1)
    tip = max(co, key=lambda c: c.x)
    J["tip"] = tip
    for name, z in (("pelvis", 0.95), ("spine", 1.12), ("chest", 1.30), ("neck", 1.47), ("head", 1.56), ("crown", 1.75)):
        sl = [c for c in co if abs(c.z - z) < 0.012 and abs(c.x) < 0.2]
        J[name] = Vector((0.0, sum(c.y for c in sl) / len(sl) if sl else -0.04, z))
    return J


def curl_fingers(ob, J):
    """A bend deformer per hand: past the knuckle line the fingers roll towards the palm."""
    me = ob.data
    for s in (1, -1):
        W = J["wrist"] * Vector((s, 1, 1))
        T = J["tip"] * Vector((s, 1, 1))
        a = (T - W).normalized()
        L = (T - W).length
        # everything past the wrist's plane on that side, out of the thigh's reach
        hand = [v for v in me.vertices if (v.co - W).dot(a) > -0.01 and (v.co - W).length < 0.3
                and v.co.x * s > 0.28]
        # the palm faces the thigh in the A-pose: the medial direction, square to the hand
        n = Vector((-s, 0.0, 0.0))
        n = (n - a * n.dot(a)).normalized()
        b = a.cross(n)
        sk_ = 0.46 * L                      # the knuckles
        Lmax = max((v.co - W).dot(a) for v in hand)
        R = (Lmax - sk_) / CURL             # the furthest fingertip curls exactly CURL
        # the thumb: the side of the hand whose verts reach furthest out close to the wrist
        def side_count(sg):
            return sum(1 for v in hand if sg * (v.co - W).dot(b) > 0.028 and (v.co - W).dot(a) < 0.6 * Lmax)
        st = 1 if side_count(1) > side_count(-1) else -1
        thumb = {v.index for v in hand if st * (v.co - W).dot(b) > 0.02 and (v.co - W).dot(a) < 0.8 * Lmax
                 and (v.co - W).dot(a) > 0.05 * Lmax}
        base = W + a * (0.18 * Lmax) + b * (st * 0.02)
        rot = Matrix.Rotation(-0.85 * st, 3, a)   # the thumb folds across the palm
        for v in hand:
            if v.index in thumb:
                w = min(1.0, max(0.0, ((v.co - W).dot(a) - 0.1 * Lmax) / (0.25 * Lmax)))
                q = base + rot @ (v.co - base)
                v.co = v.co.lerp(q, w)
        for v in hand:
            if v.index in thumb:
                continue
            d = v.co - W
            sa, tn, ub = d.dot(a), d.dot(n), d.dot(b)
            if sa <= sk_:
                continue
            th = (sa - sk_) / R
            dd = R - tn
            s2 = sk_ + dd * math.sin(th)
            t2 = R - dd * math.cos(th)
            v.co = W + a * s2 + n * t2 + b * ub


BONES = [  # name, head key, tail key, parent
    ("pelvis", "pelvis", "spine", None),
    ("spine", "spine", "chest", "pelvis"),
    ("chest", "chest", "neck", "spine"),
    ("neck", "neck", "head", "chest"),
    ("head", "head", "crown", "neck"),
]
LIMBS = [  # name, head, tail, parent
    ("thigh", "hip", "knee", "pelvis"),
    ("shin", "knee", "ankle", "thigh"),
    ("foot", "ankle", "toe", "shin"),
    ("clavicle", "neckbase", "shoulder", "chest"),
    ("upper_arm", "shoulder", "elbow", "clavicle"),
    ("forearm", "elbow", "wrist", "upper_arm"),
    ("hand", "wrist", "tip", "forearm"),
]


def build_rig(J):
    J = dict(J)
    J["neckbase"] = Vector((0.03, J["chest"].y, 1.43))
    arm = bpy.data.armatures.new("tmp_rig")
    ob = bpy.data.objects.new("tmp_rig", arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    for name, h, t, par in BONES:
        b = eb.new(name)
        b.head, b.tail = J[h], J[t]
        if par:
            b.parent = eb[par]
    for s, sfx in ((1, ".R"), (-1, ".L")):
        m = Vector((s, 1, 1))
        for name, h, t, par in LIMBS:
            b = eb.new(name + sfx)
            b.head, b.tail = J[h] * m, J[t] * m
            b.parent = eb[par + sfx] if par + sfx in eb else eb[par]
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def skin(body, rig):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    # loose bits bone heat may miss (the eyes): give them to the head
    head = body.vertex_groups.get("head")
    unweighted = [v.index for v in body.data.vertices if not v.groups]
    if unweighted and head:
        head.add(unweighted, 1.0, "REPLACE")
    return len(unweighted)


def horse_probe(horse):
    bm = bmesh.new()
    bm.from_mesh(horse.data)
    tree = BVHTree.FromBMesh(bm)
    bm.free()

    def side(y, z):
        loc, _, _, _ = tree.ray_cast(Vector((2.0, y, z)), Vector((-1, 0, 0)))
        return loc.x if loc else 0.2
    return side


def pose(rig, J, side):
    """Point each bone at its seated direction (armature space = world here)."""
    pb = rig.pose.bones
    rest = {b.name: b for b in rig.data.bones}
    # where the seated body's hips will be, in the rig's own (standing) frame
    hipC = (J["hip"] + J["hip"] * Vector((-1, 1, 1))) / 2
    shift = Vector((0.0, SEAT_Y - hipC.y, 0.0))            # only for probing the horse
    lift = None
    targets = {}
    Lt = (J["knee"] - J["hip"]).length
    Ls = (J["ankle"] - J["knee"]).length
    # the seat: the hips sit SEAT_TOP + (hip - buttock) up; measured after, so probe roughly
    z_hip = SEAT_TOP + 0.085
    for s, sfx in ((1, ".R"), (-1, ".L")):
        hip = Vector((J["hip"].x * s, SEAT_Y, z_hip))
        kz = z_hip - 0.30
        ky = SEAT_Y + 0.22
        kx = (side(ky, kz) if s > 0 else -side(ky, kz) * 0)
        kx = max(abs(side(ky, kz)), 0.27) + 0.085
        knee_dir = (Vector((kx * s, ky, kz)) - hip).normalized()
        knee = hip + knee_dir * Lt
        az = knee.z - Ls * 0.97
        ay = knee.y - 0.07
        ax = max(abs(side(ay, az + 0.05)), 0.2) + 0.062
        shin_dir = (Vector((ax * s, ay, az)) - knee).normalized()
        targets["thigh" + sfx] = knee_dir
        targets["shin" + sfx] = shin_dir
        targets["foot" + sfx] = Vector((0.03 * s, 0.93, -0.36)).normalized()
        targets["upper_arm" + sfx] = Vector((0.10 * s, 0.30, -0.95)).normalized()
    # forearms: to the wrists at the reins (the left one out on the pole)
    wrists = {".R": Vector((0.13, SEAT_Y + 0.33, z_hip + 0.13)),
              ".L": Vector((-0.20, SEAT_Y + 0.33, z_hip + 0.14))}
    order = ["pelvis", "spine", "chest", "neck", "head"]
    for sfx in (".R", ".L"):
        order += ["thigh" + sfx, "shin" + sfx, "foot" + sfx, "clavicle" + sfx, "upper_arm" + sfx,
                  "forearm" + sfx, "hand" + sfx]
    for name in order:
        b = rest[name]
        p = pb[name]
        if name.startswith("forearm") or name.startswith("hand"):
            sfx = name[-2:]
            bpy.context.view_layer.update()
            elbow_world = pb["upper_arm" + sfx].tail + shift + Vector((0, 0, z_hip - hipC.z))
            d = (wrists[sfx] - elbow_world).normalized()
            if name.startswith("hand"):
                d = (d + Vector((0, 0, -0.08))).normalized()     # the fist carries the forearm on
            targets[name] = d
        if name not in targets:
            continue
        rest_dir = (b.tail_local - b.head_local).normalized()
        q = rest_dir.rotation_difference(targets[name])
        bpy.context.view_layer.update()
        if b.parent:
            par = pb[b.parent.name]
            head = par.matrix @ (b.parent.matrix_local.inverted() @ b.head_local)
        else:
            head = b.head_local
        R = q.to_matrix().to_4x4() @ Matrix(b.matrix_local.to_3x3()).to_4x4()
        p.matrix = Matrix.Translation(head) @ R
    bpy.context.view_layer.update()


def seat(body, horse):
    """Curl, rig, pose, apply; returns the POSED joints (world, after the move onto the
    saddle) and each vertex's body part (the bone that weighed most on it)."""
    J = measure(body)
    curl_fingers(body, J)
    rig = build_rig(J)
    n_un = skin(body, rig)
    pose(rig, J, horse_probe(horse))
    # each vertex's part, before the groups go
    names = {g.index: g.name for g in body.vertex_groups}
    parts = []
    for v in body.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        parts.append(names[best.group] if best else "head")
    bpy.context.view_layer.update()
    PJ = {}
    for pb in rig.pose.bones:
        PJ[pb.name + ":h"] = rig.matrix_world @ pb.head
        PJ[pb.name + ":t"] = rig.matrix_world @ pb.tail
    bpy.context.view_layer.objects.active = body
    for o in bpy.context.selected_objects:
        o.select_set(False)
    body.select_set(True)
    mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    bpy.ops.object.modifier_apply(modifier=mod.name)
    body.parent = None
    body.matrix_world = Matrix.Identity(4)
    bpy.data.objects.remove(rig, do_unlink=True)
    for g in list(body.vertex_groups):
        body.vertex_groups.remove(g)
    co = verts(body)
    hipC = (PJ["thigh.R:h"] + PJ["thigh.L:h"]) / 2
    seatz = min(c.z for c in co if abs(c.x) < 0.12 and abs(c.y - hipC.y) < 0.15 and c.z < hipC.z + 0.3)
    move = Vector((0.0, SEAT_Y - hipC.y, SEAT_TOP - seatz))
    body.data.transform(Matrix.Translation(move))
    for k in PJ:
        PJ[k] = PJ[k] + move
    return PJ, parts, n_un


def seat_mr(body, eyes, horse):
    """v3: as seat(), on the Multires body - the rig is weighted on the cage, the sculpt
    (Multires at its level) is applied first and the pose over it; the eyes follow the
    head bone rigidly and are joined in LAST (costume.regions reads them there)."""
    import bmesh as _bm
    me = body.data
    J = measure(body)
    curl_fingers(body, J)
    rig = build_rig(J)
    n_un = skin(body, rig)
    pose(rig, J, horse_probe(horse))
    bpy.context.view_layer.update()
    PJ = {}
    for pb in rig.pose.bones:
        PJ[pb.name + ":h"] = rig.matrix_world @ pb.head
        PJ[pb.name + ":t"] = rig.matrix_world @ pb.tail
    head_pb = rig.pose.bones["head"]
    head_M = head_pb.matrix @ rig.data.bones["head"].matrix_local.inverted()
    for e in eyes:
        e.data.transform(head_M)
    bpy.context.view_layer.objects.active = body
    for o in bpy.context.selected_objects:
        o.select_set(False)
    body.select_set(True)
    for m in list(body.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)       # Multires first, then the pose
    body.parent = None
    body.matrix_world = Matrix.Identity(4)
    bpy.data.objects.remove(rig, do_unlink=True)
    names = {g.index: g.name for g in body.vertex_groups}
    parts = []
    for v in body.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        parts.append(names[best.group] if best else "head")
    for g in list(body.vertex_groups):
        body.vertex_groups.remove(g)
    # the eyes in, last
    bm = _bm.new()
    bm.from_mesh(body.data)
    for e in eyes:
        bm.from_mesh(e.data)
        parts += ["head"] * len(e.data.vertices)
        bpy.data.objects.remove(e, do_unlink=True)
    bm.to_mesh(body.data)
    bm.free()
    co = verts(body)
    hipC = (PJ["thigh.R:h"] + PJ["thigh.L:h"]) / 2
    seatz = min(c.z for c in co if abs(c.x) < 0.12 and abs(c.y - hipC.y) < 0.15 and c.z < hipC.z + 0.3)
    move = Vector((0.0, SEAT_Y - hipC.y, SEAT_TOP - seatz))
    body.data.transform(Matrix.Translation(move))
    for k in PJ:
        PJ[k] = PJ[k] + move
    return PJ, parts, n_un


if __name__ == "__main__":
    import scan_horse
    horse = scan_horse.horse_high()
    body = human.load_body()
    PJ, parts, n_un = seat(body, horse)
    co = verts(body)
    print("RIDER", len(co), "unweighted", n_un, "z", round(min(c.z for c in co), 3), round(max(c.z for c in co), 3))
    for k in ("thigh.R:h", "shin.R:h", "foot.R:h", "upper_arm.L:h", "forearm.L:h", "hand.L:h", "hand.R:h", "head:h", "head:t"):
        print("J", k, tuple(round(x, 3) for x in PJ[k]))
    from collections import Counter
    print("PARTS", Counter(parts))
