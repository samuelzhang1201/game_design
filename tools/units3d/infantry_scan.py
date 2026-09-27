"""The infantry piece from two CC0 scans, the cavalry's way (owner 2026-09-27:
"请重新design步兵的3d模型，使用和新的骑兵3d模型一样的方法的套路"; its source,
a Hunyuan3D spearman, is gone with the rest of Hunyuan).

  blender -b --factory-startup --python tools/units3d/infantry_scan.py
  INF_PREVIEW=/tmp/p blender -b --factory-startup --python tools/units3d/infantry_scan.py
      # the prepared scan only, painted by region, shot from four sides

Sources, both CC0-1.0, in assets/units3d/ai_src/cc0/ (git-ignored):
  * graf_salm/ — noe-3d.at "Graf Salm" (Sketchfab db96e431…): the 1867
    statue of Niklas Count Salm on Vienna's Rathausplatz, a man in plate
    with a mail skirt, a sword at his left hip and a long cloak. Like the
    cavalry's Hunt Museum horse, its SHAPE is used and its stone is not: the
    plinth, the helmet at his feet and the baton in his right fist are cut
    away, and his bare head is replaced (owner's pick) by
  * cleveland_armor/ — the cavalry knight's own close helmet (shells
    HELMET_PARTS of the Cleveland 1964.88 scan), so the two arms wear one
    helmet.

The statue is painted procedurally by REGION (plate, mail, cloak, leather,
the sword's steel) — boxes and capsules read off tools/units3d's slice plots,
in the statue's own frame — and baked, like the horse's coat. Then the
cavalry's recipe: the scan collapsed to BODY_TRIS, its detail kept as a baked
tangent normal map, ONE 2048 atlas material, a spear and a heater shield
built by model_cavalry.py's lofts, the humanoid skeleton and actions of
make_units.py (GARRISON / MARCH / ATTACK, bone for bone the old infantry's,
so the game and reanimate.py need nothing changed), no base.
"""
import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Vector, Matrix

HERE = "/Users/samuelzhang/game_design/tools/units3d"
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import importlib
import model_cavalry as mc
import cavalry_scan as cs
import make_units as mu
importlib.reload(mc)
importlib.reload(cs)
from unit_common import OUT, log, tri_count

SRC = "/Users/samuelzhang/game_design/assets/units3d/ai_src/cc0/"
NAME = "infantry"
BODY_TRIS = 9000
HELMET_TRIS = 1400
ATLAS = cs.ATLAS
HELMET_PARTS = {1, 28, 29, 30}     # Cleveland shells: the face and visor, the skull's two halves
# (the skull's back is the top of the Cleveland backplate's shell; taken with
# the helmet, its thin collar flanges survived the collapse as bare shards the
# bake missed, so the helmet is worn open-backed over a steel collar instead)
HELMET_TILT_DEG = -8.0             # face down a little: a man on foot looks ahead, not up

# The statue's own frame, after turning it to face +Y (his right hand at +X):
# the plinth's top is at z = PLINTH_Z, his body's axis at (0, AXIS_Y). The
# piece is that frame moved onto the axis, the plinth top to z = 0, and
# scaled by K (the statue is over life size; K brings the helmet's comb to
# ~1.85 m).
PLINTH_Z = 0.079
AXIS_Y = -0.22
K = 0.93


def P(x, y, z):
    """A point measured on the statue, in the piece's frame."""
    return Vector(((x) * K, (y - AXIS_Y) * K, (z - PLINTH_Z) * K))


# Cuts, in the statue's frame.
HELM_AT_FEET = dict(x_min=0.165, z_max=0.445, y_min=-0.455)      # the helmet by his right foot
HEAD = dict(axis=(-0.005, -0.27), r=0.18, z_min=1.685)           # his bare head, hair and beard
BATON = ((0.395, -0.140, 0.935), (0.455, -0.070, 0.855), 0.034)  # fist edge -> end, radius

# Joints, in the statue's frame (measured off the gridded front and side shots).
J = {
    "pelvis": (0.0, -0.22, 0.98), "belly": (0.0, -0.22, 1.13), "chest": (0.0, -0.23, 1.32),
    "neck": (0.0, -0.25, 1.62), "head": (0.0, -0.26, 1.72), "crown": (0.0, -0.26, 2.00),
    "shoulder_r": (0.24, -0.27, 1.62), "elbow_r": (0.37, -0.24, 1.30), "wrist_r": (0.385, -0.17, 1.02),
    "fist_r": (0.39, -0.14, 0.95),
    "shoulder_l": (-0.24, -0.27, 1.60), "elbow_l": (-0.37, -0.27, 1.24), "wrist_l": (-0.33, -0.15, 1.12),
    "fist_l": (-0.31, -0.11, 1.10),
    # contrapposto: his right leg stands back, fused into the cloak behind it,
    # his left forward (read off point-cloud slices, not the side shot, where
    # the near knee is the LEFT one)
    "hip_r": (0.10, -0.24, 0.98), "knee_r": (0.115, -0.25, 0.69), "ankle_r": (0.065, -0.33, 0.17),
    "toe_r": (0.05, -0.10, 0.04),
    "hip_l": (-0.10, -0.20, 0.98), "knee_l": (-0.125, -0.10, 0.69), "ankle_l": (-0.20, -0.19, 0.17),
    "toe_l": (-0.25, 0.07, 0.04),
}


