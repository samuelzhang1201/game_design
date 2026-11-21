"""Install build: the ARP heavy knight on the ARP armoured horse as THE cavalry piece
(docs/superpowers/specs/2026-11-21-cavalry-heavy-knight-design.md; owner 2026-11-21: 替换现有骑兵).

Source (git-ignored, read only): assets/3D/model_wip/blender_output/heavy_cavalry/rider_clips.blend
(knight `Knight_body` on ARP rig `rig`, horse `Horse_armored` on ARP rig `horse_rig`, `Spear` on the
knight's `cc_weapon.r` socket; every rider clip an action on `rig` with its horse action in
act["horse"]). Headless, nothing saved:

  Blender -b -y SOURCE.blend --python tools/units3d/cavalry_arp/game_export.py -- ROOT [OUT.json]

What the map needs of the cavalry GLB (README beside this file):
- armature `cavalry_rig`, one skinned mesh `cavalry` (knight + horse + spear, ONE material on one
  atlas whose files keep the old names `cavalry_cavalry_atlas{,_mr,_n}.jpg`);
- the bones the royal pivot solver binds by name (Map3DRoyalPivot._CHAINS): the horse's legs renamed
  FrontScapula / FrontUpperArm / FrontForearm / FrontCannon / FrontHoof .L/.R and HindThigh /
  HindShin / HindCannon / HindHoof .L/.R, and the rider (every knight bone, the stirrups) under a
  bone `Saddle` (cavalry_pivot_plan.json rider_root); the chip's bone `head` is the rider's, the
  horse's head is `head_h`; every other horse bone is prefixed `h_`;
- rest = STANDBY's first frame (mounted, lance upright): the map sizes a piece from its rest mesh;
- clips keyed from frame 0, loops closed on their own period (the clip's frame after its last is its
  first) with any residual spread over the last frames; faces glTF -Z.
- decimated to the game budget by the blender-decimate-quality skill's decikit (knight COLLAPSE,
  spear ends COLLAPSE, the spear's shaft rebuilt as an 8-sided tube); the horse is already in budget.
"""
import importlib.util
import json
import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# Game clip <- source rider clip (owner 2026-11-21 task; defaults recorded in the spec). MARCH is the run;
# ATTACK is the rearing three-stab loop (in place: ATTACK / ATTACK_STAB gallop and would run on the spot);
# PIVOT_LEFT / RIGHT are the source turns, fixtures the provider seeks and never plays. DEATH is not
# shipped: no cavalry caller plays it (army_art.csv has no duel column for the arm), and its rider
# thrown 2.3 m off the horse would widen the body envelope every footprint is measured from (cf01).
GAME = {"MARCH": "MARCH", "STANDBY": "STANDBY", "GARRISON": "GARRISON", "DEFEND": "DEFEND",
        "ATTACK": "ATTACK_REAR_LOOP", "PIVOT_LEFT": "PIVOT_LEFT",
        "PIVOT_RIGHT": "PIVOT_RIGHT"}
LOOPS = {"MARCH", "STANDBY", "GARRISON", "DEFEND", "ATTACK"}
REST = ("STANDBY", 1)
SEAM_FRAMES = 6
# MARCH contacts (the source run: the left hind never comes nearer the ground than 44 mm, the right hind
# 11 mm, the fronts skate; the horse pipeline left the run's fronts unpinned). The 13-frame run is
# resampled DENSE keys a frame (its bones' locals interpolated, as Godot would between the 30 fps keys)
# and each hoof's stance is locked: the cyclic run of keys where its lowest sole point is within
# STANCE_M of its own lowest (or of the ground, where the interpolation dips it under), narrowed to the
# longest part of it whose hoof stays within max_offset_m of a straight path at the run's speed (the
# hind hooves are pinned in the source and set the speed; the fronts skate there), the hoof held rigid (its pose at mid-stance, set down onto the ground)
# and carried straight back at the run's speed; the offset eases out over EASE keys either side, and
# the leg follows by two-bone IK (upper arm / forearm, thigh / shin) with the pastern kept. Off its stance
# a hoof clears the ground by ramp_m a key from the stance's edges up to clear_m (the source's fronts stay
# on the ground for a third of the loop: unlocked, that part skated 0.4 m through the planting band).
DENSE = 8
LOCK = {"stance_m": 0.025, "ease": 16, "max_offset_m": 0.05, "min_keys": 8, "clear_m": 0.025, "ramp_m": 0.004}
KNIGHT, HORSE, SPEAR = "Knight_body", "Horse_armored", "Spear"
SIDES = {".l": ".L", ".r": ".R"}
# horse bone (ARP horse preset) -> game name. The front legs are ARP's `_dupli_001` leg. ARP cuts each
# long bone in two consecutive halves (twist above, stretch below, or stretch above, twist below); the
# solver's chain bone is the half whose origin is the joint, the other half rides it as a side child.
HORSE_CHAIN = {}
for s, S in SIDES.items():
    HORSE_CHAIN.update({
        "c_thigh_b_dupli_001" + s: "FrontScapula" + S, "thigh_twist_dupli_001" + s: "FrontUpperArm" + S,
        "leg_stretch_dupli_001" + s: "FrontForearm" + S, "foot_dupli_001" + s: "FrontCannon" + S,
        "toes_01_dupli_001" + s: "FrontHoof" + S,
        "thigh_twist" + s: "HindThigh" + S, "leg_stretch" + s: "HindShin" + S, "foot" + s: "HindCannon" + S,
        "toes_01" + s: "HindHoof" + S})
HORSE_RENAME = {**HORSE_CHAIN, "head.x": "head_h"}
KNIGHT_RENAME = {"head.x": "head"}
SADDLE_ON = "spine_02.x"       # the horse bone the saddle (and the stirrups) ride
ATLAS = (4096, 2048)           # w, h
# (u0, v0, du, dv) of each part in the atlas, v up as in Blender's UVs and image rows; each region is
# square in pixels: knight 2048, horse 1536, spear 512
REGION = {"knight": (0.0, 0.0, 0.5, 1.0), "horse": (0.5, 0.25, 0.375, 0.75),
          "spear": (0.875, 0.75, 0.125, 0.25)}
GAME_METAL = float(os.environ.get("CAVALRY_GAME_METAL", "0.45"))  # as the infantry: near-pure metal mirrors the dark map and reads black
BUDGET = {"knight": 12000, "spear_ends": 1200}
SHAFT = (-0.53, 1.69, 8, 14)   # spear-local y of the tube's ends, sides, rings (head and butt kept)
SKILL = Path(os.path.expanduser("~/.claude/skills/blender-decimate-quality/scripts/decikit.py"))


