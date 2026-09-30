"""The infantry piece from a Tripo 3D generation (owner 2026-09-29: 用 tripo 3d 辅助生产
3d 模型). Run step by step IN THE OWNER'S OPEN BLENDER (owner 2026-09-29: 你接下来的操作都要
在我打开的blender instance上进行), through the Blender MCP:

    T = {}; exec(open(".../infantry_tripo/tripo.py").read(), T)
    T["load"]()          # both Tripo files into the scene Tripo_Infantry, aligned, in metres
    T["reduce"]()        # the parts collapsed to the budget
    T["rig"]()           # inf_rig: the blueprint man-at-arms' skeleton, fitted to this man
    T["skin"]()          # every part weighted to its own bone(s), joined into `infantry`
    T["texture"]()       # one 2048 atlas baked from the textured generation
    T["animate"]()       # MARCH and STANDBY (the blueprint's), GARRISON (guard.py)
    T["export"](out_dir) # infantry.glb (+Y forward), GARRISON / STANDBY / MARCH

Two Tripo exports of the SAME generation, in assets/3D/units/infantry/model_wip/tripo/ (git-ignored):
  * "medieval knight 3d model.glb" — one 94k-tri mesh with 4K PBR maps (base colour,
    roughness-metallic, normal): the TEXTURE source, baked onto the game mesh;
  * knight_parts.glb — Tripo's part segmentation, 51 untextured parts, 46k tris: the
    GAME MESH's shape, one part per plate, so each plate rides its own bone like the
    blueprint's (a single fused mesh can only be weighted by heat or distance, and its
    plates stretch at every joint).
The parts file is in its own units and frame; ALIGN (an affine fit, iterated closest
points onto the textured mesh: mean 0.21, p95 0.59 of its 97-unit height, ~4 mm / 12 mm
in metres) maps it onto the textured one. Both face -Y with the right hand at -X, the
blueprint's own frame, so the blueprint's MARCH and GARRISON (infantry_blueprint/) drive
this rig unchanged, given this man's joints (R, SH_GRIP, SH_REST, GRIP, A_REST).
"""
import bpy, bmesh, json, math, os, sys
import numpy as np
from mathutils import Vector, Matrix

ROOT = "/Users/samuelzhang/game_design/"
SRC = ROOT + "assets/3D/units/infantry/model_wip/tripo/"
TEX_FILE = SRC + "medieval knight 3d model.glb"
PARTS_FILE = SRC + "knight_parts.glb"
BLUEPRINT = ROOT + "tools/units3d/infantry_blueprint/"
HERE = ROOT + "tools/units3d/infantry_tripo/"
UNITS = ROOT + "tools/units3d/"
if UNITS not in sys.path:
    sys.path.insert(0, UNITS)

SCENE = "Tripo_Infantry"
HEIGHT = 1.85                    # the helmet's crown, metres (the blueprint man: 1.847)
TEX_CROWN = 88.12                # the helmet's crown in the textured file's units (its spear rises to 97.44)
K = HEIGHT / TEX_CROWN
ALIGN_A = [[100.32781, -0.39518, -0.03279], [0.68414, 101.94472, -0.93179], [-0.13585, -0.33022, 100.20221]]
ALIGN_T = [-0.08326, 0.56313, 0.05812]
BUDGET = 19000                   # tris, the whole piece (the blueprint's: 23,570)
MIN_PART_TRIS = 60
ATLAS = 2048
STEEL_METAL = 0.25               # the lesson of 2026-09-29: fully metallic plate reads BLACK at 30 px
AO_FLOOR = 0.62