# ------------------------------------------------------------ sources ----

def statue_bmesh():
    objs = cs.import_gltf(SRC + "graf_salm/scene.gltf")
    bm = cs.world_bmesh(objs)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    bm.transform(Matrix.Rotation(math.pi, 4, "Z"))      # the statue faces -Y: turn him to +Y
    # sixteen chunks whose seams share positions, not vertices: weld them
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
    return bm


def cut(bm):
    """The plinth, the helmet at his feet, his head and the baton."""
    hx, hy = HEAD["axis"]
    a, b, r = Vector(BATON[0]), Vector(BATON[1]), BATON[2]
    ab = b - a

    def baton(c):
        t = (c - a).dot(ab) / ab.length_squared
        if t < 0.0 or t > 1.25:
            return False
        return (c - (a + ab * t)).length < r

    gone = []
    for v in bm.verts:
        c = v.co
        if c.z < PLINTH_Z:
            gone.append(v)
        elif c.z < HELM_AT_FEET["z_max"] and c.x > HELM_AT_FEET["x_min"] and c.y > HELM_AT_FEET["y_min"]:
            gone.append(v)
        elif c.z > HEAD["z_min"] and math.hypot(c.x - hx, c.y - hy) < HEAD["r"]:
            gone.append(v)
        elif baton(c):
            gone.append(v)
    bmesh.ops.delete(bm, geom=gone, context="VERTS")
    keep_big(bm)


def keep_big(bm):
    """Drop the crumbs a cut leaves: every loose piece under 2% of the biggest."""
    parts = cs.loose_parts(bm)
    big = max(len(p) for p in parts)
    keep = {i for p in parts if len(p) > 0.02 * big for i in p}
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context="VERTS")


def close_holes(bm):
    """The cuts leave holes: cap them. Returns the number of patch faces."""
    before = set(bm.faces)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    new = [f for f in bm.faces if f not in before]
    bmesh.ops.triangulate(bm, faces=new)
    new = [f for f in bm.faces if f not in before]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return len(new)


# The cloak ends at the knee (owner 2026-09-27: 把披风截到膝盖). The statue is
# one solid scan and the cloak hid the backs of his lower legs — his right
# shin, standing back, is fused into it — so below the hem the cloak is cut
# away and his right lower leg is replaced by his LEFT one, which stands clear
# of the cloak and is whole, mirrored and turned onto the right knee and ankle.
CLOAK_HEM_Z = 0.635             # statue frame: just under the knee cop
CLOAK_HEM_WAVE = 0.015          # the hem is not ruled straight
SHIN_SWAP_Z = 0.60              # the right leg is replaced below this...
SHIN_TAKE_Z = 0.625             # ...by the left leg below this (the overlap fuses in the remesh)
SHIN_R, FOOT_R = 0.10, 0.085    # what of his left leg is leg, below the hem
CURTAIN_M = 0.03                # a face reaching this far under the hem from a flattened vertex is torn


def left_to_right():
    """His left lower leg mirrored and turned onto his right knee and ankle."""
    kl, al = Vector(J["knee_l"]), Vector(J["ankle_l"])
    kl.x, al.x = -kl.x, -al.x
    kr, ar = Vector(J["knee_r"]), Vector(J["ankle_r"])
    turn = (al - kl).rotation_difference(ar - kr).to_matrix().to_4x4()
    return Matrix.Translation(kr) @ turn @ Matrix.Translation(-kl) @ Matrix.Scale(-1.0, 4, (1, 0, 0))


# the right foot is the left one now, so its toe is where the left toe lands
J["toe_r"] = tuple(left_to_right() @ Vector(J["toe_l"]))