def _dk():
    spec = importlib.util.spec_from_file_location("decikit", SKILL)
    dk = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(dk)
    sys.modules["decikit"] = dk
    return dk


def use(name):
    """The rider clip and its horse clip on the two rigs (the source's c10_use.use)."""
    act = bpy.data.actions[name]
    ha = bpy.data.actions[act["horse"]]
    for o, a in ((bpy.data.objects["rig"], act), (bpy.data.objects["horse_rig"], ha)):
        o.animation_data.action = a
        o.animation_data.action_slot = a.slots[0]
    return tuple(map(int, ha.frame_range))


# ----------------------------------------------------------------- skeleton --

def _bones():
    """[(rig, source bone, game name, game parent)] in parent-before-child order, + the Saddle."""
    K, H = bpy.data.objects["rig"], bpy.data.objects["horse_rig"]
    kk = [b.name for b in K.data.bones if b.use_deform] + ["cc_weapon.r"]
    hk = [b.name for b in H.data.bones if b.use_deform]
    kname = {n: KNIGHT_RENAME.get(n, n) for n in kk}
    hname = {n: HORSE_RENAME.get(n, "h_" + n) for n in hk}

    def nearest(rig, keep, n):
        p = rig.data.bones[n].parent
        while p and p.name not in keep:
            p = p.parent
        return p.name if p else None

    par = {}
    for n in hk:
        p = nearest(H, hk, n)
        par[hname[n]] = hname[p] if p else None
    for n in kk:
        p = nearest(K, kk, n)
        par[kname[n]] = kname[p] if p else None
    # anatomical parents where ARP hangs a deform bone off a control (c_traj, the IK chains): the
    # rider's limbs blend in the pivot by their locals, so every joint must be its parent's child
    for s, S in SIDES.items():
        par.update({
            "h_c_thigh_b" + s: "h_root.x", "HindThigh" + S: "h_c_thigh_b" + s,
            "h_thigh_stretch" + s: "HindThigh" + S, "HindShin" + S: "HindThigh" + S,
            "h_leg_twist" + s: "HindShin" + S, "HindCannon" + S: "HindShin" + S, "HindHoof" + S: "HindCannon" + S,
            "FrontScapula" + S: "h_spine_03.x", "FrontUpperArm" + S: "FrontScapula" + S,
            "h_thigh_stretch_dupli_001" + s: "FrontUpperArm" + S, "FrontForearm" + S: "FrontUpperArm" + S,
            "h_leg_twist_dupli_001" + s: "FrontForearm" + S, "FrontCannon" + S: "FrontForearm" + S,
            "FrontHoof" + S: "FrontCannon" + S,
            "h_stirrup" + s: "Saddle", "h_rein_hand" + s: "hand.l",
            "thigh_twist" + s: "root.x", "thigh_stretch" + s: "thigh_twist" + s,
            "leg_stretch" + s: "thigh_stretch" + s, "leg_twist" + s: "leg_stretch" + s,
            "foot" + s: "leg_twist" + s, "toes_01" + s: "foot" + s,
            "shoulder" + s: "spine_03.x", "c_arm_twist_offset" + s: "shoulder" + s,
            "arm_stretch" + s: "shoulder" + s, "cc_couter" + s: "arm_stretch" + s,
            "forearm_stretch" + s: "arm_stretch" + s, "forearm_twist" + s: "forearm_stretch" + s,
            "hand" + s: "forearm_stretch" + s})
    par.update({"h_root.x": None, "h_spine_01.x": "h_root.x", "h_spine_02.x": "h_spine_01.x",
                "h_spine_03.x": "h_spine_02.x", "h_c_subneck_1.x": "h_spine_03.x",
                "h_c_subneck_2.x": "h_c_subneck_1.x", "h_neck.x": "h_c_subneck_2.x", "head_h": "h_neck.x",
                "h_c_tail_00.x": "h_root.x", "root.x": "Saddle", "spine_01.x": "root.x",
                "spine_02.x": "spine_01.x", "spine_03.x": "spine_02.x", "neck.x": "spine_03.x",
                "head": "neck.x", "cc_weapon.r": "hand.r", "Saddle": "h_" + SADDLE_ON})
    src = {hname[n]: (H, n) for n in hk}
    src.update({kname[n]: (K, n) for n in kk})
    src["Saddle"] = (H, SADDLE_ON)
    names = list(src)
    assert set(par) == set(names), set(par) ^ set(names)
    order, seen = [], set()

    def visit(n, trail=()):
        assert n not in trail, ("cycle", trail)
        if n in seen:
            return
        if par[n]:
            visit(par[n], trail + (n,))
        seen.add(n)
        order.append(n)
    for n in names:
        visit(n)
    roots = [n for n in order if par[n] is None]
    assert roots == ["h_root.x"], roots
    return order, par, src


def _pose(order, src):
    """Every game bone's armature-space matrix at the current frame (both rigs sit at identity)."""
    out = {}
    for n in order:
        rig, b = src[n]
        out[n] = rig.matrix_world @ rig.pose.bones[b].matrix
    return out


def _frame(f):
    scn = bpy.context.scene
    scn.frame_set(f)
    scn.frame_set(f)                 # ARP drivers lag one update (source README)


def _skeleton(order, par, rest, src):
    data = bpy.data.armatures.new("cavalry_rig")
    rig = bpy.data.objects.new("cavalry_rig", data)
    bpy.context.scene.collection.objects.link(rig)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for n in order:
        b = data.edit_bones.new(n)
        r, s = src[n]
        b.length = max(r.data.bones[s].length, 0.02) if n != "Saddle" else 0.2
        b.matrix = rest[n]
        b.use_deform = n != "Saddle"
    for n in order:
        if par[n]:
            data.edit_bones[n].parent = data.edit_bones[par[n]]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return rig


# --------------------------------------------------------------- decimation --