# --------------------------------------------------------------- parts ----
# Tripo's parts by index (tripo_part_<n>), read off a labelled render. Each names the
# bones its vertices may ride; with one bone the part is rigid, with more each vertex
# takes its nearest two by distance to the bones' segments. "S" = the part's own side.
PART_BONES = {
    23: ["spear"], 45: ["spear"], 49: ["spear"],                       # head, shaft, butt
    4: ["shield"], 13: ["shield"], 26: ["shield"],                     # the shield: face, rim, boss...
    34: ["shield"], 42: ["shield"], 44: ["shield"],                    # (its own bone, under the left forearm)
    8: ["head"], 30: ["head"], 47: ["head"],                           # helmet, visor, eye slit
    2: ["neck", "chest"],                                              # the gorget
    41: ["chest"], 16: ["chest", "spine"],                             # breastplate
    3: ["spine", "hips"],                                              # the waist lames
    40: ["hips"], 39: ["hips"], 36: ["hips"],                          # the belt, its tail, a purse
    31: ["hips", "thigh.S"], 17: ["hips", "thigh.S"], 28: ["hips", "thigh.S"],   # tassets
    12: ["hips", "thigh.S"], 20: ["hips", "thigh.S"],
    1: ["hips", "thigh.L", "thigh.R"],                                 # the mail skirt
    0: ["cloak"],                                                      # the cloak (its chains)
    # pauldrons and the armpits' gussets ride the upper arm WHOLE (owner 2026-09-29: 驻防的手臂动作太扭曲了):
    # shared with the clavicle / chest by distance, they tore to shreds the moment GARRISON raised the arm
    10: ["upperarm.S"], 32: ["upperarm.S"],
    38: ["upperarm.S"], 27: ["upperarm.S"],
    11: ["upperarm.S"], 9: ["upperarm.S"],                             # rerebraces
    22: ["forearm.S"], 18: ["forearm.S"],                              # couters, whole on the forearm (shared, they tore when GARRISON bent the elbow)
    43: ["forearm.S", "hand.S"], 46: ["forearm.S", "hand.S"],          # the right vambrace and cuff
    33: ["hand.S"],                                                    # the right fist on the spear
    35: ["forearm.S"], 6: ["forearm.S", "hand.S"],                     # the left vambrace, gauntlet
    25: ["thigh.S"], 15: ["thigh.S"], 21: ["thigh.S"],                 # cuisses
    19: ["thigh.S", "shin.S"], 29: ["thigh.S", "shin.S"], 37: ["thigh.S", "shin.S"],  # poleyns
    24: ["shin.S", "foot.S"], 14: ["thigh.S", "shin.S", "foot.S"],     # greaves
    48: ["shin.S", "foot.S"], 50: ["shin.S", "foot.S"],
    5: ["foot.S", "shin.S"], 7: ["foot.S", "shin.S"],                  # sabatons
}
SPEAR_PARTS = (23, 45, 49)
CLOAK_PART = 0

# ------------------------------------------------------------- joints ----
# Measured on the aligned parts (slices of the legs, the arm plates' centres). The LEFT
# side (+X); the right is mirrored, except the arms, which are not posed alike: the
# right fist holds the spear before him, the left hand hangs inside the shield.
HIP = Vector((0.100, 0.030, 0.920))
KNEE = Vector((0.145, 0.035, 0.490))
ANKLE = Vector((0.165, 0.060, 0.120))
TOE = Vector((0.195, -0.140, 0.030))
ARM = {"L": dict(S=Vector((0.190, 0.020, 1.380)), EL=Vector((0.312, 0.030, 1.160)),
                 W=Vector((0.332, -0.030, 1.040)), T=Vector((0.320, -0.055, 0.925))),
       "R": dict(S=Vector((-0.190, 0.020, 1.380)), EL=Vector((-0.315, 0.025, 1.170)),
                 W=Vector((-0.368, -0.160, 1.120)), T=Vector((-0.388, -0.290, 1.115)))}
SPEAR_GRIP = Vector((-0.380, -0.248, 1.116))       # the shaft's axis at the fist
CLOAK_X = {"C": 0.0, "L": 0.13, "R": -0.13}
CLOAK_Z = (1.44, 1.10, 0.75, 0.40)                 # the chains' joints, collar to near the hem (0.31)


def mx(v):
    return Vector((-v.x, v.y, v.z))


def sstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# -------------------------------------------------------------- scene ----

def scene():
    sc = bpy.data.scenes.get(SCENE) or bpy.data.scenes.new(SCENE)
    # playback syncing to the audio clock crashed Blender 5.2 on macOS (CoreAudio assert in
    # BKE_sound_sync_scene, 2026-09-29): play every frame, sound muted
    sc.sync_mode = "NONE"
    sc.use_audio = True
    if bpy.context.window:
        bpy.context.window.scene = sc
    return sc


def coll(name):
    sc = scene()
    c = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if c.name not in sc.collection.children:
        sc.collection.children.link(c)
    return c


