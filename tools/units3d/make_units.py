"""Build the game's 3D military units from their Hunyuan3D sources.

  blender -b --factory-startup --python tools/units3d/make_units.py [-- CODE ...]

Reads data/screens/map3d/unit_models.csv and writes assets/3D/units/<code>/<code>.glb — one glTF
per unit holding TWO things:

  * the retopologised, texture-baked figure, skinned to a skeleton,
  * that skeleton, carrying its actions, GARRISON, MARCH and ATTACK.

There is no base (owner 2026-09-27: 撤除所有底座; until then a separate,
unskinned disc stood under each figure): the feet stand on z = 0.

The retopo half is tools/map3d/retopo_houses.py's, proven on the houses:
voxel remesh the AI's marching-cubes surface, ONE collapse pass down to the
budget, then bake the original's albedo and normal onto the result through an
explicit cage. Two of that script's steps are deliberately NOT here:

  * solidify() — the houses are hollow shells whose remesh needs wall
    thickness. A Hunyuan character is already a closed solid; solidifying it
    inward eats the spear shaft and the fingers.
  * strip_base_plate() — these sources came out with no ground disc at all
    (the prompt refused one), and the pieces stand on no base anyway.

Every joint position is a FRACTION of the figure's measured height, not a
number in metres, so re-generating a source at another scale changes nothing
here. The fractions are anthropometric standards for the man and measured off
this pack's horse for the mount; tools/units3d/measure_units.py prints the
slice profile they were read from.
"""

import bpy
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unit_common import (ROOT, OUT, SRC, glb_path, rows, clear, import_joined, place,
                         bounds, tri_count, apply_transform, log)

BAKE_PX = 2048
# The cage offset is a LENGTH, so it has to follow the figure's size: the
# houses' fixed 1.2 m would swallow a soldier whole.
CAGE_FRACTION = 0.022        # of the figure's height
DESPECKLE_RATIO = 0.55
DESPECKLE_FLOOR = 0.18

FPS = 30


# --------------------------------------------------------------- retopo ----

def repair(ob):
    """Weld, drop degenerate faces and point every normal outward.

    Collapse decimation leaves slivers behind, and a face with no usable
    normal gets a bake ray pointing anywhere at all — which is what the black
    patches on the houses' walls were. Bone-heat weighting is just as fussy:
    a degenerate face makes its solver fail outright.
    """
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=bm.edges)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    stray = [e for e in bm.edges if not e.link_faces]
    if stray:
        bmesh.ops.delete(bm, geom=stray, context="EDGES")
    bmesh.ops.holes_fill(bm, edges=bm.edges, sides=8)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    # The last word, and not a nicety: Blender reported this mesh "not valid"
    # and bone heat then failed to solve for a SINGLE bone on the horse — it
    # is a warning, not an error, so the build went on and shipped a rider
    # and a mount welded to the exporter's neutral_bone, animated and
    # perfectly motionless. validate() is what stops that at the source.
    ob.data.validate(verbose=False)
    ob.data.update()