def _clean(ob):
    """decikit.preflight without its weld and normal recalc: the knight's parts are cut apart on
    purpose (k2 split: each part has its own border vertices, its own weights) and its custom normals
    keep the winding they show (k6), so a weld or a recalc would undo the authored mesh. Only
    degenerate faces and loose bits go."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    rep = {"verts_before": len(bm.verts), "nonmanifold": sum(1 for e in bm.edges if len(e.link_faces) > 2)}
    bmesh.ops.dissolve_degenerate(bm, dist=1e-7, edges=bm.edges)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    rep["verts_after"] = len(bm.verts)
    rep["boundary_edges"] = sum(1 for e in bm.edges if e.is_boundary)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return rep


def _copy(name, new):
    o0 = bpy.data.objects[name]
    o = o0.copy()
    o.data = o0.data.copy()
    o.name = new
    bpy.context.scene.collection.objects.link(o)
    return o


def _components(ob):
    """Vertex sets of ob's face-connected parts."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    seen, out = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, vs = [f], {v.index for v in f.verts}
        seen.add(f.index)
        while stack:
            g = stack.pop()
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
                        vs.update(v.index for v in h.verts)
        out.append(vs)
    bm.free()
    return out


def _drop_loose(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    return len(loose)


def _flips(low, high, shell_m=0.006):
    """The audit's flipped area split: a low face facing against its nearest high face is a THIN-SHELL
    match when a high face facing its way lies within `shell_m` (the plates are single sheets a few mm
    apart: the nearest point is the other sheet), else a genuine flip."""
    hb = bmesh.new()
    hb.from_mesh(high.data)
    hb.normal_update()
    hb.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(hb)
    lb = bmesh.new()
    lb.from_mesh(low.data)
    lb.normal_update()
    tot = genuine = shell = 0.0
    for f in lb.faces:
        a = f.calc_area()
        c = f.calc_center_median()
        tot += a
        co, _, i, _ = tree.find_nearest(c)
        if co is None or hb.faces[i].normal.dot(f.normal) >= 0:
            continue
        if any(hb.faces[j].normal.dot(f.normal) > 0.3 for _, _, j, _ in tree.find_nearest_range(c, shell_m)):
            shell += a
        else:
            genuine += a
    hb.free()
    lb.free()
    return {"genuine_share": round(genuine / tot, 5), "thin_shell_share": round(shell / tot, 5)}


BAKED = {}   # part -> {albedo, mr, n}: (h, w, 4) float arrays baked onto the low mesh's own UVs
BAKE = {"samples": 4, "extrusion_m": 0.006, "ray_m": 0.02, "margin_px": 4, "island_margin": 0.002}


def _bake(low, high, size, report, tag):
    """The skill's section 4: a COLLAPSE merges the Tripo atlas's thousands of small UV islands, so the
    low mesh is unwrapped anew (Smart UV Project) and its colour, metal-rough and tangent normals are
    baked from the high mesh (Cycles, selected to active, rays from just outside the low surface).
    Leaves the low mesh with that one UV map; returns the three maps as arrays."""
    scn = bpy.context.scene
    vl = bpy.context.view_layer
    low.data.uv_layers.new(name="bake")
    for o in bpy.context.selected_objects:
        o.select_set(False)
    low.select_set(True)
    vl.objects.active = low
    low.data.uv_layers.active = low.data.uv_layers["bake"]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=BAKE["island_margin"])
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, rotate_method="ANY", margin=BAKE["island_margin"], shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")
    for uv in [u for u in low.data.uv_layers if u.name != "bake"]:
        low.data.uv_layers.remove(uv)
    low.data.uv_layers["bake"].name = "UVMap"
    # the high mesh's maps
    src = high.data.materials[0].node_tree
    bsdf = next(n for n in src.nodes if n.type == "BSDF_PRINCIPLED")
    mr_node = next((n for n in src.nodes if n.type == "TEX_IMAGE" and any(
        l.to_node.type == "SEPARATE_COLOR" for l in n.outputs["Color"].links)), None)
    # the low mesh bakes into its own material with an active image node
    mat = bpy.data.materials.new("bake_" + tag)
    low.data.materials.clear()
    low.data.materials.append(mat)
    img_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    mat.node_tree.nodes.active = img_node
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = BAKE["samples"]
    bk = scn.render.bake
    bk.use_selected_to_active = True
    bk.use_cage = False
    bk.cage_extrusion = BAKE["extrusion_m"]
    bk.max_ray_distance = BAKE["ray_m"]
    bk.margin = BAKE["margin_px"]
    out = {}
    hidden = high.hide_get(), high.hide_render
    high.hide_set(False)
    high.hide_render = False
    for o in bpy.context.selected_objects:
        o.select_set(False)
    high.select_set(True)
    low.select_set(True)
    vl.objects.active = low
    try:
        # colour and metal-rough are EMIT bakes of the high mesh's own maps (a DIFFUSE colour pass is
        # black on metal); normals a TANGENT bake
        base_node = next((l.from_node for l in src.links if l.to_node == bsdf
                          and l.to_socket.name == "Base Color"), None)
        emit0 = tuple(bsdf.inputs["Emission Color"].default_value)
        for kind, btype in (("albedo", "EMIT"), ("mr", "EMIT"), ("n", "NORMAL")):
            img = bpy.data.images.new("bake_%s_%s" % (tag, kind), size, size, alpha=False, float_buffer=False)
            if kind != "albedo":
                img.colorspace_settings.name = "Non-Color"
            img_node.image = img
            kw = {"type": btype, "margin": BAKE["margin_px"], "use_selected_to_active": True,
                  "cage_extrusion": BAKE["extrusion_m"], "max_ray_distance": BAKE["ray_m"]}
            emit_link = None
            if btype == "EMIT":
                node = base_node if kind == "albedo" else mr_node
                if node is not None:
                    emit_link = src.links.new(node.outputs["Color"], bsdf.inputs["Emission Color"])
                elif kind == "albedo":
                    bsdf.inputs["Emission Color"].default_value = tuple(bsdf.inputs["Base Color"].default_value)
                else:                                      # a constant BSDF: G roughness, B metallic
                    bsdf.inputs["Emission Color"].default_value = (0.0, bsdf.inputs["Roughness"].default_value,
                                                                   bsdf.inputs["Metallic"].default_value, 1.0)
                bsdf.inputs["Emission Strength"].default_value = 1.0
            if btype == "NORMAL":
                kw["normal_space"] = "TANGENT"
            bpy.ops.object.bake(**kw)
            if btype == "EMIT":
                bsdf.inputs["Emission Strength"].default_value = 0.0
                bsdf.inputs["Emission Color"].default_value = emit0
                if emit_link is not None:
                    src.links.remove(emit_link)
            out[kind] = np.array(img.pixels[:], dtype=np.float32).reshape(size, size, 4)
            bpy.data.images.remove(img)
    finally:
        high.hide_set(hidden[0])
        high.hide_render = hidden[1]
        scn.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in [e.identifier for e in
                            bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else scn.render.engine
    report[tag] = {"size_px": size, **BAKE}
    return out


def _decimate_knight(dk, report):
    """The knight in its bind pose: COLLAPSE with the face, hands, couter wings and every small part
    (rivets, buckles: under 120 vertices) protected at the skill's low weight."""
    ob = _copy(KNIGHT, "knight_low")
    arm = [m for m in ob.modifiers if m.type == "ARMATURE"]
    for m in arm:
        m.show_viewport = m.show_render = False     # the bind pose, for the bake too
    hi = dk.snapshot(ob)
    base = dk.audit_decimate(hi, high=hi)["metrics"]
    pre = _clean(ob)
    hands = [g.name for g in ob.vertex_groups if g.name.startswith(("hand.", "c_index", "index", "c_middle",
             "middle", "c_ring", "ring", "c_pinky", "pinky", "thumb", "c_thumb", "cc_couter", "head.x"))]
    small = [i for vs in _components(ob) if len(vs) < 120 for i in vs]
    prot = dk.protect(ob, "decimate_keep", from_groups=hands, vertex_indices=small)
    dec = dk.decimate(ob, BUDGET["knight"], protect_group="decimate_keep", symmetry_axis="X", max_step=0.5)
    dec["loose_dropped"] = _drop_loose(ob)
    shading = dk.fix_shading(ob, angle_deg=45, weighted=True)
    audit = dk.audit_decimate(ob, high=hi, budget=BUDGET["knight"])
    BAKED["knight"] = _bake(ob, hi, int(REGION["knight"][2] * ATLAS[0]), report.setdefault("bake", {}), "knight")
    report["knight"] = {"preflight": pre, "protect": prot, "decimate": dec, "shading": shading, "audit": audit,
                        "source_baseline": base, "flips": _flips(ob, hi)}
    ob.vertex_groups.remove(ob.vertex_groups["decimate_keep"])
    for m in arm:
        m.show_viewport = m.show_render = True
    bpy.data.objects.remove(hi)
    return ob


def _decimate_spear(dk, report):
    """The spear in its own frame (grip at the origin, tip +Y): head and butt cap COLLAPSE, the shaft
    between them rebuilt as a tube (the skill: never COLLAPSE a slender part) with the high mesh's UVs
    sampled per corner."""
    y0, y1, sides, rings = SHAFT
    full = _copy(SPEAR, "spear_full")
    full.parent = None
    full.matrix_world = Matrix.Identity(4)
    me = full.data
    ys = np.array([v.co.y for v in me.vertices])
    rad = np.hypot([v.co.x for v in me.vertices], [v.co.z for v in me.vertices])
    # ends = every face with a vertex outside [y0, y1]
    ends = _copy(SPEAR, "spear_ends")
    ends.parent = None
    ends.matrix_world = Matrix.Identity(4)
    bm = bmesh.new()
    bm.from_mesh(ends.data)
    drop = [f for f in bm.faces if all(y0 <= v.co.y <= y1 for v in f.verts)]
    bmesh.ops.delete(bm, geom=drop, context="FACES_ONLY")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(ends.data)
    bm.free()
    hi = dk.snapshot(ends)
    pre = dk.preflight(ends)
    dec = dk.decimate(ends, BUDGET["spear_ends"], max_step=0.5)
    shading = dk.fix_shading(ends, angle_deg=35, weighted=True)
    audit = dk.audit_decimate(ends, high=hi, budget=BUDGET["spear_ends"])
    bpy.data.objects.remove(hi)
    # the tube: the high shaft's median radius in each ring's slab (the slabs kept off the cap and the socket)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    ring_y = np.linspace(y0, y1, rings)
    slab = (y1 - y0) / (rings - 1)
    shaft = (ys > y0 + 0.02) & (ys < y1 - 0.02)
    verts = []
    for y in ring_y:
        m = shaft & (np.abs(ys - y) <= slab)
        r = float(np.median(rad[m]))
        verts.append([bm.verts.new((r * math.cos(2 * math.pi * k / sides), y, r * math.sin(2 * math.pi * k / sides)))
                      for k in range(sides)])
    faces = []
    for i in range(rings - 1):
        for k in range(sides):
            a_, b_ = verts[i][k], verts[i][(k + 1) % sides]
            c_, d_ = verts[i + 1][(k + 1) % sides], verts[i + 1][k]
            faces.append(bm.faces.new((a_, b_, c_, d_)))
    bm.normal_update()
    # UVs: one texel line of the high shaft's own wood, read at each ring's front (+X) point; the whole
    # ring takes it (the grain runs along the shaft; a 2 cm shaft shows no grain round it at play zoom),
    # and a ring whose sample jumps to another UV chart keeps the ring before's
    hb = bmesh.new()
    hb.from_mesh(me)
    hb.faces.ensure_lookup_table()
    huv = hb.loops.layers.uv.active
    tree = BVHTree.FromBMesh(hb)
    from mathutils.geometry import barycentric_transform
    ring_uv, prev = [], None
    for y in ring_y:
        y_s = min(max(y, y0 + 0.03), y1 - 0.03)
        p = Vector((0.02, y_s, 0.0))
        _, _, fi, _ = tree.find_nearest(p)
        tri = list(hb.faces[fi].loops)[:3]
        uv = barycentric_transform(p, *(l.vert.co for l in tri), *(Vector((*l[huv].uv, 0)) for l in tri))
        uv = (uv.x, uv.y)
        if prev is not None and math.dist(uv, prev) > 0.03:
            uv = prev
        ring_uv.append(uv)
        prev = uv
    hb.free()
    for i, f in enumerate(faces):
        ring = i // sides
        for loop in f.loops:
            j = ring + (1 if any(loop.vert is v for v in verts[ring + 1]) else 0)
            loop[uvl].uv = ring_uv[j]
    for f in bm.faces:
        f.smooth = True
    tube = bpy.data.objects.new("spear_tube", bpy.data.meshes.new("spear_tube"))
    bpy.context.scene.collection.objects.link(tube)
    bm.to_mesh(tube.data)
    bm.free()
    report["spear"] = {"preflight_ends": pre, "decimate_ends": dec, "shading_ends": shading, "audit_ends": audit,
                       "tube": {"y": [y0, y1], "sides": sides, "rings": rings,
                                "tris": 2 * sides * (rings - 1)}}
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ends.select_set(True)
    tube.select_set(True)
    bpy.context.view_layer.objects.active = ends
    bpy.ops.object.join()
    ends.data.materials.clear()
    ends.data.materials.append(bpy.data.objects[SPEAR].data.materials[0])
    BAKED["spear"] = _bake(ends, full, int(REGION["spear"][2] * ATLAS[0]), report.setdefault("bake", {}), "spear")
    bpy.data.objects.remove(full)
    return ends


# --------------------------------------------------------------------- mesh --

def _region_uv(obj, part):
    u0, v0, du, dv = REGION[part]
    uv = obj.data.uv_layers.active.data
    co = np.zeros(len(uv) * 2)
    uv.foreach_get("uv", co)
    co = co.reshape(-1, 2)
    assert co.min() > -1e-3 and co.max() < 1 + 1e-3, (part, co.min(), co.max())
    co = np.c_[u0 + np.clip(co[:, 0], 0, 1) * du, v0 + np.clip(co[:, 1], 0, 1) * dv]
    uv.foreach_set("uv", co.ravel())
    obj.data.uv_layers.active.name = "UVMap"


def _posed(ob, rename, prefix):
    """ob's armature applied at the current frame (rest = this pose), its groups renamed to game bones."""
    vl = bpy.context.view_layer
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    vl.objects.active = ob
    mods = [m for m in ob.modifiers if m.type == "ARMATURE"]
    assert len(mods) == 1, [m.name for m in ob.modifiers]
    bpy.ops.object.modifier_apply(modifier=mods[0].name)
    mw = ob.matrix_world.copy()
    ob.parent = None
    ob.data.transform(mw)
    ob.matrix_world = Matrix.Identity(4)
    for g in ob.vertex_groups:
        g.name = rename.get(g.name, prefix + g.name)
    return ob


def _mesh(rig, knight, spear):
    """Knight, horse and spear posed at REST, merged into ONE mesh `cavalry` with one material."""
    horse = _copy(HORSE, "horse_low")
    _posed(knight, KNIGHT_RENAME, "")
    _posed(horse, HORSE_RENAME, "h_")
    # the spear hangs where the source's bone-parented spear hangs at REST (its mesh is in its own frame)
    spear.data.transform(bpy.data.objects[SPEAR].matrix_world)
    spear.matrix_world = Matrix.Identity(4)
    spear.vertex_groups.clear()
    spear.vertex_groups.new(name="cc_weapon.r").add(range(len(spear.data.vertices)), 1.0, "REPLACE")
    for ob, part in ((knight, "knight"), (horse, "horse"), (spear, "spear")):
        _region_uv(ob, part)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in (knight, horse, spear):
        o.select_set(True)
    bpy.context.view_layer.objects.active = knight
    bpy.ops.object.join()
    body = knight
    body.name = "cavalry"
    body.data.name = "cavalry"
    unknown = [g.name for g in body.vertex_groups if g.name not in rig.data.bones]
    assert not unknown, unknown
    mat = bpy.data.materials.new("cavalry_atlas")
    body.data.materials.clear()
    body.data.materials.append(mat)
    for p in body.data.polygons:
        p.material_index = 0
    body.modifiers.clear()
    m = body.modifiers.new("Skin", "ARMATURE")
    m.object = rig
    body.parent = rig
    body.matrix_parent_inverse.identity()
    return body, mat


def _pixels(img, w, h):
    c = img.copy()
    c.scale(w, h)
    a = np.array(c.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(c)
    return a


def _maps(name):
    """{albedo, mr, n: image or None} of a source object's material (by the socket each feeds)."""
    nt = bpy.data.objects[name].data.materials[0].node_tree
    out = {"albedo": None, "mr": None, "n": None}
    for n in nt.nodes:
        if n.type != "TEX_IMAGE" or not n.image:
            continue
        for l in n.outputs["Color"].links:
            if l.to_node.type == "BSDF_PRINCIPLED" and l.to_socket.name == "Base Color":
                out["albedo"] = n.image
            elif l.to_node.type == "SEPARATE_COLOR":
                assert {lk.to_socket.name for lk in l.to_node.outputs["Green"].links} == {"Roughness"}, name
                assert {lk.to_socket.name for lk in l.to_node.outputs["Blue"].links} == {"Metallic"}, name
                out["mr"] = n.image
            elif l.to_node.type == "NORMAL_MAP":
                out["n"] = n.image
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    out["const_rough"] = float(bsdf.inputs["Roughness"].default_value)
    out["const_metal"] = float(bsdf.inputs["Metallic"].default_value)
    assert out["albedo"] is not None, name
    return out


def _atlases(mat, out_dir):
    W, H = ATLAS
    parts = {"knight": _maps(KNIGHT), "horse": _maps(HORSE), "spear": _maps(SPEAR)}
    files = {}
    for kind in ("albedo", "mr", "n"):
        atlas = np.zeros((H, W, 4), np.float32)
        atlas[..., 3] = 1
        if kind == "n":
            atlas[..., :3] = (0.5, 0.5, 1.0)
        for part, maps in parts.items():
            u0, v0, du, dv = REGION[part]
            w, h = int(round(du * W)), int(round(dv * H))
            x, y = int(round(u0 * W)), int(round(v0 * H))
            img = maps[kind]
            if part in BAKED:
                atlas[y:y + h, x:x + w] = BAKED[part][kind]
            elif img is not None:
                atlas[y:y + h, x:x + w] = _pixels(img, w, h)
            elif kind == "mr":           # a constant BSDF: G roughness, B metallic
                atlas[y:y + h, x:x + w, :3] = (0.0, maps["const_rough"], maps["const_metal"])
        if kind == "mr":
            atlas[..., 2] *= GAME_METAL
        name = "cavalry_atlas" + ("" if kind == "albedo" else "_" + kind)
        im = bpy.data.images.new(name, W, H, alpha=False)
        if kind != "albedo":
            im.colorspace_settings.name = "Non-Color"
        im.pixels.foreach_set(atlas.ravel())
        path = str(Path(out_dir) / ("cavalry_" + name + ".jpg"))
        im.filepath_raw = path
        im.file_format = "JPEG"
        bpy.context.scene.render.image_settings.quality = 92
        im.save(filepath=path, quality=92)
        im.pack()
        im.filepath_raw = name + ".jpg"
        files[kind] = im
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = files["albedo"]
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = files["mr"]
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(t.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = files["n"]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(t.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return {k: str(Path(out_dir) / ("cavalry_" + v.name + ".jpg")) for k, v in files.items()}


# -------------------------------------------------------------------- clips --

def _poses(order, src, clip):
    """The clip's poses, one per frame from its first; a loop gets its own period: when its last frame
    is not its first pose again, the first is appended (the source loops are cyclic: MARCH's 13 frames
    are a 13-frame period, frame 14 = 1), then any residual is spread over the last SEAM_FRAMES."""
    f0, f1 = use(GAME[clip])
    poses = []
    for f in range(f0, f1 + 1):
        _frame(f)
        poses.append(_pose(order, src))
    info = {"source": GAME[clip], "source_frames": [f0, f1], "loop": clip in LOOPS}
    if clip in LOOPS:
        def gap(a, b):
            return max((a[n].translation - b[n].translation).length for n in a)
        last_first = gap(poses[-1], poses[0])
        step = float(np.median([gap(poses[i], poses[i + 1]) for i in range(len(poses) - 1)]))
        info["seam_last_to_first_m"] = round(last_first, 5)
        info["median_step_m"] = round(step, 5)
        if last_first > 0.25 * step:            # last != first: the period ends one frame on
            poses.append({n: m.copy() for n, m in poses[0].items()})
            info["closed"] = "appended first pose"
        else:
            n = len(poses)
            fix = {b: poses[0][b] @ poses[-1][b].inverted() for b in poses[0]}
            for k in range(SEAM_FRAMES):
                i = n - SEAM_FRAMES + k
                w = (k + 1) / SEAM_FRAMES
                poses[i] = {b: Matrix.Identity(4).lerp(fix[b], w) @ m for b, m in poses[i].items()}
            info["closed"] = "residual spread over %d frames" % SEAM_FRAMES
    info["frames"] = len(poses)
    return poses, info


def _rot_about(p, q):
    return Matrix.Translation(p) @ q.to_matrix().to_4x4() @ Matrix.Translation(-p)


def _locals(order, par, pose):
    return {n: (pose[par[n]].inverted() @ pose[n]) if par[n] else pose[n].copy() for n in order}


def _fk(order, par, loc, override=None):
    out = {}
    for n in order:
        if override and n in override:
            out[n] = override[n]
        else:
            out[n] = (out[par[n]] @ loc[n]) if par[n] else loc[n].copy()
    return out


def _dense(order, par, poses):
    """poses (a closed loop, last = first) resampled DENSE keys a frame by interpolating each bone's local."""
    locs = [_locals(order, par, p) for p in poses]
    out = []
    for j in range((len(poses) - 1) * DENSE + 1):
        k, a = divmod(j, DENSE)
        a /= DENSE
        if a == 0:
            out.append(_fk(order, par, locs[k]))
            continue
        loc = {}
        for n in order:
            l0, q0, s0 = locs[k][n].decompose()
            l1, q1, s1 = locs[k + 1][n].decompose()
            loc[n] = Matrix.LocRotScale(l0.lerp(l1, a), q0.slerp(q1, a), s0.lerp(s1, a))
        out.append(_fk(order, par, loc))
    return out


def _low(m, pts):
    return min((m @ p).z for p in pts)


def _two_bone(S, E0, K0, K):
    a, b = (E0 - S).length, (K0 - E0).length
    d0 = (K - S).length
    d = min(max(d0, abs(a - b) + 1e-4), a + b - 1e-4)
    t = (K - S).normalized()
    n = (E0 - S).cross(K0 - S)
    w = n.normalized().cross(t).normalized()
    if w.dot(E0 - S) < 0:
        w = -w
    c = (a * a + d * d - b * b) / (2 * a * d)
    E = S + a * (c * t + math.sqrt(max(0.0, 1 - c * c)) * w)
    return E, S + d * t, d != d0


def _lock(order, par, poses, patch):
    """LOCK on a dense closed loop; returns (poses, report). Bone names are the game's."""
    n = len(poses) - 1                      # keys in the period (last = first)
    chains = {}
    for hoof in patch:
        S = hoof[-2:]
        if hoof.startswith("Front"):
            chains[hoof] = ("FrontUpperArm" + S, "FrontForearm" + S, "FrontCannon" + S)
        else:
            chains[hoof] = ("HindThigh" + S, "HindShin" + S, "HindCannon" + S)
    h = {f: np.array([_low(poses[j][f], patch[f]) for j in range(n)]) for f in patch}
    ymid = {f: np.array([float(np.mean([(poses[j][f] @ p).y for p in patch[f]])) for j in range(n)]) for f in patch}
    down_run = {}
    for f in patch:
        # within stance_m of its lowest, or of the ground where the interpolation dips the hoof under it
        down = h[f] <= max(float(h[f].min()), 0.0) + LOCK["stance_m"]
        j0 = int(np.argmin(h[f]))
        a = j0
        while down[(a - 1) % n] and (j0 - a) < n - 1:
            a -= 1
        b = j0
        while down[(b + 1) % n] and (b - a) < n - 1:
            b += 1
        down_run[f] = (a, b)                 # inclusive, may run below 0 (cyclic)
    speeds = []
    for f, (a, b) in down_run.items():
        if f.startswith("Hind"):
            speeds += [ymid[f][(j + 1) % n] - ymid[f][j % n] for j in range(a, b)]
    v = float(np.median(speeds))             # model m per key, +Y = backward (the horse faces -Y)

    # off[f][m, j]: how far (largest sole point) the hoof held at key m's pose, set on the ground and
    # carried back at v, lies from its own pose at key j
    off = {}
    for f in patch:
        pts = np.array([[(poses[j][f] @ p)[:] for p in patch[f]] for j in range(n)])      # n, k, 3
        ref = pts.copy()
        ref[:, :, 2] -= pts[:, :, 2].min(axis=1, keepdims=True)
        dj = np.arange(n)[None, :] - np.arange(n)[:, None]                                  # j - m
        dj = (dj + n // 2) % n - n // 2
        moved = ref[:, None, :, :] + np.stack([np.zeros_like(dj), v * dj, np.zeros_like(dj)], -1)[:, :, None, :]
        off[f] = np.linalg.norm(moved - pts[None, :, :, :], axis=-1).max(-1)                # n, n

    def cost(f, s0, e0):
        jm = (s0 + e0) // 2
        return float(max(off[f][jm % n, j % n] for j in range(s0, e0 + 1)))
    stance = {}
    for f, (a, b) in down_run.items():
        best = None
        for length in range(b - a + 1, LOCK["min_keys"] - 1, -1):
            c, s0 = min((cost(f, s0, s0 + length - 1), s0) for s0 in range(a, b - length + 2))
            if c <= LOCK["max_offset_m"] or length == LOCK["min_keys"]:
                best = (s0, s0 + length - 1)
                break
        stance[f] = best
    rep = {"speed_m_per_key": round(v, 6), "stride_m": round(v * n, 4), "hooves": {}}
    target = {f: {} for f in patch}
    for f, (a, b) in stance.items():
        jm = (a + b) // 2
        ref = poses[jm % n][f].copy()
        ref = Matrix.Translation((0, 0, -_low(ref, patch[f]))) @ ref
        for j in range(a, b + 1):
            target[f][j % n] = Matrix.Translation((0, v * (j - jm), 0)) @ ref
        E = LOCK["ease"]
        for side, edge, step in (("out", b, 1), ("in", a, -1)):
            D = target[f][edge % n] @ poses[edge % n][f].inverted()
            dl, dq, _ = D.decompose()
            for k in range(1, E + 1):
                j = (edge + step * k) % n
                if any(j == (x % n) for x in range(a, b + 1)):
                    break
                w = 1 - k / (E + 1)
                w = w * w * (3 - 2 * w)
                blend = Matrix.LocRotScale(Vector((0, 0, 0)).lerp(dl, w),
                                           Matrix.Identity(3).to_quaternion().slerp(dq, w), Vector((1, 1, 1)))
                t = blend @ poses[j][f]
                if j in target[f]:          # both eases reach this key: average them
                    t0 = target[f][j]
                    t = Matrix.LocRotScale(t0.translation.lerp(t.translation, 0.5),
                                           t0.to_quaternion().slerp(t.to_quaternion(), 0.5), Vector((1, 1, 1)))
                lift = _low(t, patch[f])
                if lift < 0:                # an eased hoof never dips under the ground
                    t = Matrix.Translation((0, 0, -lift)) @ t
                target[f][j] = t
        locked = {x % n for x in range(a, b + 1)}
        for j in range(n):                  # off the stance: clear of the ground, ramping up from its edges
            if j in locked:
                continue
            d = min(min((j - x) % n, (x - j) % n) for x in (a % n, b % n))
            need = min(LOCK["clear_m"], LOCK["ramp_m"] * d)
            t = target[f].get(j, poses[j][f])
            low = _low(t, patch[f])
            if low < need:
                target[f][j] = Matrix.Translation((0, 0, need - low)) @ t
        rep["hooves"][f] = {"stance_keys": [a % n, b % n], "low_keys": [down_run[f][0] % n, down_run[f][1] % n], "duty": round((b - a + 1) / n, 3),
                            "source_lowest_m": round(float(h[f].min()), 4),
                            "max_offset_m": round(max((target[f][j].translation - poses[j][f].translation).length
                                                      for j in target[f]), 4), "clamped": 0}
    out = []
    for j in range(n):
        P = poses[j]
        loc = _locals(order, par, P)
        over = {}
        for f, (U, F, C) in chains.items():
            if j not in target[f]:
                continue
            Ht = target[f][j]
            Ct = Ht @ P[f].inverted() @ P[C]
            E, K, clamped = _two_bone(P[U].translation, P[F].translation, P[C].translation, Ct.translation)
            rep["hooves"][f]["clamped"] += int(clamped)
            S0 = P[U].translation
            R1 = (P[F].translation - S0).rotation_difference(E - S0)
            U1 = _rot_about(S0, R1) @ P[U]
            F1 = _rot_about(S0, R1) @ P[F]
            K1 = _rot_about(S0, R1) @ P[C].translation
            R2 = (K1 - E).rotation_difference(K - E)
            F2 = _rot_about(E, R2) @ F1
            Ct.translation = K
            # the hoof keeps its native pastern on the cannon (= the target unless the reach was clamped)
            over.update({U: U1, F: F2, C: Ct, f: Ct @ (P[C].inverted() @ P[f])})
        out.append(_fk(order, par, loc, over))
    out.append({k: m.copy() for k, m in out[0].items()})
    # after: planted slide (key to key, the lowest sole points' travel against the run) and lowest points
    for f, (a, b) in stance.items():
        slide = 0.0
        for j in range(a, b):
            p0 = [out[j % n][f] @ p for p in patch[f]]
            p1 = [out[(j + 1) % n][f] @ p for p in patch[f]]
            slide = max(slide, max(((q - p) - Vector((0, v, 0))).length for p, q in zip(p0, p1)))
        r = rep["hooves"][f]
        r["planted_slide_mm_per_key"] = round(slide * 1000, 3)
        r["lowest_m"] = round(min(_low(out[j][f], patch[f]) for j in range(n)), 4)
    return out, rep


def _key(rig, par, poses, game, step=1.0):
    """One action `game` keyed from frame 0, every bone, every `step` frames (fcurves written whole, LINEAR:
    the exporter writes these keys as they are, so MARCH keeps its DENSE keys)."""
    rig.animation_data_create()
    act = bpy.data.actions.new(game)
    rig.animation_data.action = act
    n = len(poses)
    for pb in rig.pose.bones:
        name = pb.name
        rest = pb.bone.matrix_local
        p = par[name]
        rel = (pb.parent.bone.matrix_local.inverted() @ rest) if p else rest
        loc, rot, scl = [], [], []
        prev = None
        for pose in poses:
            local = pose[p].inverted() @ pose[name] if p else pose[name]
            basis = rel.inverted() @ local
            l, q, s = basis.decompose()
            if prev is not None and prev.dot(q) < 0:
                q.negate()
            prev = q
            loc.append(l); rot.append(q); scl.append(s)
        for path, vals, width in (("location", loc, 3), ("rotation_quaternion", rot, 4), ("scale", scl, 3)):
            for i in range(width):
                fc = act.fcurve_ensure_for_datablock(rig, 'pose.bones["%s"].%s' % (name, path), index=i,
                                                     group_name=name)
                fc.keyframe_points.add(n)
                co = np.empty(2 * n)
                co[0::2] = np.arange(n) * step
                co[1::2] = [v[i] for v in vals]
                fc.keyframe_points.foreach_set("co", co)
                fc.keyframe_points[0].interpolation = "LINEAR"
                lin = np.zeros(n, dtype=np.int32)
                fc.keyframe_points.foreach_get("interpolation", lin)
                fc.keyframe_points.foreach_set("interpolation", np.full(n, lin[0], dtype=np.int32))
                fc.update()
    track = rig.animation_data.nla_tracks.new()
    track.name = game
    strip = track.strips.new(game, 0, act)
    strip.action_slot = act.slots[0]
    rig.animation_data.action = None


def _transplant(shipped, dense):
    """Every MARCH channel of `shipped` takes `dense`'s keys (same rig, same channel set, same length)."""
    spec = importlib.util.spec_from_file_location("archer_march_transplant",
                                                  Path(__file__).resolve().parents[1] / "archer_arp/march_transplant.py")
    gm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gm)
    gl, binary = gm.read(shipped.read_bytes())
    egl, ebin = gm.read(dense.read_bytes())
    mine, theirs = gm.channels(gl, binary), gm.channels(egl, ebin)
    assert set(mine) == set(theirs), sorted(set(mine) ^ set(theirs))
    times = {theirs[k][1].tobytes() for k in theirs}
    assert len(times) == 1, "dense MARCH channels do not share one key list"
    etimes = next(iter(theirs.values()))[1]
    end = float(next(iter(mine.values()))[1][-1, 0])
    assert abs(float(etimes[0, 0])) < 1e-6 and abs(float(etimes[-1, 0]) - end) < 1e-5, (etimes[-1, 0], end)

    def append(values, like):
        nonlocal binary
        binary += b"\0" * (-len(binary) % 4)
        data = np.ascontiguousarray(values, "<f4").tobytes()
        gl["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
        binary += data
        a = {k: v for k, v in like.items() if k not in ("bufferView", "byteOffset", "min", "max", "count")}
        a.update({"bufferView": len(gl["bufferViews"]) - 1, "count": int(values.shape[0])})
        if values.shape[1] == 1:
            a.update({"min": [float(values.min())], "max": [float(values.max())]})
        gl["accessors"].append(a)
        return len(gl["accessors"]) - 1
    shared = None
    for key in sorted(mine):
        sampler, _, _ = mine[key]
        if shared is None:
            shared = append(etimes, gl["accessors"][sampler["input"]])
        sampler["input"] = shared
        sampler["output"] = append(theirs[key][2], gl["accessors"][sampler["output"]])
        sampler["interpolation"] = "LINEAR"
    gl["buffers"][0]["byteLength"] = len(binary) + (-len(binary) % 4)
    shipped.write_bytes(gm.write(gl, binary))
    return {"channels": len(mine), "keys": int(etimes.shape[0])}


def install(root):
    root = Path(root)
    out = root / "assets/3D/units/cavalry"
    report = {}
    dk = _dk()
    order, par, src = _bones()
    K, H = bpy.data.objects["rig"], bpy.data.objects["horse_rig"]
    report["bbone_segments"] = {n: r.data.bones[b].bbone_segments for n, (r, b) in src.items()
                                if r.data.bones[b].bbone_segments > 1}
    # decimate in the bind pose (the armature off), before anything is posed
    use(REST[0]); _frame(REST[1])
    knight = _decimate_knight(dk, report)
    spear = _decimate_spear(dk, report)
    use(REST[0]); _frame(REST[1]); bpy.context.view_layer.update()
    rest = _pose(order, src)
    rig = _skeleton(order, par, rest, src)
    body, mat = _mesh(rig, knight, spear)
    report["files"] = _atlases(mat, out)
    # each hoof's patch for the stride: its vertices weighted > 0.8 on it, within 5 mm of its lowest
    me = body.data
    gi = {g.index: g.name for g in body.vertex_groups}
    patch = {}
    for hoof in [n for n in order if "Hoof" in n]:
        pts = []
        for v in me.vertices:
            if any(gi[g.group] == hoof and g.weight > 0.8 for g in v.groups):
                pts.append(v.co.copy())
        lo = min(p.z for p in pts)
        patch[hoof] = [rest[hoof].inverted() @ p for p in pts if p.z <= lo + 0.005]
    report["clips"] = {}
    for game in GAME:
        poses, info = _poses(order, src, game)
        if game == "MARCH":
            dense = _dense(order, par, poses)
            report["march_before"] = {f: round(min(_low(p[f], patch[f]) for p in dense), 4) for f in patch}
            poses, report["march"] = _lock(order, par, dense, patch)
            _key(rig, par, poses[::DENSE], game)   # the 30 fps clip; its dense keys are transplanted
            dense_march = poses
            info["keys"] = len(poses)
        else:
            _key(rig, par, poses, game)
        report["clips"][game] = info
    rig.rotation_euler.z = math.pi           # Blender -Y -> glTF +Z; the game's figures face -Z
    bpy.context.view_layer.update()
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True); body.select_set(True)
    bpy.context.view_layer.objects.active = rig
    kw = dict(export_format="GLB", use_selection=True, export_yup=True, export_skins=True,
              export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
              export_def_bones=False, export_optimize_animation_size=False, export_image_format="JPEG",
              export_jpeg_quality=92)
    bpy.ops.export_scene.gltf(filepath=str(out / "cavalry.glb"), **kw)
    # MARCH's DENSE keys: the same rig with MARCH alone, keyed a frame a key at DENSE x the fps, its
    # channels moved into the shipped GLB (the exporter samples at the scene's fps)
    for t in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(t)
    _key(rig, par, dense_march, "MARCH")
    scn = bpy.context.scene
    fps = scn.render.fps
    scn.render.fps = fps * DENSE
    tmp = root / "assets/3D/model_wip/blender_output/heavy_cavalry/export/cavalry_march_dense.glb"  # the work folder
    tmp.parent.mkdir(parents=True, exist_ok=True)
    try:
        bpy.ops.export_scene.gltf(filepath=str(tmp), **{**kw, "export_image_format": "NONE"})
    finally:
        scn.render.fps = fps
    report["march"]["transplant"] = _transplant(out / "cavalry.glb", tmp)
    tmp.unlink()
    me.calc_loop_triangles()
    lo = min(v.co.z for v in me.vertices); hi = max(v.co.z for v in me.vertices)
    report.update(tris=len(me.loop_triangles), verts=len(me.vertices), bones=len(rig.data.bones),
                  height_m=round(hi - lo, 3), bone_parents={n: par[n] for n in order})
    return report


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    result = install(argv[0])
    text = json.dumps(result, indent=1, default=str)
    if len(argv) > 1:
        Path(argv[1]).write_text(text)
    print("CAVALRY_EXPORT", text[:2000])