def _import(path, cname):
    c = coll(cname)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for uc in list(o.users_collection):
            uc.objects.unlink(o)
        c.objects.link(o)
    return new


def _bake_in(o, m):
    mw = o.matrix_world.copy()
    o.parent = None
    o.data.transform(mw)
    o.matrix_world = Matrix.Identity(4)
    o.data.transform(m)


def load():
    """The textured generation as `tripo_high`, the parts as tripo_part_<n>, in metres."""
    for name in ("Tripo_Textured", "Tripo_Parts"):
        c = bpy.data.collections.get(name)
        if c:
            for o in list(c.objects):
                bpy.data.objects.remove(o, do_unlink=True)
    tex = _import(TEX_FILE, "Tripo_Textured")
    for o in tex:
        if o.type == "MESH":
            _bake_in(o, Matrix.Scale(K, 4))
            o.name = "tripo_high"
        else:
            bpy.data.objects.remove(o, do_unlink=True)
    parts = _import(PARTS_FILE, "Tripo_Parts")
    m = np.eye(4)
    m[:3, :3] = np.array(ALIGN_A) * K
    m[:3, 3] = np.array(ALIGN_T) * K
    m = Matrix(m.tolist())
    for o in parts:
        if o.type == "MESH":
            _bake_in(o, m)
    for o in parts:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    return bpy.data.objects["tripo_high"]


def part(n):
    return bpy.data.objects["tripo_part_%d" % n]


def parts():
    return sorted((o for o in bpy.data.collections["Tripo_Parts"].objects if o.type == "MESH"),
                  key=lambda o: int(o.name.split("_")[-1]))


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def activate(o):
    for x in bpy.context.view_layer.objects:
        x.select_set(False)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


# ------------------------------------------------------------- reduce ----