def shorten_cloak(bm):
    import numpy as np
    bm.verts.ensure_lookup_table()
    co = np.array([v.co[:] for v in bm.verts])
    reg = regions(co)
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    hem = CLOAK_HEM_Z + CLOAK_HEM_WAVE * np.sin(x * 23.0 + y * 17.0)
    # below the hem only his left leg and the scabbard stay: the hem's folds
    # lying on his feet were painted as sabaton, and would float once cut free
    leg_l = (_seg_dist(co, J["knee_l"], J["ankle_l"]) < SHIN_R) | \
            ((_seg_dist(co, J["ankle_l"], J["toe_l"]) < FOOT_R) & (z < 0.24))
    scab = _seg_dist(co, (-0.262, -0.215, 0.10), (-0.258, -0.200, 1.02)) < 0.05
    # FLATTENED onto the hem, not deleted: the scan is one closed solid, and
    # cutting it open at the hem left a ring of holes no fill could close
    # (the remesh then fell to pieces and bone heat with it); pressed flat,
    # everything under the hem folds into the hem's own underside and the
    # surface stays closed
    # (the scan's scabbard goes flat too — fused into the cloak, it stretched
    # the cloak's faces into a curtain — and a lofted one hangs in its place)
    under = (z < hem) & (((reg == CLOAK) | ~leg_l) | ((x > -0.02) & (z < SHIN_SWAP_Z)))
    for i in np.nonzero(under)[0]:
        bm.verts[int(i)].co.z = float(hem[i])
    # where the cloak was fused to his left leg, a face now spans from the
    # flattened hem down to the leg: a curtain. Cut those; close_holes caps the
    # small rings they leave round the leg
    flat = set(int(i) for i in np.nonzero(under)[0])
    bm.faces.ensure_lookup_table()
    curtain = [f for f in bm.faces
               if any(v.index in flat for v in f.verts)
               and any(v.index not in flat and v.co.z < hem[v.index] - CURTAIN_M for v in f.verts)]
    bmesh.ops.delete(bm, geom=curtain, context="FACES")
    keep_big(bm)

    # his left lower leg, clear of the scabbard beside it
    bm.verts.ensure_lookup_table()
    co = np.array([v.co[:] for v in bm.verts])
    reg = regions(co)
    near = np.minimum(_seg_dist(co, J["knee_l"], J["ankle_l"]), _seg_dist(co, J["ankle_l"], J["toe_l"]))
    scab = _seg_dist(co, (-0.262, -0.215, 0.10), (-0.258, -0.200, 1.02)) < 0.05
    take = (co[:, 2] < SHIN_TAKE_Z) & (near < 0.15) & (reg != LEATHER) & ~scab & (co[:, 0] < -0.02)
    leg = bm.copy()
    leg.verts.ensure_lookup_table()
    bmesh.ops.delete(leg, geom=[leg.verts[i] for i in np.nonzero(~take)[0]], context="VERTS")
    leg.transform(left_to_right())
    bmesh.ops.reverse_faces(leg, faces=leg.faces)          # the mirror turned it inside out
    me = bpy.data.meshes.new("inf_leg_tmp")
    leg.to_mesh(me)
    leg.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    return int(take.sum())


# ------------------------------------------------------------ regions ----
# Every vertex of the statue gets one region; the bake paints it.
STEEL, MAIL, CLOAK, LEATHER = 0, 1, 2, 3


def _seg_dist(co, a, b):
    import numpy as np
    a, b = np.array(a), np.array(b)
    ab = b - a
    t = np.clip(((co - a) @ ab) / float(ab @ ab), 0.0, 1.0)
    return np.linalg.norm(co - (a + t[:, None] * ab), axis=1)


def regions(co):
    """co: (n, 3) in the statue's frame -> region per vertex."""
    import numpy as np
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    d = lambda a, b: _seg_dist(co, J[a], J[b])
    plate = np.zeros(len(co), bool)
    # the trunk, but never its back: the cloak hangs down all of it
    plate |= (d("pelvis", "neck") < 0.205) & (y > -0.36)
    # the tassets and the skirt flare out over the hips
    plate |= (z > 0.84) & (z < 1.24) & (y > -0.33) & (np.hypot(x, (y + 0.22) * 1.3) < 0.285)
    for s in ("r", "l"):
        plate |= d("hip_" + s, "knee_" + s) < 0.11
        plate |= np.linalg.norm(co - np.array(J["knee_" + s]), axis=1) < 0.13     # the knee cop
        plate |= d("knee_" + s, "ankle_" + s) < 0.09
        plate |= (d("ankle_" + s, "toe_" + s) < 0.12) & (z < 0.28)        # the sabatons
        plate |= (d("ankle_" + s, "toe_" + s) < 0.15) & (z < 0.11)        # and their tips
    # his left arm is bare plate; his right upper arm is under the cloak's drape
    plate |= (d("shoulder_l", "elbow_l") < 0.085) & (y > -0.36)
    plate |= d("elbow_l", "fist_l") < 0.075
    plate |= d("elbow_r", "wrist_r") < 0.080
    plate |= d("wrist_r", "fist_r") < 0.075
    # the drape across his chest, right shoulder to left hip
    sash = [(0.12, -0.20, 1.69), (-0.05, -0.08, 1.47), (-0.19, -0.08, 1.29), (-0.23, -0.10, 1.17)]
    band = np.full(len(co), 9.0)
    for a, b in zip(sash, sash[1:]):
        band = np.minimum(band, _seg_dist(co, a, b))
    plate &= ~((band < 0.058) & (y > -0.25))
    reg = np.where(plate, STEEL, CLOAK)
    # mail: the skirt's scalloped fringe (the codpiece's mail read as a black box)
    mail = plate & (z > 0.84) & (z < 0.925) & (y > -0.30)
    reg = np.where(mail, MAIL, reg)
    # the scabbard down his left side; the hilt and its guard stay steel
    scab = _seg_dist(co, (-0.262, -0.215, 0.13), (-0.258, -0.200, 1.02)) < 0.036
    reg = np.where(scab, LEATHER, reg)
    hilt = (_seg_dist(co, (-0.13, -0.16, 1.085), (-0.38, -0.19, 1.085)) < 0.036) | \
           (_seg_dist(co, (-0.258, -0.200, 1.00), (-0.25, -0.18, 1.21)) < 0.042)
    reg = np.where(hilt & ~plate, STEEL, reg)
    return reg