def retopologise(ob, voxel_m, budget):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    m = ob.modifiers.new("remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel_m
    bpy.ops.object.modifier_apply(modifier=m.name)
    got = tri_count(ob)
    if got > budget:
        m = ob.modifiers.new("decimate", "DECIMATE")
        m.ratio = float(budget) / float(got)
        bpy.ops.object.modifier_apply(modifier=m.name)
    repair(ob)
    return tri_count(ob)


def unwrap(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


def make_cage(low, offset):
    """A copy of the low poly pushed out along SMOOTHED normals.

    Blender's automatic cage offsets along the low poly's OWN normal, which on
    a decimated voxel remesh is jagged — neighbouring rays set off in quite
    different directions and one of them finds nothing at all. Smoothing the
    normals over one ring first fixes the direction rather than the distance.
    The cage must keep the low poly's exact topology, so it is built by moving
    vertices, never by a modifier.
    """
    import bmesh
    cage = low.copy()
    cage.data = low.data.copy()
    cage.name = low.name + "_cage"
    bpy.context.scene.collection.objects.link(cage)
    bm = bmesh.new()
    bm.from_mesh(cage.data)
    bm.verts.ensure_lookup_table()
    smoothed = []
    for v in bm.verts:
        n = v.normal.copy()
        for e in v.link_edges:
            n += e.other_vert(v).normal
        if n.length > 1e-9:
            n.normalize()
        smoothed.append(n)
    for v, n in zip(bm.verts, smoothed):
        v.co += n * offset
    bm.to_mesh(cage.data)
    bm.free()
    return cage


def despeckle(image):
    """Replace dark outlier texels with their 3x3 median.

    A ray aimed through a gap in the source's own skin carries on and lands
    on the inside, which comes back near black. Those texels are outliers
    against their own neighbourhood, so a texel is replaced only when it is
    much darker than the median around it AND that median is itself light —
    a genuinely dark region (a visor slit, black leather) keeps every texel.
    """
    import numpy as np
    w, h = image.size
    buf = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = buf[:, :, :3]
    stack = np.stack([np.roll(np.roll(rgb, dy, axis=0), dx, axis=1)
                      for dy in (-1, 0, 1) for dx in (-1, 0, 1)], axis=0)
    med = np.median(stack, axis=0)
    dark = ((rgb.mean(axis=2) < med.mean(axis=2) * DESPECKLE_RATIO)
            & (med.mean(axis=2) > DESPECKLE_FLOOR))
    if dark.any():
        rgb[dark] = med[dark]
        buf[:, :, :3] = rgb
        image.pixels[:] = buf.reshape(-1)
    return int(dark.sum())


def bake_surface(low, high, tag, cage_offset):
    low.data.materials.clear()
    mat = bpy.data.materials.new("unit_" + tag)
    mat.use_nodes = True
    low.data.materials.append(mat)
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")

    images = {}
    for kind, colorspace in (("albedo", "sRGB"), ("normal", "Non-Color")):
        im = bpy.data.images.new("%s_%s" % (tag, kind), BAKE_PX, BAKE_PX, alpha=False)
        im.colorspace_settings.name = colorspace
        images[kind] = im
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = im
        node.name = kind

    cage = make_cage(low, cage_offset)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.render.bake.use_cage = True
    scene.render.bake.cage_object = cage

    for kind, bake_type, extra in (("albedo", "DIFFUSE", {"pass_filter": {"COLOR"}}),
                                   ("normal", "NORMAL", {})):
        for n in nt.nodes:
            n.select = False
        nt.nodes[kind].select = True
        nt.nodes.active = nt.nodes[kind]
        bpy.ops.object.select_all(action="DESELECT")
        high.select_set(True)
        low.select_set(True)
        bpy.context.view_layer.objects.active = low
        bpy.ops.object.bake(type=bake_type, use_selected_to_active=True,
                            use_cage=True, margin=max(4, BAKE_PX // 128), **extra)

    scene.render.bake.use_cage = False
    scene.render.bake.cage_object = None
    bpy.data.objects.remove(cage, do_unlink=True)
    despeckle(images["albedo"])

    nt.links.new(nt.nodes["albedo"].outputs["Color"], bsdf.inputs["Base Color"])
    nrm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nt.nodes["normal"].outputs["Color"], nrm.inputs["Color"])
    nt.links.new(nrm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.72
    bsdf.inputs["Metallic"].default_value = 0.0
    for im in images.values():
        im.pack()


# ------------------------------------------------------------ skeletons ----
#
# Every coordinate below is a FRACTION of the unit's own measured height, so
# the same table fits a source regenerated at any scale. The man's fractions
# are ordinary anthropometric standards (hip joint at 0.53 of stature, knee
# at 0.285, shoulder at 0.815, elbow at 0.63, wrist at 0.485); the horse's
# were read off this pack's own source with tools/units3d/measure_units.py —
# its slice profile is what put the withers at 0.537 and the hocks at 0.167.
#
# The figure faces +Y with +Z up, so its RIGHT hand is at +X.

def humanoid_spec(h):
    sw, ew, ww = 0.097 * h, 0.115 * h, 0.130 * h   # shoulder, elbow, wrist
    lw, aw = 0.050 * h, 0.058 * h                  # hip joint, ankle
    bones = [
        ("root",   None,    (0, 0, 0),           (0, 0.25 * h, 0)),
        ("hips",   "root",  (0, 0, 0.530 * h),   (0, 0, 0.600 * h)),
        ("spine",  "hips",  (0, 0, 0.600 * h),   (0, 0, 0.700 * h)),
        ("chest",  "spine", (0, 0, 0.700 * h),   (0, 0, 0.815 * h)),
        ("neck",   "chest", (0, 0, 0.815 * h),   (0, 0, 0.870 * h)),
        ("head",   "neck",  (0, 0, 0.870 * h),   (0, 0, 1.000 * h)),
    ]
    for side, s in (("r", 1.0), ("l", -1.0)):
        bones += [
            ("clavicle_" + side, "chest",
             (s * 0.020 * h, 0, 0.805 * h), (s * sw, 0, 0.815 * h)),
            ("upperarm_" + side, "clavicle_" + side,
             (s * sw, 0, 0.815 * h), (s * ew, 0, 0.630 * h)),
            ("forearm_" + side, "upperarm_" + side,
             (s * ew, 0, 0.630 * h), (s * ww, 0, 0.485 * h)),
            ("hand_" + side, "forearm_" + side,
             (s * ww, 0, 0.485 * h), (s * ww, 0.020 * h, 0.430 * h)),
            ("thigh_" + side, "hips",
             (s * lw, 0, 0.530 * h), (s * lw, 0, 0.285 * h)),
            ("shin_" + side, "thigh_" + side,
             (s * lw, 0, 0.285 * h), (s * aw, 0, 0.055 * h)),
            ("foot_" + side, "shin_" + side,
             (s * aw, 0, 0.055 * h), (s * aw, 0.075 * h, 0.005 * h)),
        ]
    return bones


def mounted_spec(h):
    lw = 0.067 * h                                  # half the horse's track
    rw, re, rr = 0.070 * h, 0.081 * h, 0.093 * h    # rider shoulder/elbow/hand
    bones = [
        ("root",       None,   (0, 0, 0),                    (0, 0.25 * h, 0)),
        ("horse_body", "root", (0, -0.230 * h, 0.463 * h),   (0, 0.204 * h, 0.537 * h)),
        ("horse_neck", "horse_body", (0, 0.204 * h, 0.537 * h), (0, 0.389 * h, 0.722 * h)),
        ("horse_head", "horse_neck", (0, 0.389 * h, 0.722 * h), (0, 0.500 * h, 0.537 * h)),
        ("horse_tail", "horse_body", (0, -0.267 * h, 0.481 * h), (0, -0.389 * h, 0.167 * h)),
    ]
    for side, s in (("r", 1.0), ("l", -1.0)):
        bones += [
            # fore leg: shoulder -> carpus -> fetlock -> hoof
            ("fore_upper_" + side, "horse_body",
             (s * lw, 0.204 * h, 0.389 * h), (s * lw, 0.230 * h, 0.241 * h)),
            ("fore_lower_" + side, "fore_upper_" + side,
             (s * lw, 0.230 * h, 0.241 * h), (s * lw, 0.259 * h, 0.093 * h)),
            ("fore_hoof_" + side, "fore_lower_" + side,
             (s * lw, 0.259 * h, 0.093 * h), (s * lw, 0.270 * h, 0.007 * h)),
            # hind leg: hip -> stifle -> hock -> hoof
            ("hind_upper_" + side, "horse_body",
             (s * lw, -0.230 * h, 0.426 * h), (s * lw, -0.241 * h, 0.296 * h)),
            ("hind_lower_" + side, "hind_upper_" + side,
             (s * lw, -0.241 * h, 0.296 * h), (s * lw, -0.267 * h, 0.167 * h)),
            ("hind_hoof_" + side, "hind_lower_" + side,
             (s * lw, -0.267 * h, 0.167 * h), (s * lw, -0.267 * h, 0.007 * h)),
        ]
    bones += [
        ("hips",  "horse_body", (0, -0.019 * h, 0.574 * h), (0, -0.007 * h, 0.648 * h)),
        ("spine", "hips",       (0, -0.007 * h, 0.648 * h), (0, 0, 0.722 * h)),
        ("chest", "spine",      (0, 0, 0.722 * h),          (0, 0.007 * h, 0.796 * h)),
        ("neck",  "chest",      (0, 0.007 * h, 0.796 * h),  (0, 0.007 * h, 0.822 * h)),
        ("head",  "neck",       (0, 0.007 * h, 0.822 * h),  (0, 0.007 * h, 0.926 * h)),
    ]
    for side, s in (("r", 1.0), ("l", -1.0)):
        bones += [
            ("clavicle_" + side, "chest",
             (s * 0.007 * h, 0, 0.785 * h), (s * rw, 0, 0.770 * h)),
            ("upperarm_" + side, "clavicle_" + side,
             (s * rw, 0, 0.770 * h), (s * re, 0.018 * h, 0.689 * h)),
            ("forearm_" + side, "upperarm_" + side,
             (s * re, 0.018 * h, 0.689 * h), (s * rr, 0.067 * h, 0.659 * h)),
            ("hand_" + side, "forearm_" + side,
             (s * rr, 0.067 * h, 0.659 * h), (s * rr, 0.089 * h, 0.652 * h)),
            ("thigh_" + side, "hips",
             (s * 0.048 * h, -0.011 * h, 0.574 * h), (s * 0.056 * h, 0.078 * h, 0.537 * h)),
            ("shin_" + side, "thigh_" + side,
             (s * 0.056 * h, 0.078 * h, 0.537 * h), (s * 0.063 * h, 0.089 * h, 0.407 * h)),
        ]
    return bones


SPECS = {"humanoid": humanoid_spec, "mounted": mounted_spec}


def build_armature(name, spec):
    arm_data = bpy.data.armatures.new(name + "_rig")
    arm = bpy.data.objects.new(name + "_rig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for bname, parent, head, tail in spec:
        b = arm_data.edit_bones.new(bname)
        b.head = head
        b.tail = tail
        b.roll = 0.0
        if parent:
            b.parent = made[parent]
            # Connected only where head and tail genuinely coincide: a
            # connected bone drags its parent's tail when it moves, and the
            # arms and legs hang off joints their parent does not end at.
            b.use_connect = (made[parent].tail - b.head).length < 1e-6
        made[bname] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# --------------------------------------------------- skinning and weapon ----

def unweighted_share(ob, arm):
    """The share of vertices no real bone is holding.

    Nothing in Blender raises when weighting fails: bone heat prints a
    warning, leaves the vertices bare, and the glTF exporter quietly invents
    a `neutral_bone` to park them on. The result exports, imports, plays its
    animations and does not move. This is the check that catches it.
    """
    wanted = {b.name for b in arm.pose.bones if b.name != "root"}
    idx = {i: g.name for i, g in enumerate(ob.vertex_groups)}
    bare = 0
    for v in ob.data.vertices:
        if not any(ge.weight > 1e-4 and idx.get(ge.group) in wanted
                   for ge in v.groups):
            bare += 1
    return float(bare) / max(1, len(ob.data.vertices))


def weight_by_distance(ob, arm, power=5.0, k=3):
    """Weight every vertex by its distance to the nearest bone SEGMENTS.

    The fallback for a mesh bone heat will not solve. It is cruder — it knows
    nothing about the surface, only about space, so a vertex can in principle
    be caught by a bone on the other side of a thin wall — but it always
    produces an answer, and at the size a wargame piece is looked at the
    difference does not show. The sharp falloff (distance to the fifth) and
    the three-bone cap are what keep the horse's belly from picking up the
    rider's thigh.
    """
    import numpy as np
    bones = [(b.name, np.array(b.head_local), np.array(b.tail_local))
             for b in arm.data.bones if b.name != "root"]
    n = len(ob.data.vertices)
    co = np.empty(n * 3, dtype=np.float64)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    dist = np.empty((len(bones), n), dtype=np.float64)
    for i, (_, a, b) in enumerate(bones):
        ab = b - a
        denom = float(ab @ ab) or 1.0
        t = np.clip(((co - a) @ ab) / denom, 0.0, 1.0)
        dist[i] = np.linalg.norm(co - (a + t[:, None] * ab), axis=1)
    order = np.argsort(dist, axis=0)[:k]
    near = np.take_along_axis(dist, order, axis=0)
    w = 1.0 / np.power(near + 1e-4, power)
    w /= w.sum(axis=0, keepdims=True)
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    groups = {name: ob.vertex_groups.new(name=name) for name, _, _ in bones}
    for slot in range(k):
        for bi in range(len(bones)):
            idx = np.nonzero((order[slot] == bi) & (w[slot] > 1e-3))[0]
            if len(idx):
                groups[bones[bi][0]].add([int(i) for i in idx],
                                         0.0, "REPLACE")
                for i in idx:
                    groups[bones[bi][0]].add([int(i)], float(w[slot, i]), "ADD")


def skin(ob, arm):
    """Bone-heat weights, with envelopes as the fallback.

    Heat weighting is the one that follows the surface — which is exactly
    what a welded figure needs, because the spear reaches the mesh only
    through the hand and the shield only through the forearm, so the heat
    arrives through the arm and the props come along with it. It refuses to
    solve on a mesh with degenerate faces, which is why repair() runs first.
    """
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    try:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
        bare = unweighted_share(ob, arm)
    except RuntimeError as exc:
        log("bone heat refused outright: %s" % exc)
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        arm.select_set(True)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.parent_set(type="ARMATURE_NAME")
        bare = 1.0
    if bare <= 0.02:
        return "heat"
    log("bone heat left %.1f%% of the vertices bare — weighting by distance"
        % (bare * 100.0))
    weight_by_distance(ob, arm)
    left = unweighted_share(ob, arm)
    if left > 0.001:
        raise RuntimeError("%.2f%% of %s is still unweighted"
                           % (left * 100.0, ob.name))
    return "distance"


def parse_seed(text, h):
    """'x0:x1;y0:y1;z0:z1' in fractions of the height -> a box in metres.

    Semicolons, not commas: the box lives in one CSV cell.
    """
    parts = [p.split(":") for p in text.split(";")]
    return [(float(a) * h, float(b) * h) for a, b in parts]


def lock_weapon(ob, hand_name, hand_head, seed_text, radius, lock_below, h, z0):
    """Make the spear or lance one RIGID stick carried by the hand.

    Bone heat gets the hand and the grip right and the rest of the shaft
    wrong, and it cannot do otherwise: a metre and a half of pole has its own
    bones nearest at every point along it, so the butt drifts toward the leg
    and the head toward the head. The shaft bends like rope the moment the
    arm moves.

    The fix is to treat it as what it is — one rigid body. The CSV's
    `weapon_seed` box is a coarse region that contains only shaft (measured
    with measure_units.py), the shaft's AXIS is fitted through whatever is in
    it, and then every vertex within `weapon_radius_m` of that infinite line
    is pinned to the hand at full weight and to nothing else. Seeding a fit
    rather than naming the whole weapon is what lets one box cover a spear
    that leans and a lance that does not.
    """
    import numpy as np
    box = parse_seed(seed_text, h)
    box[2] = (box[2][0] + z0, box[2][1] + z0)
    co = np.array([v.co[:] for v in ob.data.vertices], dtype=np.float64)
    inside = np.ones(len(co), dtype=bool)
    for axis, (lo, hi) in enumerate(box):
        inside &= (co[:, axis] >= lo) & (co[:, axis] <= hi)
    if inside.sum() < 8:
        raise RuntimeError("weapon seed box caught %d vertices" % inside.sum())
    seed = co[inside]
    centre = seed.mean(axis=0)
    # The longest principal axis of the seed IS the shaft's direction.
    _, _, vh = np.linalg.svd(seed - centre, full_matrices=False)
    axis = vh[0] / np.linalg.norm(vh[0])
    rel = co - centre
    along = rel @ axis
    perp = np.linalg.norm(rel - np.outer(along, axis), axis=1)
    # Cut the cylinder off below the grip — see the note above.
    hand = np.array(hand_head, dtype=np.float64)
    floor = float((hand - centre) @ axis) - lock_below
    if float(seed.mean(axis=0) @ axis) < floor:
        axis, floor = -axis, -floor - 2.0 * lock_below
        along = rel @ axis
        perp = np.linalg.norm(rel - np.outer(along, axis), axis=1)
    shaft = (perp <= radius) & (along >= floor)
    groups = {g.name: g for g in ob.vertex_groups}
    if hand_name not in groups:
        groups[hand_name] = ob.vertex_groups.new(name=hand_name)
    idx = [int(i) for i in np.nonzero(shaft)[0]]
    for g in ob.vertex_groups:
        if g.name != hand_name:
            g.remove(idx)
    groups[hand_name].add(idx, 1.0, "REPLACE")
    return len(idx), int(inside.sum())


def lock_props(ob, spec_text, h, z0):
    """Pin a rigid prop — the kite shield — to one bone by its box alone.

    The shield needs this for a reason the spear does not: it RESTS AGAINST
    the man's side, so it is welded to his torso in the source and bone heat
    flows straight into it from the chest and the hip. Half the shield then
    belongs to the arm and half to the body, and the first frame that turns
    one against the other shears the plate in two — which is exactly what the
    first attack render showed.

    Pinning it to the forearm costs nothing in the pose, because no action
    turns the forearm or the upper arm on that side against each other: the
    left arm is moved at the CLAVICLE, above everything the box caught, so
    the whole assembly swings as one piece and the shoulder still deforms.
    """
    import numpy as np
    if not spec_text.strip():
        return 0
    co = np.array([v.co[:] for v in ob.data.vertices], dtype=np.float64)
    total = 0
    for entry in spec_text.split("|"):
        bone, box_text = entry.split("=")
        box = parse_seed(box_text, h)
        box[2] = (box[2][0] + z0, box[2][1] + z0)
        inside = np.ones(len(co), dtype=bool)
        for axis, (lo, hi) in enumerate(box):
            inside &= (co[:, axis] >= lo) & (co[:, axis] <= hi)
        idx = [int(i) for i in np.nonzero(inside)[0]]
        if not idx:
            raise RuntimeError("prop box for %s caught nothing" % bone)
        group = ob.vertex_groups.get(bone) or ob.vertex_groups.new(name=bone)
        for g in ob.vertex_groups:
            if g.name != bone:
                g.remove(idx)
        group.add(idx, 1.0, "REPLACE")
        total += len(idx)
    return total


# ----------------------------------------------------------- animation ----
#
# A pose names, per bone, a list of WORLD-axis turns and a WORLD translation.
# Both are converted into the bone's own space through its rest matrix, which
# is the only way to write these poses down without guessing Euler signs: a
# bone's local axes depend on the direction it points and its roll, so "+X on
# the upper arm" means one thing for the man and the opposite for the horse's
# hind leg. Said in world axes, +X turns a hanging limb FORWARD, +Z yaws, and
# a lean is the same sign everywhere.

AXES = {"x": (1.0, 0.0, 0.0), "y": (0.0, 1.0, 0.0), "z": (0.0, 0.0, 1.0)}


def apply_pose(arm, pose):
    from mathutils import Vector, Quaternion
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
    for name, entry in pose.items():
        pb = arm.pose.bones.get(name)
        if pb is None:
            raise RuntimeError("no bone " + name)
        rest = pb.bone.matrix_local.to_3x3()
        inv = rest.inverted()
        q = Quaternion((1.0, 0.0, 0.0, 0.0))
        for axis, deg in entry.get("rot", ()):
            local_axis = inv @ Vector(AXES[axis])
            q = q @ Quaternion(local_axis, math.radians(deg))
        pb.rotation_quaternion = q
        if "loc" in entry:
            pb.location = inv @ Vector(entry["loc"])


def key_all(arm, frame):
    for pb in arm.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def action_fcurves(act):
    """Every f-curve of an action, on either side of Blender 4.4's slots.

    A slotted action keeps no `fcurves` at all — the curves hang off
    layer -> strip -> channelbag -> fcurves, one channelbag per slot — and
    reading the old attribute on 5.2 raises rather than returning empty.
    """
    if hasattr(act, "fcurves"):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", ()):
        for strip in getattr(layer, "strips", ()):
            for bag in getattr(strip, "channelbags", ()):
                out.extend(bag.fcurves)
    return out


def make_action(arm, name, keys):
    ad = arm.animation_data or arm.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ad.action = act
    # Blender 4.4+ gives an action slots; keyframe_insert creates and binds one
    # on its own, but an action assigned before any key has none yet.
    for frame, pose in keys:
        apply_pose(arm, pose)
        key_all(arm, frame)
    for fc in action_fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"
    ad.action = None
    return act


def stash(arm, actions):
    """Put each action on its own muted NLA track.

    The glTF exporter's ACTIONS mode writes one animation per action it can
    see, and what it can see is the active action plus the NLA tracks — a
    fake user alone is not enough, which is why all of these are pushed down
    rather than just kept alive.
    """
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for act in actions:
        track = ad.nla_tracks.new()
        track.name = act.name
        strip = track.strips.new(act.name, int(act.frame_range[0]), act)
        strip.name = act.name
        if hasattr(strip, "action_slot") and getattr(act, "slots", None):
            try:
                strip.action_slot = act.slots[0]
            except Exception as exc:          # older / newer API, harmless
                log("slot bind skipped: %s" % exc)
        track.mute = True


# ------------------------------------------------------------- the walk ----

def gait(phase, swing_frac=0.40):
    """One limb's place in a walk cycle: how far the upper joint is swung
    and how far the lower one is folded, both as a SHARE of the limb's own
    amplitude, at `phase` of the stride (0 = the foot plants, farthest
    forward).

    Written as a function rather than as hand-set poses because a horse has
    four legs on four different phases of a four-beat walk, and hand-keying
    sixteen joints through eight beats is how a gait ends up subtly wrong in
    a way nobody can find afterwards. Both halves meet at the hand-over
    (upper is -1 at the end of the stance and at the start of the swing; the
    fold returns to its stance value at the end of the swing), so the loop
    has no step in it.
    """
    p = phase % 1.0
    stance = 1.0 - swing_frac
    if p < stance:
        t = p / stance
        return 1.0 - 2.0 * t, -0.10
    t = (p - stance) / swing_frac
    return -1.0 + 2.0 * t, -0.10 - 1.80 * math.sin(math.pi * t)


def walk_keys(frames, beats, legs, body, amp_upper, amp_lower):
    """Sample `gait` into a list of (frame, pose) around one loop.

    `legs` is (upper_bone, lower_bone, phase) per limb; `body` is a callable
    given the cycle position that adds whatever the trunk does. The last key
    repeats the first, so the action loops without a hitch.
    """
    keys = []
    for i in range(beats + 1):
        u = float(i) / beats
        pose = {}
        for upper, lower, phase in legs:
            a, b = gait(u + phase)
            pose[upper] = {"rot": [("x", a * amp_upper)]}
            pose[lower] = {"rot": [("x", b * amp_lower)]}
        pose.update(body(u))
        keys.append((1 + int(round(u * (frames - 1))), pose))
    return keys


def humanoid_actions(arm, h):
    """GARRISON: a man standing his post, not a statue. ATTACK: a spear thrust.

    The thrust is driven by the LUNGE and the twist of the body, not by
    swinging the arm through the shoulder. That was the first attempt and it
    was wrong on its own terms: the spear is one rigid stick pinned to the
    glove, so turning the arm pivots the whole weapon about the SHOULDER —
    well above the grip — which sends the head arcing down and back past his
    own feet and reads as a man swinging a pole, not thrusting a spear.
    Stepping the root forward carries the whole spear forward instead, which
    is what a thrust actually is.

    The garrison loop is deliberately SMALL — a degree or two of breath, a
    shift of weight, one slow look to the side. A unit standing on a map is
    seen out of the corner of the eye for minutes at a time, and anything
    with a visible beat to it turns into a twitch.
    """
    neutral = {}
    garrison = [
        (1, neutral),
        (31, {"chest": {"rot": [("x", -1.6)]},
              "head": {"rot": [("x", 2.0), ("z", 2.5)]},
              "hips": {"rot": [("z", 2.0)]},
              "upperarm_r": {"rot": [("x", 2.0)]},
              "clavicle_l": {"rot": [("x", -1.0)]}}),
        (61, {"chest": {"rot": [("x", 1.0)]},
              "head": {"rot": [("z", -7.0), ("x", -1.5)]},
              "hips": {"rot": [("z", -1.0)]},
              "upperarm_r": {"rot": [("x", -1.5)]}}),
        (91, {"chest": {"rot": [("x", -1.2)]},
              "head": {"rot": [("z", -3.0), ("x", 1.0)]},
              "hips": {"rot": [("z", -2.2)]},
              "clavicle_l": {"rot": [("x", 1.5)]}}),
        (121, neutral),
    ]
    attack = [
        (1, neutral),
        (11, {"root": {"loc": (0.0, -0.05, 0.0)},
              "hips": {"rot": [("z", -10.0)]},
              "chest": {"rot": [("z", -13.0), ("x", -3.0)]},
              "head": {"rot": [("z", 5.0)]},
              "upperarm_r": {"rot": [("x", -15.0)]},
              "forearm_r": {"rot": [("x", -10.0)]},
              "clavicle_l": {"rot": [("x", 9.0)]},
              "thigh_r": {"rot": [("x", -6.0)]}}),
        (21, {"root": {"loc": (0.0, 0.16, 0.0)},
              "hips": {"rot": [("z", 14.0)]},
              "chest": {"rot": [("z", 19.0), ("x", -11.0)]},
              "head": {"rot": [("z", -4.0), ("x", -5.0)]},
              "upperarm_r": {"rot": [("x", 23.0)]},
              "forearm_r": {"rot": [("x", 7.0)]},
              "clavicle_l": {"rot": [("x", 15.0)]},
              "thigh_l": {"rot": [("x", 20.0)]},
              "shin_l": {"rot": [("x", -16.0)]},
              "thigh_r": {"rot": [("x", -13.0)]}}),
        (30, {"root": {"loc": (0.0, 0.14, 0.0)},
              "hips": {"rot": [("z", 12.0)]},
              "chest": {"rot": [("z", 16.0), ("x", -9.0)]},
              "upperarm_r": {"rot": [("x", 19.0)]},
              "forearm_r": {"rot": [("x", 6.0)]},
              "clavicle_l": {"rot": [("x", 13.0)]},
              "thigh_l": {"rot": [("x", 17.0)]},
              "shin_l": {"rot": [("x", -13.0)]},
              "thigh_r": {"rot": [("x", -11.0)]}}),
        (46, {"root": {"loc": (0.0, 0.05, 0.0)},
              "chest": {"rot": [("z", 5.0)]},
              "upperarm_r": {"rot": [("x", 6.0)]},
              "thigh_l": {"rot": [("x", 5.0)]}}),
        (61, neutral),
    ]
    def foot_body(u: float) -> dict:
        # The pelvis rises twice a stride and the shoulders counter-turn
        # against the hips, which is what stops a walk reading as a shuffle.
        # The SPEAR ARM barely moves: the shaft is one rigid stick pinned to
        # the glove, and a marching spearman shoulders it rather than
        # swinging it.
        # BIG since 2026-09-27 (owner: 行进动作设计幅度再大一点): a longer
        # stride, a bob, the shoulders and the shield arm swinging against
        # the hips — read at map size, a small walk is no walk at all.
        swing = math.sin(2.0 * math.pi * u)
        return {
            "root": {"loc": (0.0, 0.0, abs(math.sin(2.0 * math.pi * u)) * 0.032 * h)},
            "hips": {"rot": [("z", swing * 7.0), ("y", swing * 3.0)]},
            "chest": {"rot": [("z", -swing * 9.0), ("x", -5.0)]},
            "head": {"rot": [("z", -swing * 3.0)]},
            "upperarm_r": {"rot": [("x", swing * 5.0)]},
            "clavicle_l": {"rot": [("x", -swing * 9.0)]},
        }

    march = walk_keys(41, 8,
                      [("thigh_l", "shin_l", 0.0), ("thigh_r", "shin_r", 0.5)],
                      foot_body, 34.0, 34.0)
    return [make_action(arm, "GARRISON", garrison),
            make_action(arm, "ATTACK", attack),
            make_action(arm, "MARCH", march)]


def mounted_actions(arm, h):
    """GARRISON: a horse standing at rest. ATTACK: a rear into a couched lance.

    The rear pivots on horse_body, whose HEAD sits on the croup right where
    the hind hips are — so turning it lifts the forehand while the hind hips
    stay put, and counter-turning the hind upper legs by the same angle keeps
    the hind hooves on the ground instead of swinging them out behind. That
    is the whole trick; without the counter-turn the horse rears by sliding
    backwards through the floor.
    """
    neutral = {}
    garrison = [
        (1, neutral),
        (31, {"horse_body": {"rot": [("x", 1.1)]},
              "horse_neck": {"rot": [("x", -3.0)]},
              "horse_head": {"rot": [("x", 4.0)]},
              "horse_tail": {"rot": [("z", 7.0), ("x", 3.0)]},
              "chest": {"rot": [("x", -1.6)]},
              "head": {"rot": [("z", 4.0)]}}),
        (61, {"horse_neck": {"rot": [("x", 3.0)]},
              "horse_head": {"rot": [("x", -5.0)]},
              "horse_tail": {"rot": [("z", -5.0)]},
              "hips": {"rot": [("x", 1.2)]},
              "head": {"rot": [("z", -3.0), ("x", -2.0)]}}),
        (91, {"horse_body": {"rot": [("x", -0.9)]},
              "horse_head": {"rot": [("x", 3.0)]},
              "horse_tail": {"rot": [("z", 6.0), ("x", -2.0)]},
              "chest": {"rot": [("x", 1.2)]},
              "head": {"rot": [("z", -6.0)]}}),
        (121, neutral),
    ]

    def rear(body, hind, fore_u, fore_l, neck, arm_r, lean, root_y):
        pose = {
            "root": {"loc": (0.0, root_y, 0.0)},
            "horse_body": {"rot": [("x", body)]},
            "horse_neck": {"rot": [("x", neck)]},
            "horse_head": {"rot": [("x", -neck * 0.4)]},
            "horse_tail": {"rot": [("x", -body * 0.5)]},
            "hips": {"rot": [("x", lean * 0.4)]},
            "spine": {"rot": [("x", lean * 0.3)]},
            "chest": {"rot": [("x", lean * 0.3)]},
            "upperarm_r": {"rot": [("x", arm_r)]},
            "forearm_r": {"rot": [("x", arm_r * 0.2)]},
        }
        for side in ("r", "l"):
            pose["hind_upper_" + side] = {"rot": [("x", hind)]}
            pose["hind_lower_" + side] = {"rot": [("x", hind * 0.3)]}
            pose["fore_upper_" + side] = {"rot": [("x", fore_u)]}
            pose["fore_lower_" + side] = {"rot": [("x", fore_l)]}
            pose["thigh_" + side] = {"rot": [("x", -lean * 0.2)]}
        return pose

    attack = [
        (1, neutral),
        (13, rear(-4.0, 4.0, 6.0, -8.0, -4.0, -12.0, 6.0, -0.03)),
        (34, rear(24.0, -24.0, -34.0, -52.0, 10.0, 18.0, -26.0, 0.07)),
        (50, rear(18.0, -18.0, -26.0, -40.0, 8.0, 24.0, -22.0, 0.15)),
        (64, rear(6.0, -6.0, -8.0, -12.0, 3.0, 10.0, -8.0, 0.07)),
        (76, neutral),
    ]
    def horse_body(u: float) -> dict:
        # A four-beat walk puts four small rises in a stride, not two, and
        # the head nods once — the nod is the thing an eye reads as "walking"
        # at map distance, more than any leg.
        nod = math.sin(2.0 * math.pi * u)
        return {
            "root": {"loc": (0.0, 0.0, abs(math.sin(4.0 * math.pi * u)) * 0.008 * h)},
            "horse_body": {"rot": [("x", nod * 1.2)]},
            "horse_neck": {"rot": [("x", nod * 3.5)]},
            "horse_head": {"rot": [("x", -nod * 4.5)]},
            "horse_tail": {"rot": [("z", nod * 5.0)]},
            "hips": {"rot": [("x", -nod * 2.0)]},
            "chest": {"rot": [("x", nod * 1.5)]},
            "upperarm_r": {"rot": [("x", nod * 2.0)]},
        }

    # LH, LF, RH, RF — the four-beat walk, each leg a quarter of a stride
    # behind the last.
    march = walk_keys(49, 12, [
        ("hind_upper_l", "hind_lower_l", 0.00),
        ("fore_upper_l", "fore_lower_l", 0.25),
        ("hind_upper_r", "hind_lower_r", 0.50),
        ("fore_upper_r", "fore_lower_r", 0.75),
    ], horse_body, 15.0, 11.0)
    return [make_action(arm, "GARRISON", garrison),
            make_action(arm, "ATTACK", attack),
            make_action(arm, "MARCH", march)]


ACTIONS = {"humanoid": humanoid_actions, "mounted": mounted_actions}


# --------------------------------------------------------------- export ----

def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    # JPEG like the houses: these are baked photographs drawn small, and a
    # lossless 2048 pair is ~10 MB a unit, committed and again in history on
    # every regeneration.
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True,
        use_active_scene=True,   # else a selection in ANY scene of a live file rides along
        export_yup=True, export_apply=False,
        export_image_format="JPEG", export_jpeg_quality=92,
        export_animations=True, export_animation_mode="ACTIONS",
        export_frame_range=False, export_optimize_animation_size=False,
        export_anim_single_armature=True)


def main():
    import json
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    wanted = set(argv)
    manifest_path = os.path.join(OUT, "units3d.json")
    manifest = {}
    if os.path.exists(manifest_path):
        with open(manifest_path) as f:
            manifest = json.load(f)

    for row in rows():
        code = row["code"]
        if wanted and code not in wanted:
            continue
        if row["source"].endswith(".py"):
            # hand-modelled: built by its own script, never from an AI source
            log("%s is built by tools/units3d/%s — skipped" % (code, row["source"]))
            continue
        src = os.path.join(SRC, row["source"])
        if not os.path.exists(src):
            log("no source for " + code)
            continue
        h = float(row["height_m"])
        z0 = 0.0          # no base any more (owner 2026-09-27): the feet stand on z = 0
        clear()
        bpy.context.scene.render.fps = FPS

        high = import_joined(src, code + "_high")
        place(high, h, float(row["yaw_offset_deg"]))
        src_tris = tri_count(high)

        low = high.copy()
        low.data = high.data.copy()
        low.name = code
        low.data.name = code
        bpy.context.scene.collection.objects.link(low)
        got = retopologise(low, float(row["voxel_m"]), int(row["tris"]))
        unwrap(low)
        bake_surface(low, high, code, CAGE_FRACTION * h)
        bpy.data.objects.remove(high, do_unlink=True)

        spec = [(n, p, (hx, hy, hz + z0), (tx, ty, tz + z0))
                for n, p, (hx, hy, hz), (tx, ty, tz) in SPECS[row["kind"]](h)]
        arm = build_armature(code, spec)
        how = skin(low, arm)
        hand_name = "hand_" + row["weapon_side"]
        hand_head = next(b[2] for b in spec if b[0] == hand_name)
        shaft, seed = lock_weapon(low, hand_name, hand_head, row["weapon_seed"],
                                  float(row["weapon_radius_m"]),
                                  float(row["weapon_lock_below_m"]), h, z0)

        props = lock_props(low, row["rigid_props"], h, z0)

        acts = ACTIONS[row["kind"]](arm, h)
        stash(arm, acts)
        bpy.context.scene.frame_end = int(max(a.frame_range[1] for a in acts))

        path = glb_path(OUT, code)
        export([arm, low], path)
        manifest[code] = {
            "label": row["label"],
            "kind": row["kind"],
            "height_m": round(h, 3),
            "source": "hunyuan3d+retopo",
            "source_tris": src_tris,
            "tris": got,
            "bones": len(spec),
            "weights": how,
            "weapon_verts": shaft,
            "prop_verts": props,
            "actions": {a.name: [int(a.frame_range[0]), int(a.frame_range[1])]
                        for a in acts},
            "fps": FPS,
        }
        log("%s  %d -> %d tris, %d bones, %s weights, weapon %d verts "
            "(seed %d), props %d verts, %s"
            % (code, src_tris, got, len(spec), how, shaft, seed, props,
               ", ".join(sorted(manifest[code]["actions"]))))

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")
    log("wrote " + manifest_path)


if __name__ == "__main__":  # model_cavalry.py imports the helpers below
    main()