def reduce(budget=BUDGET):
    """Each part collapsed by the same ratio (never under MIN_PART_TRIS), as `inf_p<n>`
    in Tripo_Game; the parts themselves stay as they came."""
    game = coll("Tripo_Game")
    for o in list(game.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    ps = parts()
    total = sum(tris(o) for o in ps)
    ratio = budget / total
    out = []
    for o in ps:
        n = int(o.name.split("_")[-1])
        low = o.copy()
        low.data = o.data.copy()
        low.name = low.data.name = "inf_p%d" % n
        low["part"] = n
        game.objects.link(low)
        t = tris(o)
        # the spear is left whole: collapsed, its thin shaft pinched into a spike under the fist
        r = 1.0 if n in SPEAR_PARTS else min(1.0, max(ratio, MIN_PART_TRIS / max(1, t)))
        if r < 0.999:
            d = low.modifiers.new("decimate", "DECIMATE")
            d.ratio = r
            activate(low)
            bpy.ops.object.modifier_apply(modifier=d.name)
        activate(low)
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
        out.append(low)
    coll("Tripo_Parts").hide_viewport = True
    bpy.data.objects["tripo_high"].hide_set(True)          # the bake's source, not the piece
    got = sum(tris(o) for o in out)
    print("reduce: %d parts, %d -> %d tris" % (len(out), total, got))
    return got


# ---------------------------------------------------------------- rig ----

def cloak_joints():
    ob = bpy.data.objects.get("inf_p%d" % CLOAK_PART) or part(CLOAK_PART)
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    out = {}
    for side, x in CLOAK_X.items():
        js = []
        for z in CLOAK_Z:
            near = [v for v in vs if abs(v.x - x) < 0.05 and abs(v.z - z) < 0.05] or \
                sorted(vs, key=lambda v: (v.x - x) ** 2 + (v.z - z) ** 2)[:6]
            js.append(Vector((x, max(v.y for v in near) - 0.012, z)))
        out[side] = js
    return out


SABATON = {"L": 7, "R": 5}


def foot_toe(sd):
    """The foot bone's tail along the sabaton's OWN length: Tripo's feet are splayed (19 and 26
    degrees out), and a bone that does not follow the foot leaves the foot splayed once MARCH turns
    the bone straight ahead (owner 2026-09-29: 士兵走路外八字太严重)."""
    o = bpy.data.objects.get("tripo_part_%d" % SABATON[sd])
    ank = ANKLE if sd == "L" else mx(ANKLE)
    if o is None:
        return TOE if sd == "L" else mx(TOE)
    c = np.array([o.matrix_world @ v.co for v in o.data.vertices])
    s2 = c[c[:, 2] < 0.05][:, :2]
    u = np.linalg.svd(s2 - s2.mean(0))[2][0]
    if u[1] > 0:
        u = -u                                        # toward the toe (-Y is forward)
    d = Vector((u[0], u[1], 0.0)).normalized()
    return Vector((ank.x, ank.y, TOE.z)) + d * (ank.y - TOE.y)


def shield_centre():
    co = np.concatenate([np.array([part(n).matrix_world @ v.co for v in part(n).data.vertices]) for n in SHIELD_PARTS])
    c = co.mean(0)
    up = np.linalg.svd(co - c)[2][0]
    up = up if up[2] > 0 else -up
    return Vector(c.tolist()), Vector(up.tolist()).normalized()


def bone_table():
    """The blueprint's bone names and hierarchy (infantry_blueprint/rig.py), this man's joints."""
    B = [("hips", None, Vector((0, 0.03, 0.92)), Vector((0, 0.03, 1.00))),
         ("spine", "hips", Vector((0, 0.03, 1.00)), Vector((0, 0.02, 1.18))),
         ("chest", "spine", Vector((0, 0.02, 1.18)), Vector((0, 0.02, 1.46))),
         ("neck", "chest", Vector((0, 0.02, 1.46)), Vector((0, 0.03, 1.56))),
         ("head", "neck", Vector((0, 0.03, 1.56)), Vector((0, 0.03, 1.84)))]
    for sd, f in (("L", lambda v: v), ("R", mx)):
        a = ARM[sd]
        B += [("clavicle." + sd, "chest", f(Vector((0.03, 0.02, 1.44))), a["S"]),
              ("upperarm." + sd, "clavicle." + sd, a["S"], a["EL"]),
              ("forearm." + sd, "upperarm." + sd, a["EL"], a["W"]),
              ("hand." + sd, "forearm." + sd, a["W"], a["T"]),
              ("thigh." + sd, "hips", f(HIP), f(KNEE)),
              ("shin." + sd, "thigh." + sd, f(KNEE), f(ANKLE)),
              ("foot." + sd, "shin." + sd, f(ANKLE), foot_toe(sd))]
    B.append(("spear", "hand.R", SPEAR_GRIP, SPEAR_GRIP + Vector((0, 0, 0.3))))
    # the shield rides its own bone under the left forearm (owner 2026-09-29: 驻防的手臂动作太扭曲了):
    # fixed to the forearm, holding it upright before the chest wrenched the whole arm out straight
    sc_, su_ = shield_centre()
    B.append(("shield", "forearm.L", sc_, sc_ + su_ * 0.2))
    for side, joints in cloak_joints().items():
        parent = "chest"
        for k in range(len(joints) - 1):
            nm = "cloak.%s.%d" % (side, k + 1)
            B.append((nm, parent, joints[k], joints[k + 1]))
            parent = nm
    return B


def rig():
    old = bpy.data.objects.get("inf_rig")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    arm = bpy.data.armatures.new("inf_rig")
    ob = bpy.data.objects.new("inf_rig", arm)
    coll("Tripo_Game").objects.link(ob)
    arm.display_type = "STICK"
    ob.show_in_front = True
    activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for name, parent, h, t in bone_table():
        b = arm.edit_bones.new(name)
        b.head, b.tail, b.roll = h, t, 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = (eb[parent].tail - h).length < 1e-4
        eb[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    print("rig: %d bones" % len(arm.bones))
    return ob


# ------------------------------------------------------------ weights ----

def _segs(rig_ob):
    return {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig_ob.data.bones}


def _seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def cloak_weights(co):
    """The collar on the chest; below it the three chains, shared across by x and along by
    the joints (after infantry_blueprint/rig.py's cloak_weights)."""
    z = co.z
    top = sstep(CLOAK_Z[0] - 0.06, CLOAK_Z[0] + 0.02, z)
    ws = {"chest": top}
    sd = "L" if co.x >= 0 else "R"
    a = abs(co.x) / CLOAK_X["L"]
    lat = {"C": max(0.0, 1 - a), sd: min(1.0, a)}
    u = (CLOAK_Z[0] - z) / (CLOAK_Z[0] - CLOAK_Z[-1]) * 3.0
    u = min(max(u, 0.5), 2.5)
    along = {k: max(0.0, 1 - abs(u - (k - 0.5))) for k in (1, 2, 3)}
    tot = sum(along.values())
    for side, wl in lat.items():
        for k, wk in along.items():
            if wl * wk > 0:
                nm = "cloak.%s.%d" % (side, k)
                ws[nm] = ws.get(nm, 0.0) + (1 - top) * wl * wk / tot
    return ws


def part_weights(n, co, segs):
    names = PART_BONES[n]
    if names == ["cloak"]:
        return cloak_weights(co)
    sd = "L" if co.x >= 0 else "R"
    cands = [nm.replace(".S", "." + sd) for nm in names]
    if len(cands) == 1:
        return {cands[0]: 1.0}
    ds = sorted((_seg_dist(co, *segs[nm]), nm) for nm in cands)[:2]
    ws = {nm: 1.0 / (d ** 4 + 1e-7) for d, nm in ds}
    tot = sum(ws.values())
    return {nm: w / tot for nm, w in ws.items()}


def skin():
    """Every part weighted, then all joined into `infantry` under the armature; the spear is
    also kept apart as `inf_spear` (MARCH / GARRISON read its axis and its butt)."""
    rig_ob = bpy.data.objects["inf_rig"]
    segs = _segs(rig_ob)
    lows = [o for o in coll("Tripo_Game").objects if o.type == "MESH" and "part" in o]
    for o in lows:
        n = int(o["part"])
        a = o.data.attributes.get("tripo_part") or o.data.attributes.new("tripo_part", "INT", "POINT")
        a.data.foreach_set("value", [n] * len(o.data.vertices))       # kept through the join
        for g in list(o.vertex_groups):
            o.vertex_groups.remove(g)
        groups = {}
        for v in o.data.vertices:
            for bn, w in part_weights(n, o.matrix_world @ v.co, segs).items():
                if w <= 1e-4:
                    continue
                g = groups.get(bn) or o.vertex_groups.new(name=bn)
                groups[bn] = g
                g.add([v.index], w, "REPLACE")
    old = bpy.data.objects.get("inf_spear")
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    sp = [o for o in lows if int(o["part"]) in SPEAR_PARTS]
    spear = sp[0].copy()
    spear.data = sp[0].data.copy()
    for o in sp[1:]:
        bm = bmesh.new()
        bm.from_mesh(spear.data)
        bm.from_mesh(o.data)
        bm.to_mesh(spear.data)
        bm.free()
    spear.name = spear.data.name = "inf_spear"
    coll("Tripo_Game").objects.link(spear)
    spear.hide_set(True)
    spear.hide_render = True
    activate(lows[0])
    for o in lows:
        o.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = "infantry"
    del ob["part"]
    activate(ob)
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = rig_ob
    ob.parent = rig_ob
    print("skin: %d tris, %d groups" % (tris(ob), len(ob.vertex_groups)))
    return ob


# ------------------------------------------------------------ texture ----

def _image(name, colour, fill):
    old = bpy.data.images.get(name)
    if old:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    img.generated_color = fill
    return img


def _emit_from(high_mat, key):
    tex = None
    for nd in high_mat.node_tree.nodes:
        if nd.type == "TEX_IMAGE" and nd.image is not None and key in nd.image.name.lower():
            tex = nd.image
    em = bpy.data.materials.new("tripo_emit_" + key)
    em.use_nodes = True
    nt = em.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = tex
    nt.links.new(t.outputs["Color"], e.inputs["Color"])
    nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
    return em


def unwrap(ob):
    for layer in list(ob.data.uv_layers):
        ob.data.uv_layers.remove(layer)
    ob.data.uv_layers.new(name="UVMap")
    activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004, area_weight=0.0)
    bpy.ops.uv.pack_islands(margin=0.004, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


_FILL = {}


def texture():
    """One 2048 atlas: base colour and roughness-metallic EMITTED from the textured
    generation, its normals baked tangent-space, AO multiplied into the colour, the
    metal held to STEEL_METAL."""
    import cavalry_scan as cs
    sc = scene()
    ob = bpy.data.objects["infantry"]
    high = bpy.data.objects["tripo_high"]
    high.location = (0, 0, 0)
    high.hide_set(False)
    high.hide_render = False
    arm_mod = ob.modifiers.get("Armature")
    if arm_mod:
        arm_mod.show_render = arm_mod.show_viewport = False     # bake the rest pose
    unwrap(ob)
    col = _image("infantry_atlas", True, (0.5, 0.5, 0.5, 1))
    nor = _image("infantry_atlas_n", False, (0.5, 0.5, 1.0, 1))
    mr = _image("infantry_atlas_mr", False, (1.0, 0.6, 0.0, 1))
    mat = cs.atlas_material(col, nor, mr)
    mat.name = "infantry_atlas_mat"
    mat.use_backface_culling = False       # doubleSided like the blueprint piece: a part seen from inside must not vanish
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 1
    try:
        sc.cycles.device = "GPU"
    except TypeError:
        pass
    hm = high.data.materials[0]
    # COVERAGE first: the high model emitting white onto black marks every pixel a bake writes (a
    # sentinel fill colour would not do: the bake blends into what is there at the islands' edges)
    cov = _image("infantry_coverage", False, (0, 0, 0, 1))
    white = bpy.data.materials.new("tripo_emit_white")
    white.use_nodes = True
    em = next(n for n in white.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    white.node_tree.nodes.remove(em)
    e = white.node_tree.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (1, 1, 1, 1)
    white.node_tree.links.new(e.outputs["Emission"], next(n for n in white.node_tree.nodes if n.type == "OUTPUT_MATERIAL").inputs["Surface"])
    high.data.materials[0] = white
    cs.bake_into(ob, high, cov, "EMIT")
    _FILL["mask"] = np.array(cov.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)[..., 0] < 0.5   # no island's pixels
    bpy.data.images.remove(cov)
    high.data.materials[0] = _emit_from(hm, "basecolor")
    cs.bake_into(ob, high, col, "EMIT")
    high.data.materials[0] = _emit_from(hm, "_rm")
    cs.bake_into(ob, high, mr, "EMIT")
    high.data.materials[0] = hm
    cs.bake_into(ob, high, nor, "NORMAL")
    # AO of the game mesh itself, multiplied in: flat-lit plate and cloak read as one lump from the map
    high.hide_render = True
    ao = _image("infantry_ao", False, (1, 1, 1, 1))
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = ao
    for nd in mat.node_tree.nodes:
        nd.select = False
    node.select = True
    mat.node_tree.nodes.active = node
    activate(ob)
    sc.render.bake.use_selected_to_active = False
    sc.render.bake.use_clear = True
    sc.world = sc.world or bpy.data.worlds.new("tripo_world")
    sc.world.light_settings.distance = 0.35
    sc.cycles.samples = 64
    bpy.ops.object.bake(type="AO")
    sc.cycles.samples = 1
    mat.node_tree.nodes.remove(node)
    a = np.array(ao.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)[..., :1]
    c = np.array(col.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    c[..., :3] *= AO_FLOOR + (1.0 - AO_FLOOR) * a
    fill = _FILL["mask"]
    c[fill, :3] = np.median(c[~fill, :3], axis=0)          # the fill takes the baked colour, not magenta
    col.pixels.foreach_set(c.ravel())
    m = np.array(mr.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    m[..., 2] *= STEEL_METAL
    mr.pixels.foreach_set(m.ravel())
    bpy.data.images.remove(ao)
    for img in (col, nor, mr):
        img.pack()
    for nd in [nd for nd in mat.node_tree.nodes if nd.name.startswith("bake_")]:
        mat.node_tree.nodes.remove(nd)
    if arm_mod:
        arm_mod.show_render = arm_mod.show_viewport = True
    high.hide_set(True)
    print("texture: baked %d px atlas" % ATLAS)


# ------------------------------------------------------------ actions ----

def blueprint_inputs():
    """What the blueprint's MARCH / GARRISON read of the body, for this man."""
    R = {"HIP": HIP, "KNEE": KNEE, "ANKLE": ANKLE, "TOE": TOE}
    sp = bpy.data.objects["inf_spear"]
    co = np.array([v.co[:] for v in sp.data.vertices])
    mean = co.mean(0)
    ax = Vector(np.linalg.svd(co - mean)[2][0].tolist())
    if ax.z < 0:
        ax = -ax
    # the shaft laid on the right pauldron's crown, the fist before its front edge
    p = bpy.data.objects.get("tripo_part_10") or part(10)
    pv = [p.matrix_world @ v.co for v in p.data.vertices]
    crown = max(pv, key=lambda v: v.z - 2.0 * abs(v.x - ARM["R"]["S"].x) - 2.0 * abs(v.y - 0.02))
    front = min(v.y for v in pv)
    return dict(R=R, A_REST=ax,
                SH_REST=(crown.x, crown.y, crown.z + 0.012),
                SH_GRIP=(crown.x - 0.005, front - 0.155, 1.215),
                GRIP=(-0.30, -0.26, 1.24))


STANCE = 0.40            # MARCH: the feet walk this share of the rest stance's width out from the hips
CLIPS = ("GARRISON", "STANDBY", "MARCH")
SHIELD_PARTS = (4, 13, 26, 34, 42, 44)


def animate():
    """MARCH (the blueprint's, the feet under him and square), STANDBY (the blueprint's old
    garrison stance, owner 2026-09-29: 你现在的驻防动作其实应该算是待命动作) and GARRISON (guard.py:
    the shield before the chest, the spear laid over it)."""
    for n in CLIPS:
        a = bpy.data.actions.get(n)
        if a:
            bpy.data.actions.remove(a)
    inp = blueprint_inputs()
    exec(open(BLUEPRINT + "march.py").read(), dict(inp, STANCE=STANCE))
    exec(open(BLUEPRINT + "garrison.py").read(), dict(inp, CLIP="STANDBY", FEET_FORWARD=True))
    exec(open(HERE + "guard.py").read(), dict(inp, SHIELD=[part(n) for n in SHIELD_PARTS]))
    bpy.data.objects["inf_rig"].animation_data.action = bpy.data.actions["GARRISON"]
    print("animate: %s" % ", ".join(CLIPS))


# ------------------------------------------------------------- export ----

def export(out_dir, manifest=False):
    """infantry_blueprint/export.py on this rig: the spear upright at rest, +Y forward,
    GARRISON and MARCH as glTF animations, the MARCH stride printed."""
    rig_ob, ob = bpy.data.objects["inf_rig"], bpy.data.objects["infantry"]
    for o in (rig_ob, ob):
        o.hide_set(False)                  # a hidden object cannot be selected, so is not exported
    ad = rig_ob.animation_data
    for tr in list(ad.nla_tracks):         # export.py stashes the actions anew
        ad.nla_tracks.remove(tr)
    argv = sys.argv
    sys.argv = ["blender", "--", out_dir] + (["--manifest"] if manifest else [])
    try:
        exec(open(BLUEPRINT + "export.py").read(), {"CLIPS": CLIPS})
    finally:
        sys.argv = argv
        # export.py turned the rig and the mesh to +Y in their DATA: back to the build frame
        turn = Matrix.Rotation(-math.pi, 4, "Z")
        rig_ob.data.transform(turn)
        ob.data.transform(turn)
        ob.data.update()
        for tr in list(ad.nla_tracks):
            ad.nla_tracks.remove(tr)
        ad.action = bpy.data.actions.get("MARCH")


# -------------------------------------------------------------- shots ----

VIEWS = {"front": (0, -1, 0), "side": (1, 0, 0), "rside": (-1, 0.1, 0.1), "back": (0, 1, 0.2),
         "q": (0.7, -0.7, 0.25), "rq": (-0.7, -0.7, 0.25), "top": (0, -0.35, 1)}


def shoot(out_prefix, action, frames=(1,), views=("front", "side", "q"), centre=(0, 0, 1.05), scale=2.5, size=500):
    """Viewport (OpenGL) shots of the piece, in the open Blender, for the look loop: one PNG per
    view and frame, `<out_prefix>_<action>_<view>_<frame>.png`."""
    sc = scene()
    cam = bpy.data.objects.get("tripo_cam") or bpy.data.objects.new("tripo_cam", bpy.data.cameras.new("tripo_cam"))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = scale
    sc.camera = cam
    sc.render.resolution_x = sc.render.resolution_y = size
    rig_ob = bpy.data.objects["inf_rig"]
    rig_ob.animation_data.action = bpy.data.actions[action]
    area = next(a for a in bpy.context.window.screen.areas if a.type == "VIEW_3D")
    sp = area.spaces.active
    was = sp.overlay.show_overlays
    sp.overlay.show_overlays = False
    out = []
    for v in views:
        d = Vector(VIEWS[v]).normalized()
        cam.location = Vector(centre) + d * 8
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        for f in frames:
            sc.frame_set(f)
            sc.render.filepath = "%s_%s_%s_%03d.png" % (out_prefix, action, v, f)
            with bpy.context.temp_override(area=area, region=[r for r in area.regions if r.type == "WINDOW"][0]):
                bpy.ops.render.opengl(write_still=True, view_context=False)
            out.append(sc.render.filepath)
    sp.overlay.show_overlays = was
    return out


# ---------------------------------------------------------- the look ----
# owner 2026-09-29 (同意): the spear to ~2.6 m, as the blueprint piece's (the runtime sizes a piece
# by its whole box, spear included: at 2.06 m the man was drawn 1.3x bigger and the spear vanished),
# and the steel toned down toward the cavalry's warm dark plate (Tripo's delit silver read white).
SPEAR_LONGER = 0.60              # metres added to the shaft between the fist and the head
STEEL_TARGET = 0.32              # the steel's median value (the atlas's own 0..1) after toning; Tripo's baked ~0.39
STEEL_ROUGH_MIN = 0.55           # and no glossier than this: at Tripo's 0.32 a dielectric sheen read white in the game
STEEL_TINT = (1.0, 0.95, 0.88)   # warm, like cavalry_scan's plate
STEEL_SAT_MAX = 0.16             # a pixel this grey (HSV saturation) and...
STEEL_VAL_MIN = 0.30             # ...this bright is steel; cloak, shield paint, wood and leather are not


def lengthen_spear(extra=SPEAR_LONGER):
    """The shaft stretched above the fist, the head (Tripo part 23) moved up with it; after the bake,
    so the shaft's wood (a plain grain along it) stretches in its UVs and nothing is re-baked. Run
    ONCE on a freshly skinned mesh: it measures the shaft by part, not by height."""
    ob = bpy.data.objects["infantry"]
    part_of = [0] * len(ob.data.vertices)
    ob.data.attributes["tripo_part"].data.foreach_get("value", part_of)
    grip = SPEAR_GRIP.z + 0.03
    shaft = [i for i, n in enumerate(part_of) if n == 45]
    top = max(ob.data.vertices[i].co.z for i in shaft)
    k = (top - grip + extra) / (top - grip)
    for i, n in enumerate(part_of):
        v = ob.data.vertices[i]
        if n == 23:
            v.co.z += extra
        elif n == 45 and v.co.z > grip:
            v.co.z = grip + (v.co.z - grip) * k
    ob.data.update()
    tip = max(ob.data.vertices[i].co.z for i, n in enumerate(part_of) if n == 23)
    print("spear: +%.2f m, shaft x%.2f above the fist, tip at %.2f m" % (extra, k, tip))


def tone_steel():
    """Steel toned toward STEEL_TARGET, only in BAKED pixels (texture() keeps the mask of the fill)."""
    img = bpy.data.images["infantry_atlas"]
    c = np.array(img.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    rgb = c[..., :3]
    fill = _FILL["mask"]
    mx_, mn_ = rgb.max(-1), rgb.min(-1)
    sat = np.where(mx_ > 1e-4, (mx_ - mn_) / np.maximum(mx_, 1e-4), 0)
    steel = ~fill & (sat < STEEL_SAT_MAX) & (mx_ > STEEL_VAL_MIN)
    med = float(np.median(mx_[steel]))
    k = min(1.0, STEEL_TARGET / med)                      # only ever darker
    rgb[steel] = rgb[steel] * k * np.array(STEEL_TINT, np.float32)
    c[..., :3] = np.clip(rgb, 0, 1)
    img.pixels.foreach_set(c.ravel())
    img.pack()
    mri = bpy.data.images["infantry_atlas_mr"]
    m = np.array(mri.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    m[..., 1][steel] = np.maximum(m[..., 1][steel], STEEL_ROUGH_MIN)
    mri.pixels.foreach_set(m.ravel())
    mri.pack()
    print("steel: %.1f%% of the baked pixels, median %.2f -> x%.2f" % (steel.sum() / max(1, (~fill).sum()) * 100, med, k))