# (albedo linear, roughness, metallic) per region
# The plate matches the helmet it wears (the Cleveland scan baked: ~(0.24,
# 0.19, 0.16) linear, roughness ~0.63, metallic ~0.9) once the patina and the
# AO below have darkened it — painted darker, it read black on the map beside
# the knight — so helmet and body are one metal and the two arms one army;
# the cloak is the old infantry's red, deeper.
LOOK = {STEEL: ((0.29, 0.245, 0.21), 0.58, 0.75),
        MAIL: ((0.19, 0.165, 0.14), 0.70, 0.65),
        CLOAK: ((0.22, 0.033, 0.024), 0.92, 0.0),
        LEATHER: ((0.075, 0.034, 0.016), 0.62, 0.0)}


def paint(me, reg):
    """Two colour attributes the bake reads: `albedo` and `mr` (G roughness,
    B metallic, glTF's packing)."""
    import numpy as np
    n = len(me.vertices)
    alb = np.ones((n, 4), np.float32)
    mr = np.ones((n, 4), np.float32)
    for k, (rgb, rough, metal) in LOOK.items():
        m = reg == k
        alb[m, :3] = rgb
        mr[m, 1] = rough
        mr[m, 2] = metal
    for name, arr in (("albedo", alb), ("mr", mr)):
        a = me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
        a.data.foreach_set("color", arr.ravel())


def statue_source():
    bm = statue_bmesh()
    cut(bm)
    took = shorten_cloak(bm)
    patched = close_holes(bm)
    me = bpy.data.meshes.new("inf_body_high")
    bm.to_mesh(me)
    bm.free()
    for layer in list(me.uv_layers):
        me.uv_layers.remove(layer)
    import numpy as np
    n = len(me.vertices)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    paint(me, regions(co.reshape(n, 3)))
    me.transform(Matrix.Scale(K, 4) @ Matrix.Translation((0.0, -AXIS_Y, -PLINTH_Z)))
    log("statue: %d verts, %d faces, %d patch faces, a %d-vertex left shin for the right" % (n, len(me.polygons), patched, took))
    return mc.link(bpy.data.objects.new("inf_body_high", me))


def helmet_source():
    """The cavalry knight's close helmet, set on the statue's neck."""
    rider = cs.rider_source()          # the knight alone, in the cavalry's frame
    mat = rider.data.materials[0]
    bm = bmesh.new()
    bm.from_mesh(rider.data)
    bpy.data.objects.remove(rider, do_unlink=True)
    parts = cs.loose_parts(bm)         # HELMET_PARTS index the knight's own shells
    keep = {i for k, p in enumerate(parts) if k in HELMET_PARTS for i in p}
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context="VERTS")
    # onto the statue's neck: its rim's centre on the head's axis, its rim at
    # the collar, sized to the statue (life size x 1.08), then into the piece
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    z0 = min(v.co.z for v in bm.verts)
    c = Vector(((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, z0))
    hx, hy = HEAD["axis"]
    # (the knight's head is carried a little back in the saddle: tip it forward)
    bm.transform(Matrix.Translation(P(hx, hy + 0.012, 1.635)) @ Matrix.Rotation(math.radians(HELMET_TILT_DEG), 4, "X")
                 @ Matrix.Scale(1.08 * K, 4) @ Matrix.Translation(-c))
    me = bpy.data.meshes.new("inf_helmet_high")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    return mc.link(bpy.data.objects.new("inf_helmet_high", me))


# ------------------------------------------------------------ preview ----

def preview(out, objs):
    """The prepared scans painted flat by region, four sides, one sheet."""
    sc = bpy.context.scene
    for e in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = e
            break
        except TypeError:
            pass
    sc.render.resolution_x, sc.render.resolution_y = 800, 1000
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.55, 0.58, 0.62, 1)
    sc.world = w
    sun = mc.link(bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")))
    sun.data.energy = 3.0
    mat = bpy.data.materials.new("inf_preview")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = "albedo"
    nt.links.new(at.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.6
    for o in objs:
        if o.data.color_attributes.get("albedo"):
            o.data.materials.clear()
            o.data.materials.append(mat)
    cam = mc.link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.2
    t = Vector((0, -0.05, 0.95))
    for name, yaw in (("front", 0), ("right", 90), ("back", 180), ("left", 270), ("q", 35)):
        a = math.radians(yaw)
        d = Vector((math.sin(a), math.cos(a), 0.15)).normalized()
        cam.location = t + d * 6
        cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
        sun.rotation_euler = (-(d + Vector((0.5, 0, 1.0)))).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = "%s_%s.png" % (out, name)
        bpy.ops.render.render(write_still=True)


# -------------------------------------------------------------- props ----
# The spear stands upright in his right fist, its butt on the ground; the
# heater hangs on his left forearm, over the sword, its face outward.
SPEAR_TOP = 2.30
SHIELD_C = (-0.475, -0.19, 1.15)        # statue frame: outboard of the left forearm's middle
SHIELD_SCALE = 1.12
SHIELD_TURN_DEG = -60.0


def gorget():
    """A steel collar from inside his cuirass up into the helmet: with the
    statue's neck cut away, the helmet's open back showed sky under it."""
    hx, hy = HEAD["axis"]
    ring = [P(hx, hy + 0.01, z) for z in (1.56, 1.64, 1.72, 1.80)]
    g = mc.loft("gorget", ring, [(0.068, 0.074), (0.064, 0.070), (0.060, 0.066), (0.058, 0.064)],
                segs=12, part="steel")
    g["bone"] = "neck"
    return [g]


SCABBARD = ((-0.258, -0.200, 1.02), (-0.262, -0.215, 0.16))     # statue frame: throat to chape


def scabbard():
    """The sword's scabbard from under his hip to a hand above the ground."""
    top, end = P(*SCABBARD[0]), P(*SCABBARD[1])
    at = lambda t: top.lerp(end, t)
    out = [mc.loft("scabbard", [at(0.0), at(0.5), at(0.94)], [(0.030, 0.018), (0.027, 0.016), (0.022, 0.013)],
                   segs=10, side=Vector((0, 1, 0)), part="leather"),
           mc.loft("chape", [at(0.93), at(0.985), at(1.0)], [(0.024, 0.015), (0.020, 0.012), (0.006, 0.006)],
                   segs=10, side=Vector((0, 1, 0)), part="steel")]
    for p in out:
        p["bone"] = "hips"
    return out


def spear():
    g = P(*J["fist_r"])
    at = lambda z: Vector((g.x, g.y, z))
    L = SPEAR_TOP
    out = [mc.loft("spear_shaft", [at(0.01), at(0.40 * L), at(0.86 * L)],
                   [(0.021, 0.021), (0.022, 0.022), (0.018, 0.018)], segs=8, part="wood"),
           mc.loft("spear_ferrule", [at(0.0), at(0.035)], [(0.022, 0.022), (0.023, 0.023)], segs=8, part="steel"),
           mc.loft("spear_socket", [at(0.855 * L), at(0.90 * L)], [(0.020, 0.020), (0.016, 0.016)], segs=8, part="steel"),
           mc.loft("spear_head", [at(0.90 * L), at(0.925 * L), at(0.965 * L), at(L)],
                   [(0.015, 0.012), (0.040, 0.008), (0.026, 0.006), (0.002, 0.002)],
                   segs=8, side=Vector((1, 0, 0)), part="steel")]
    for p in out:
        p["bone"] = "spear"
    return out


def shield():
    """model_cavalry's heater, the cavalry's arms, hung on his left forearm."""
    saved = (mc.V, mc.OY)
    try:
        mc.OY = 0.0
        mc.V = lambda x, y, z: Vector((x, y, z))
        pieces = mc.shield()
    finally:
        mc.V, mc.OY = saved
    here = Vector((-0.325, 0.25, 1.87))           # where model_cavalry builds it
    boss = next(p for p in pieces if p.name.endswith("boss"))
    c = sum((v.co for v in boss.data.vertices), Vector()) / len(boss.data.vertices)
    boss.data.transform(Matrix.Translation(c) @ Matrix.Scale(0.65, 4) @ Matrix.Translation(-c))
    to = P(*SHIELD_C)
    # model_cavalry's face leans 17 degrees off the horse's line; this one is
    # turned on to face half forward, so the arms read from the front too
    turn = Matrix.Rotation(math.radians(SHIELD_TURN_DEG), 4, "Z")
    m = Matrix.Translation(to) @ turn @ Matrix.Scale(SHIELD_SCALE, 4) @ Matrix.Translation(-here)
    for p in pieces:
        p.data.transform(m)
        p["bone"] = "shield"
    return pieces


# ---------------------------------------------------------------- rig ----

def rig_spec():
    j = {k: P(*v) for k, v in J.items()}
    b = [("root", None, Vector((0, 0, 0)), Vector((0, 0.25, 0))),
         ("hips", "root", j["pelvis"], j["belly"]),
         ("spine", "hips", j["belly"], j["chest"]),
         ("chest", "spine", j["chest"], j["neck"]),
         ("neck", "chest", j["neck"], j["head"]),
         ("head", "neck", j["head"], j["crown"])]
    for s, sx in (("r", 1.0), ("l", -1.0)):
        fist = j["fist_" + s]
        b += [("clavicle_" + s, "chest", P(sx * 0.03, -0.25, 1.58), j["shoulder_" + s]),
              ("upperarm_" + s, "clavicle_" + s, j["shoulder_" + s], j["elbow_" + s]),
              ("forearm_" + s, "upperarm_" + s, j["elbow_" + s], j["wrist_" + s]),
              ("hand_" + s, "forearm_" + s, j["wrist_" + s], fist + (fist - j["wrist_" + s]).normalized() * 0.04),
              ("thigh_" + s, "hips", j["hip_" + s], j["knee_" + s]),
              ("shin_" + s, "thigh_" + s, j["knee_" + s], j["ankle_" + s]),
              ("foot_" + s, "shin_" + s, j["ankle_" + s], j["toe_" + s])]
    g = j["fist_r"]
    c = P(*SHIELD_C)
    b += [("spear", "hand_r", g, g + Vector((0, 0, 0.3))),
          ("shield", "forearm_l", c - Vector((0, 0, 0.1)), c + Vector((0, 0, 0.1)))]
    return b


LEG_BONES = ("thigh_r", "shin_r", "foot_r", "thigh_l", "shin_l", "foot_l")
# the cloak hangs round his legs: past LEG_FULL_M from a leg bone a vertex keeps
# less and less of the leg's weight, LEG_KEEP of it from LEG_FAR_M, the rest
# going to the hips — or a march swings the hem out behind him like a skirt
LEG_FULL_M, LEG_FAR_M, LEG_KEEP = 0.07, 0.20, 0.30


def soften_legs(ob, arm):
    import numpy as np
    bones = {b.name: (np.array(b.head_local), np.array(b.tail_local)) for b in arm.data.bones}
    n = len(ob.data.vertices)
    co = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    d = np.full(n, 9.0)
    for name in LEG_BONES:
        a, b = bones[name]
        ab = b - a
        t = np.clip(((co - a) @ ab) / float(ab @ ab), 0.0, 1.0)
        d = np.minimum(d, np.linalg.norm(co - (a + t[:, None] * ab), axis=1))
    keep = np.clip((LEG_FAR_M - d) / (LEG_FAR_M - LEG_FULL_M), 0.0, 1.0) * (1.0 - LEG_KEEP) + LEG_KEEP
    idx = {g.index: g.name for g in ob.vertex_groups}
    hips = ob.vertex_groups.get("hips") or ob.vertex_groups.new(name="hips")
    moved = 0
    for v in ob.data.vertices:
        if keep[v.index] >= 0.999:
            continue
        spill = 0.0
        for g in v.groups:
            if idx.get(g.group) in LEG_BONES and g.weight > 0.0:
                cut = g.weight * (1.0 - keep[v.index])
                g.weight -= cut
                spill += cut
        if spill > 1e-4:
            hips.add([v.index], spill, "ADD")
            moved += 1
    return moved


BODY_BONES = lambda arm: {b.name for b in arm.data.bones if b.name not in ("root", "spear", "shield")}


# ------------------------------------------------------------- baking ----
TILES = {"body": (0, 0, 3, 3), "helmet": (3, 0, 1, 1), "wood": (3, 1, 1, 1), "steel": (3, 2, 1, 1),
         "shield": (3, 3, 1, 1), "brass": (0, 3, 1, 1), "leather": (1, 3, 1, 1)}
PAINTED = ("wood", "steel", "shield", "brass", "leather")
STEEL_TILE_TINT = (0.80, 0.72, 0.64)


def use_tiles():
    """model_cavalry's lofts and its painted atlas read mc.TILES: point them at
    this atlas, and park what it paints and this atlas never copies (the coat,
    cloth, hair and hoof) inside the body's cells, which the bake overwrites."""
    mc.TILES.clear()
    mc.TILES.update(TILES)
    mc.TILES.update({"coat": (0, 0, 2, 2), "cloth": (2, 0, 1, 1), "hair": (0, 2, 1, 1), "hoof": (1, 2, 1, 1)})


def new_image(name, colour, fill):
    img = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    img.generated_color = fill
    return img


def paint_tiles(col, mr):
    import numpy as np
    ccol, cmr = mc.paint_atlas()
    a = np.array(ccol.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    m = np.array(cmr.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    c = np.array(col.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    b = np.array(mr.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    cell = ATLAS // 4
    for key in PAINTED:
        u0, v0, du, dv = TILES[key]
        ys, xs = slice(v0 * cell, (v0 + dv) * cell), slice(u0 * cell, (u0 + du) * cell)
        c[ys, xs] = a[ys, xs]
        b[ys, xs] = m[ys, xs]
    # model_cavalry's steel is a cool bright grey; the collar, the spear's iron
    # and the shield's rim take the plate's warm dark steel instead
    u0, v0, du, dv = TILES["steel"]
    c[v0 * cell:(v0 + dv) * cell, u0 * cell:(u0 + du) * cell, :3] *= STEEL_TILE_TINT
    col.pixels.foreach_set(c.ravel())
    mr.pixels.foreach_set(b.ravel())
    bpy.data.images.remove(ccol)
    bpy.data.images.remove(cmr)


def attribute_emitter(name, attr, grain):
    """Emits a colour attribute of the painted scan, for an EMIT bake. With
    `grain`, the colour is mottled (a broad wash of +-grain) and speckled
    (small dark pits), the patina the Cleveland knight's own plate has."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_name = attr
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    if not grain:
        nt.links.new(at.outputs["Color"], em.inputs["Color"])
        return mat
    tc = nt.nodes.new("ShaderNodeTexCoord")
    colour = at.outputs["Color"]
    for scale, lo, hi, stops in ((14.0, 1.0 - grain, 1.0 + grain, (0.3, 0.7)),     # the wash
                                 (240.0, 0.58, 1.0, (0.58, 0.68))):               # the pits
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = scale
        noise.inputs["Detail"].default_value = 4.0
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = stops[0]
        ramp.color_ramp.elements[1].position = stops[1]
        if scale > 100:          # dark pits where the noise runs high
            ramp.color_ramp.elements[0].color = (hi, hi, hi, 1)
            ramp.color_ramp.elements[1].color = (lo, lo, lo, 1)
        else:
            ramp.color_ramp.elements[0].color = (lo, lo, lo, 1)
            ramp.color_ramp.elements[1].color = (hi, hi, hi, 1)
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(colour, mix.inputs["A"])
        nt.links.new(ramp.outputs["Color"], mix.inputs["B"])
        colour = mix.outputs["Result"]
    nt.links.new(colour, em.inputs["Color"])
    return mat


AO_FLOOR = 0.60          # the darkest a fold goes: albedo x (floor + (1 - floor) x ao)


def shade_body(body, highs, col):
    """Ambient occlusion baked on the collapsed body (its own shape, the helmet,
    spear and shield round it) and multiplied into its cells of the albedo:
    painted flat, plate and cloak read as one smooth lump from the map."""
    import numpy as np
    sc = bpy.context.scene
    for h in highs:
        h.hide_render = True
    ao = new_image(NAME + "_ao", False, (1.0, 1.0, 1.0, 1))
    mat = body.data.materials[0]
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = ao
    for n in mat.node_tree.nodes:
        n.select = False
    node.select = True
    mat.node_tree.nodes.active = node
    mc.activate(body)
    sc.render.bake.use_selected_to_active = False
    sc.render.bake.use_clear = True
    sc.render.bake.margin = cs.BAKE_MARGIN
    sc.world = sc.world or bpy.data.worlds.new("inf_world")
    sc.world.light_settings.distance = 0.35
    sc.cycles.samples = 64
    bpy.ops.object.bake(type="AO")
    sc.cycles.samples = 1
    mat.node_tree.nodes.remove(node)
    a = np.array(ao.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)[..., :1]
    c = np.array(col.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    cell = ATLAS // 4
    u0, v0, du, dv = TILES["body"]
    ys, xs = slice(v0 * cell, (v0 + dv) * cell), slice(u0 * cell, (u0 + du) * cell)
    c[ys, xs, :3] *= AO_FLOOR + (1.0 - AO_FLOOR) * a[ys, xs]
    col.pixels.foreach_set(c.ravel())
    bpy.data.images.remove(ao)
    for h in highs:
        h.hide_render = False


def atlas_material(col, nor, mr):
    mat = cs.atlas_material(col, nor, mr)
    mat.name = NAME + "_atlas"
    return mat


def reduce_body(high):
    """Voxel-remeshed (closes the cuts' seams, and bone heat wants a sound
    mesh), collapsed to the budget, unwrapped into the body's cells."""
    low = high.copy()
    low.data = high.data.copy()
    low.name = low.data.name = "inf_body"
    mc.link(low)
    for layer in list(low.data.uv_layers):
        low.data.uv_layers.remove(layer)
    for a in list(low.data.color_attributes):
        low.data.color_attributes.remove(a)
    got = mu.retopologise(low, 0.006, BODY_TRIS)
    bm = bmesh.new()
    bm.from_mesh(low.data)
    keep_big(bm)                     # a crumb the remesh leaves makes bone heat fail outright
    bm.to_mesh(low.data)
    bm.free()
    mc.unwrap(low)
    low["part"] = "body"
    mc.into_tile(low)
    mc.activate(low)
    bpy.ops.object.shade_smooth()
    log("body: %d tris" % got)
    return low


def reduce_helmet(high):
    low = high.copy()
    low.data = high.data.copy()
    low.name = low.data.name = "inf_helmet"
    mc.link(low)
    for layer in list(low.data.uv_layers):
        low.data.uv_layers.remove(layer)
    d = low.modifiers.new("decimate", "DECIMATE")
    d.ratio = min(1.0, HELMET_TRIS / max(1, len(high.data.polygons)))
    mc.apply_mods(low)
    mc.unwrap(low)
    low["part"] = "helmet"
    mc.into_tile(low)
    mc.activate(low)
    bpy.ops.object.shade_smooth()
    return low


# -------------------------------------------------------------- build ----

def fresh_scene():
    if bpy.app.background:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        return bpy.context.scene
    sc = bpy.data.scenes.get("infantry_c") or bpy.data.scenes.new("infantry_c")
    bpy.context.window.scene = sc
    for ob in list(sc.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    return sc


def build(write=True):
    sc = fresh_scene()
    use_tiles()
    colls = (bpy.data.materials, bpy.data.images, bpy.data.meshes, bpy.data.textures)
    before = {id(c): {d.name for d in c} for c in colls}
    body_high = statue_source()
    helmet_high = helmet_source()
    if os.environ.get("INF_PREVIEW"):
        preview(os.environ["INF_PREVIEW"], [body_high, helmet_high])
        return
    body = reduce_body(body_high)
    helmet = reduce_helmet(helmet_high)
    pieces = gorget() + scabbard() + spear() + shield()
    for p in pieces:
        if not p.data.uv_layers:
            mc.unwrap(p)
        mc.into_tile(p)
        mc.activate(p)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(50))

    # the atlas: the props' tiles painted, then the two scans baked into theirs
    col = new_image(NAME + "_atlas", True, (0.5, 0.5, 0.5, 1))
    nor = new_image(NAME + "_atlas_n", False, (0.5, 0.5, 1.0, 1))
    mr = new_image(NAME + "_atlas_mr", False, (1.0, 0.6, 0.0, 1))
    paint_tiles(col, mr)
    mat = atlas_material(col, nor, mr)
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 1
    sc.cycles.device = "GPU"
    for low in (body, helmet):
        low.data.materials.clear()
        low.data.materials.append(mat)
    body_high.data.materials.clear()
    body_high.data.materials.append(attribute_emitter("inf_emit_albedo", "albedo", 0.22))
    cs.bake_into(body, body_high, col, "EMIT")
    body_high.data.materials[0] = attribute_emitter("inf_emit_mr", "mr", 0.0)
    cs.bake_into(body, body_high, mr, "EMIT")
    cs.bake_into(body, body_high, nor, "NORMAL")
    shade_body(body, [body_high, helmet_high], col)
    scan_mat = helmet_high.data.materials[0]
    helmet_high.data.materials[0] = cs.emit_material_from(scan_mat, "albedo")
    cs.bake_into(helmet, helmet_high, col, "EMIT")
    helmet_high.data.materials[0] = cs.emit_material_from(scan_mat, "mr")
    cs.bake_into(helmet, helmet_high, mr, "EMIT")
    cs.bake_into(helmet, helmet_high, nor, "NORMAL")
    for img in (col, nor, mr):
        img.pack()
    nt = mat.node_tree
    for n in [n for n in nt.nodes if n.name.startswith("bake_")]:
        nt.nodes.remove(n)

    # the rig and the weights: the body by bone heat, the rest rigid
    arm = cs.build_rig(rig_spec())
    arm.name = arm.data.name = NAME + "_rig"
    how = mc.heat(body, arm, BODY_BONES(arm))
    log("cloak: %d vertices handed from the legs to the hips" % soften_legs(body, arm))
    mc.rigid(helmet, "head")
    for p in pieces:
        mc.rigid(p, p["bone"])
    mc.activate(body)
    for p in [helmet] + pieces:
        p.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = ob.data.name = NAME
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for poly in ob.data.polygons:
        poly.material_index = 0
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    mod = ob.modifiers.new("rig", "ARMATURE")
    mod.object = arm
    ob.parent = arm
    for o in (body_high, helmet_high):
        o.hide_set(True)
        o.hide_render = True

    for c in colls:        # what importing the scans left behind, and only that
        for d in [d for d in c if d.name not in before[id(c)] and d.users == 0]:
            c.remove(d)

    # make_units' humanoid actions, bone for bone the old infantry's; named
    # infantry_* so a live file's other GARRISON cannot collide, the glTF
    # clips taking the NLA tracks' bare names
    h = round(max(v.co.z for v in ob.data.vertices if v.co.z < SPEAR_TOP * 0.85), 3)
    sc.render.fps = mu.FPS
    acts = mu.humanoid_actions(arm, h)
    for a in acts:
        a.name = NAME + "_" + a.name
    mu.stash(arm, acts)
    for track in arm.animation_data.nla_tracks:
        track.name = track.name[len(NAME) + 1:]
    tris = tri_count(ob)
    log("infantry (scans): %d tris, %d bones, body weights %s, figure %.2f m" % (tris, len(arm.data.bones), how, h))
    if write:
        out_dir = os.environ.get("INF_OUT", OUT)
        path = os.path.join(out_dir, NAME + ".glb")
        mc.export_glb([arm, ob], path)
        if out_dir == OUT:
            mpath = os.path.join(OUT, "units3d.json")
            manifest = json.load(open(mpath))
            manifest[NAME] = {
                "label": "Man-at-arms", "kind": "humanoid",
                "height_m": h,
                "source": "CC0 scans (noe-3d.at Graf Salm statue, Cleveland Museum of Art 1964.88 helmet), tools/units3d/infantry_scan.py",
                "tris": tris, "bones": len(arm.data.bones), "weights": how,
                "actions": {a.name[len(NAME) + 1:]: [int(a.frame_range[0]), int(a.frame_range[1])] for a in acts},
                "fps": mu.FPS,
            }
            with open(mpath, "w") as f:
                json.dump(manifest, f, indent=1, sort_keys=True)
                f.write("\n")
        log("wrote " + path)
    blend = os.environ.get("INF_BLEND")
    if blend and bpy.app.background:
        save_blend(arm, acts, blend)
    return arm, ob


def save_blend(arm, acts, path):
    """A .blend to open by hand: the piece alone, the GARRISON loop playing."""
    for name in ("inf_body_high", "inf_helmet_high"):
        o = bpy.data.objects.get(name)
        if o:
            bpy.data.objects.remove(o, do_unlink=True)
    garrison = next(a for a in acts if a.name.endswith("GARRISON"))
    ad = arm.animation_data
    ad.action = garrison
    if getattr(garrison, "slots", None):
        try:
            ad.action_slot = garrison.slots[0]
        except Exception:
            pass
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = [int(f) for f in garrison.frame_range]
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)
    log("saved " + path)


if __name__ in ("__main__", "live"):
    build()
