"""UV + TEXTURES for the blueprint man-at-arms (owner 2026-09-28: 先展UV做贴图
（钢、皮革、木头、锁子甲、盾面的磨损和颜色）). The 35 rigged pieces of
`Infantry` are joined into ONE mesh `infantry` (its bones and MARCH kept), each
material's faces unwrapped into its own cell of ONE 2048 atlas, the cells
painted (worn steel, mail rings, leather, ash wood, chipped green / white
paint), a patina and grime baked over the whole figure in object space so it
runs across seams, the rubbed edges lightened, and the ambient occlusion
multiplied in with rust in the crevices. Reuses hand_weather.py's library.

  blender -b infantry_blueprint_model.blend --python texture.py -- OUT.blend
"""
import bpy, math, os, sys
from mathutils import Matrix

SRC = "/Users/samuelzhang/game_design/tools/units3d/infantry_blueprint/"
OUT = sys.argv[sys.argv.index("--") + 1]
os.environ.setdefault("NO_ETCH", "1")                    # the owner chose the plain plate (B)
KIT = SRC + "swatches/"   # the owner's material swatches (overview_4_materials)
# owner 2026-09-29: 盔甲太干净太亮了，做脏做旧 / no environment mirror on the steel.
# AGE=A a field harness, worn and dulled; AGE=B campaign-worn, grimy, rust in every crevice
AGE = os.environ.get("AGE", "C")
AGED = {"A": dict(rgb="0.50,0.48,0.45", rough="0.56", edge="0.62,0.61,0.58", patina=(0.66, 1.02), grime=0.58,
                  ao=0.50, rust=0.42),
        "C": dict(rgb="0.60,0.58,0.54", rough="0.58", edge="", patina=(0.64, 1.02), grime=0.55,
                  ao=0.52, rust=0.45),         # campaign-worn but READABLE on the map at a piece's 30 px
        "B": dict(rgb="0.44,0.41,0.37", rough="0.64", edge="0.56,0.55,0.52", patina=(0.55, 0.98), grime=0.48,
                  ao=0.46, rust=0.55)}[AGE]
# no rubbed-bright edges: Cycles' pointiness is per VERTEX, and on a low-poly plate one sharp corner
# lit a whole quad into a pale square (and the owner asked for dirt, not polish)
os.environ["EDGE_WEAR"] = ""
os.environ.setdefault("STEEL_RGB", AGED["rgb"])
os.environ.setdefault("STEEL_ROUGH", AGED["rough"])       # dull: the sky no longer mirrored in the plate
GREEN = (0.07, 0.20, 0.09)                               # the shield's paint AND the cloak (owner: 和盾牌同色), LINEAR
FADE = 0.20                                               # how far the paint is sun-faded toward grey
FADED = tuple(g * (1 - FADE * 0.4) + f * FADE * 0.4 for g, f in zip(GREEN, (0.36, 0.38, 0.33)))   # the paint's mean


def to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _paint_mean():
    """The mean colour of the owner's shield paint swatch D9b, in its own sRGB numbers."""
    img = bpy.data.images.load(KIT + "D9b_shield_paint.png")
    px = img.pixels[:]
    n = len(px) // 4
    mean = [sum(px[i::4]) / n for i in range(3)]
    bpy.data.images.remove(img)
    return mean


# the atlas tiles are written as sRGB numbers, the bake's shader colours are linear: the cloak's
# tile is the shield's mean paint (D9b, faded as the bake fades it; a little darker, wool drinks
# the light) converted back to sRGB
PAINT_MEAN_LIN = [to_lin(c) for c in _paint_mean()]
os.environ.setdefault("CLOAK_RGB", ",".join("%.3f" % to_srgb(0.88 * (c * (1 - FADE * 0.4) + g * FADE * 0.4))
                                            for c, g in zip(PAINT_MEAN_LIN, (0.36, 0.38, 0.33))))
GRIME = {"A": 0.6, "B": 1.0, "C": 0.8}[AGE]                         # rust spots, streaks and dirt on the steel
L = {"__name__": "hand_weather_lib"}
code = open(SRC + "hand_weather.py").read().rsplit("\nmain()", 1)[0]
for a, b in (("elements[0].color = (0.70, 0.64, 0.58, 1)", "elements[0].color = (%.2f, %.2f, %.2f, 1)" % (AGED["patina"][0], AGED["patina"][0] * 0.93, AGED["patina"][0] * 0.85)),
             ("elements[1].color = (1.06, 1.05, 1.03, 1)", "elements[1].color = (%.2f, %.2f, %.2f, 1)" % ((AGED["patina"][1],) * 3)),
             ("c = c * (1 + fbm(h, w, 48, 3)[..., None] * 0.10)", "c = c * (1 + fbm(h, w, 48, 3)[..., None] * 0.05)"),   # finer: islands differed
             ("rough = np.clip(base_rough + fbm(h, w, 8, 4) * 0.25", "rough = np.clip(base_rough + fbm(h, w, 8, 4) * 0.06"),   # broad roughness broke at seams
             ('grime.inputs["To Min"].default_value = 0.62', 'grime.inputs["To Min"].default_value = %.2f' % AGED["grime"]),
             ("AO_FLOOR = 0.52", "AO_FLOOR = %.2f" % AGED["ao"]),
             ("c[..., :3] * k * (1 - 0.35 * occl) + rust * 0.35 * occl * k", "c[..., :3] * k * (1 - %.2f * occl) + rust * %.2f * occl * k" % (AGED["rust"], AGED["rust"])),
             # cloth, leather and wood get the grime and the patina too, and the shield is painted here
             ('if key in ("steel", "mail", "dark", "brass"):', 'if key in ("steel", "mail", "dark", "brass", "cloak", "leather", "leather_dark", "wood", "shield"):'),
             ('        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, scale_to_bounds=False)',
              '        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, scale_to_bounds=False)\n'
              '        bpy.ops.uv.pack_islands(rotate=True, margin=0.004)   # smart_project left most of each cell empty'),
             # FACE select with UV sync: in vertex mode the faces of a neighbouring material that share
             # every vertex came along, and were unwrapped and packed over the cell already placed
             ('        bpy.ops.object.mode_set(mode="EDIT")\n        bpy.ops.mesh.select_all(action="DESELECT")',
              '        bpy.ops.object.mode_set(mode="EDIT")\n        bpy.ops.mesh.select_mode(type="FACE")\n'
              '        bpy.context.scene.tool_settings.use_uv_select_sync = True\n        bpy.ops.mesh.select_all(action="DESELECT")'),
             ('        nt.links.new(colour, e.inputs["Color"])', '        colour = EXTRA_EMIT(nt, key, colour)\n        nt.links.new(colour, e.inputs["Color"])')):
    assert a in code, a
    code = code.replace(a, b)
exec(compile(code, "hand_weather.py", "exec"), L)
L["HERE"] = SRC                                          # wash.npy / mail.npy
L["MAT_TILE"].update({"arm_steel": "steel", "base_clay": "mail", "arm_leather": "leather", "arm_dark": "dark",
                      "arm_wood": "wood", "arm_brass": "brass", "arm_leather_dark": "leather_dark",
                      "arm_cloak": "cloak", "arm_shield": "shield"})


def orient_outward():
    """The plates are open shells, and a shell's normals were only made CONSISTENT, not
    outward: a plate facing in bakes black (its occlusion rays hit the body). Each
    connected part of each plate is turned to face away from the body's surface, by an
    area-weighted vote of its faces."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    base = bpy.data.objects["inf_base_body"]
    bb = bmesh.new(); bb.from_mesh(base.data)
    tree = BVHTree.FromBMesh(bb)
    cen = sum((v.co for v in bb.verts), __import__("mathutils").Vector()) / len(bb.verts)
    bb.free()
    flipped = []
    for ob in bpy.data.collections["Infantry"].objects:
        if ob.type != "MESH" or ob.name in ("inf_base_body",):
            continue
        bm = bmesh.new(); bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        seen = set()
        n_flip = 0
        for f0 in bm.faces:
            if f0.index in seen:
                continue
            comp, stack = [], [f0]
            seen.add(f0.index)
            while stack:
                f = stack.pop()
                comp.append(f)
                for e in f.edges:
                    for g in e.link_faces:
                        if g.index not in seen:
                            seen.add(g.index)
                            stack.append(g)
            vote = 0.0
            for f in comp:
                c = f.calc_center_median()
                loc, nor, _, _ = tree.find_nearest(c)
                out = (c - loc) if loc is not None and (c - loc).length > 1e-4 else (c - cen)
                if loc is not None and out.dot(nor) < 0:
                    out = nor                        # a face inside the body's hull: trust the body's normal
                vote += f.calc_area() * f.normal.dot(out.normalized())
            if vote < 0:
                bmesh.ops.reverse_faces(bm, faces=comp)
                n_flip += 1
        if n_flip:
            bm.to_mesh(ob.data)
            ob.data.update()
            flipped.append("%s(%d)" % (ob.name, n_flip))
        bm.free()
    print("turned outward:", ", ".join(flipped) or "none")


def join_pieces():
    orient_outward()
    rig = bpy.data.objects["inf_rig"]
    parts = [o for o in bpy.data.collections["Infantry"].objects if o.type == "MESH"]
    for o in bpy.data.objects:
        o.select_set(False)
    for o in parts:
        o.hide_set(False)
        o.select_set(True)
    body = bpy.data.objects["inf_base_body"]
    bpy.context.view_layer.objects.active = body
    with bpy.context.temp_override(active_object=body, object=body, selected_objects=parts,
                                   selected_editable_objects=parts):
        bpy.ops.object.join()
    body.name = body.data.name = "infantry"
    for p in body.data.polygons:
        p.use_smooth = True
    print("joined:", len(body.data.vertices), "verts,", sum(len(p.vertices) - 2 for p in body.data.polygons), "tris,",
          [m.name for m in body.data.materials])
    return body, rig


def arms_clear(on):
    """For the occlusion bake only: the arms swung out from the body so the fists,
    spear and shield do not shade the plate under them; put back after."""
    rig = bpy.data.objects["inf_rig"]
    ad = rig.animation_data
    if on:
        L["_act"] = ad.action if ad else None
        if ad:
            ad.action = None
        for b in rig.pose.bones:
            b.matrix_basis = Matrix.Identity(4)
        for sd, sg in (("L", 1), ("R", -1)):
            rig.pose.bones["upperarm." + sd].rotation_mode = "XYZ"
            rig.pose.bones["upperarm." + sd].rotation_euler = (0, 0, math.radians(0))
            b = rig.pose.bones["upperarm." + sd]
            b.rotation_mode = "QUATERNION"
            from mathutils import Quaternion, Vector
            # swing about the bone's own local Z (in the frontal plane) by 45 degrees away from the body
            b.rotation_quaternion = Quaternion(Vector((0, 0, 1)), math.radians(45 * -sg))
    else:
        for b in rig.pose.bones:
            b.matrix_basis = Matrix.Identity(4)
        if ad and L.get("_act"):
            ad.action = L["_act"]
    bpy.context.view_layer.update()


L["arms_clear"] = arms_clear

# the atlas repacked: steel takes 3x3 of the 4x4 cells; one cell each for mail, leather, wood, the
# cloak, the shield and the dark leather; the last cell quartered for the slit's black and the brass
CELLS = {"steel": (0, 0, 3, 3), "mail": (3, 0, 1, 1), "leather": (3, 1, 1, 1), "wood": (3, 2, 1, 1),
         "cloak": (3, 3, 1, 1), "shield": (0, 3, 1, 1), "leather_dark": (1, 3, 1, 1),
         "dark": (2, 3, 0.5, 0.5), "brass": (2.5, 3, 0.5, 0.5), "smalls": (2, 3, 1, 1)}
L["TILES"].clear()
L["TILES"].update(CELLS)


def shield_paint(nt, colour):
    """Old boards under old paint, in OBJECT space on the shield's own frame (so the boards
    run straight down it whatever the UV): vertical planks with dark seams and grain, each
    board its own shade; a green field with a white pale over them, sun-faded, chipped and
    worn through to the wood, most at the rim, the point and along the seams."""
    fr = list(bpy.context.scene["shield_frame"])
    Cs, wv, hv = fr[0:3], fr[3:6], fr[6:9]
    Lk = nt.links.new

    def node(t, **kw):
        n = nt.nodes.new(t)
        for k, v in kw.items():
            setattr(n, k, v)
        return n

    def vm(op, a, b):
        n = node("ShaderNodeVectorMath", operation=op)
        for idx, v in enumerate((a, b)):
            if isinstance(v, (list, tuple)):
                n.inputs[idx].default_value = v
            else:
                Lk(v, n.inputs[idx])
        return n.outputs["Value" if op == "DOT_PRODUCT" else "Vector"]

    def m(op, a, b=None):
        n = node("ShaderNodeMath", operation=op)
        for idx, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[idx].default_value = v
            else:
                Lk(v, n.inputs[idx])
        return n.outputs["Value"]

    def rng(v, a, b, c=0.0, d=1.0):
        n = node("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        n.clamp = True
        for k_, x in (("From Min", a), ("From Max", b), ("To Min", c), ("To Max", d)):
            n.inputs[k_].default_value = x
        Lk(v, n.inputs["Value"])
        return n.outputs["Result"]

    def noise(vec, scale, detail=6.0, rough=0.6, dist=0.0):
        n = node("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = dist
        Lk(vec, n.inputs["Vector"])
        return n.outputs["Fac"]

    def mix(a, b, f):
        n = node("ShaderNodeMix", data_type="RGBA", blend_type="MIX")
        for sock, v in (("A", a), ("B", b)):
            if isinstance(v, (list, tuple)):
                n.inputs[sock].default_value = tuple(v) + (1.0,)
            else:
                Lk(v, n.inputs[sock])
        if isinstance(f, (int, float)):
            n.inputs["Factor"].default_value = f
        else:
            Lk(f, n.inputs["Factor"])
        return n.outputs["Result"]

    def mul(a, f):
        n = node("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
        n.inputs["Factor"].default_value = 1.0
        Lk(a, n.inputs["A"])
        c = node("ShaderNodeCombineColor")
        for ch in ("Red", "Green", "Blue"):
            Lk(f, c.inputs[ch])
        Lk(c.outputs["Color"], n.inputs["B"])
        return n.outputs["Result"]

    tc = node("ShaderNodeTexCoord")
    P = tc.outputs["Object"]
    d = vm("SUBTRACT", P, Cs)
    u = vm("DOT_PRODUCT", d, wv)
    v = vm("DOT_PRODUCT", d, hv)
    # the owner's swatches laid on the shield's frame: D9b (green paint on boards) and D7b (ash),
    # the boards turned to run DOWN the shield, 11 cm wide (three to a 0.33 m tile)
    uvw = node("ShaderNodeCombineXYZ")
    Lk(m("DIVIDE", v, 0.33), uvw.inputs["X"])
    Lk(m("DIVIDE", u, 0.33), uvw.inputs["Y"])

    def image(name):
        n = node("ShaderNodeTexImage")
        n.image = bpy.data.images.load(KIT + name, check_existing=True)
        n.extension = "REPEAT"
        Lk(uvw.outputs["Vector"], n.inputs["Vector"])
        return n.outputs["Color"]
    painted = image("D9b_shield_paint.png")
    bare = image("D7b_ash_wood.png")
    bw = node("ShaderNodeRGBToBW")
    Lk(bare, bw.inputs["Color"])
    wood = mix(bare, (0.20, 0.17, 0.13), 0.55)                                   # weathered: greyed and darkened
    wood = mul(wood, m("ADD", 0.35, m("MULTIPLY", bw.outputs["Val"], 1.2)))
    pale = rng(m("ABSOLUTE", u), 0.050, 0.044)
    pbw = node("ShaderNodeRGBToBW")
    Lk(painted, pbw.inputs["Color"])
    white = node("ShaderNodeRGB")
    white.outputs["Color"].default_value = (0.62, 0.60, 0.52, 1.0)
    palec = mul(white.outputs["Color"], m("DIVIDE", pbw.outputs["Val"], max(0.05, sum(PAINT_MEAN_LIN) / 3)))
    paint = mix(painted, palec, pale)                                             # the white pale, same brushwork
    fade = noise(P, 3.0, 4.0)
    paint = mix(paint, (0.36, 0.38, 0.33), m("MULTIPLY", rng(fade, 0.35, 0.75), FADE))   # sun-faded, patchy
    wear = m("ADD", m("MULTIPLY", noise(P, 9.0, 6.0), 0.75), m("MULTIPLY", noise(P, 40.0, 3.0), 0.25))
    wear = m("SUBTRACT", wear, m("MULTIPLY", rng(m("ABSOLUTE", u), 0.19, 0.27), 0.22))        # the rim
    wear = m("SUBTRACT", wear, m("MULTIPLY", rng(v, -0.25, -0.50), 0.18))                      # the point
    keep = rng(wear, 0.40, 0.45)
    out = mix(wood, paint, keep)
    return mul(out, rng(noise(P, 2.2, 3.0), 0.30, 0.70, 0.72, 1.05))                      # grime


def steel_grime(nt, colour):
    """Owner 2026-09-29: 做脏做旧. Over the patina, in object space so it runs across seams:
    rust spots, rain streaks running down, and broad dirty blotches."""
    Lk = nt.links.new
    tc = nt.nodes.new("ShaderNodeTexCoord")
    P = tc.outputs["Object"]

    def noise(vec, scale, detail=6.0):
        n = nt.nodes.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = 0.6
        Lk(vec, n.inputs["Vector"])
        return n.outputs["Fac"]

    def rng(v, a, b, c=0.0, d=1.0):
        n = nt.nodes.new("ShaderNodeMapRange")
        n.interpolation_type = "SMOOTHSTEP"
        for k_, x in (("From Min", a), ("From Max", b), ("To Min", c), ("To Max", d)):
            n.inputs[k_].default_value = x
        Lk(v, n.inputs["Value"])
        return n.outputs["Result"]

    def mixc(a, rgb, f):
        n = nt.nodes.new("ShaderNodeMix"); n.data_type = "RGBA"; n.blend_type = "MIX"
        Lk(a, n.inputs["A"]); n.inputs["B"].default_value = rgb + (1.0,)
        Lk(f, n.inputs["Factor"])
        return n.outputs["Result"]

    def scale(v, k):
        n = nt.nodes.new("ShaderNodeMath"); n.operation = "MULTIPLY"
        Lk(v, n.inputs[0]); n.inputs[1].default_value = k
        return n.outputs["Value"]
    stretch = nt.nodes.new("ShaderNodeVectorMath"); stretch.operation = "MULTIPLY"
    Lk(P, stretch.inputs[0]); stretch.inputs[1].default_value = (14.0, 14.0, 1.0)       # long streaks down the plate
    c = mixc(colour, (0.24, 0.21, 0.17), scale(rng(noise(P, 5.0), 0.55, 0.75), 0.30 * GRIME))       # dirty blotches (darker read as holes)
    c = mixc(c, (0.12, 0.10, 0.08), scale(rng(noise(stretch.outputs["Vector"], 3.0, 4.0), 0.55, 0.70), 0.35 * GRIME))   # streaks
    c = mixc(c, (0.20, 0.095, 0.04), scale(rng(noise(P, 22.0, 8.0), 0.64, 0.72), 0.85 * GRIME))      # rust spots
    return c


def EXTRA_EMIT(nt, key, colour):
    """Per-material extras in the patina bake: the shield's boards and paint; the cloak's
    hem dirtied and its top sun-faded."""
    if key == "shield":
        return shield_paint(nt, colour)
    if key == "steel" and GRIME:
        return steel_grime(nt, colour)
    if key == "cloak":
        tc = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
        mr_ = nt.nodes.new("ShaderNodeMapRange")
        mr_.inputs["From Min"].default_value = 0.55; mr_.inputs["From Max"].default_value = 1.0
        mr_.inputs["To Min"].default_value = 0.62; mr_.inputs["To Max"].default_value = 1.0
        nt.links.new(sep.outputs["Z"], mr_.inputs["Value"])
        mx_ = nt.nodes.new("ShaderNodeMix"); mx_.data_type = "RGBA"; mx_.blend_type = "MULTIPLY"
        mx_.inputs["Factor"].default_value = 1.0
        cc = nt.nodes.new("ShaderNodeCombineColor")
        for ch in ("Red", "Green", "Blue"):
            nt.links.new(mr_.outputs["Result"], cc.inputs[ch])
        nt.links.new(colour, mx_.inputs["A"]); nt.links.new(cc.outputs["Color"], mx_.inputs["B"])
        return mx_.outputs["Result"]
    return colour


L["EXTRA_EMIT"] = EXTRA_EMIT




def swatch(name, size, reps=1):
    """One of the owner's swatches as a float array (its own sRGB numbers, like every tile
    here), box-averaged down to `size` and tiled `reps` x `reps`."""
    import numpy as np
    img = bpy.data.images.load(KIT + name)
    w, h = img.size
    a = np.array(img.pixels[:], np.float32).reshape(h, w, 4)[..., :3]
    bpy.data.images.remove(img)
    k = w // size
    if k > 1:
        a = a[:size * k, :size * k].reshape(size, k, size, k, 3).mean((1, 3))
    return np.tile(a, (reps, reps, 1))


def detail(a, contrast=1.0, highpass=0):
    """A swatch's luminance as a multiplier about 1: its scratches, grain and weave without its
    colour. highpass > 0 divides out the swatch's own broad light and dark (a box blur of that
    radius): a UV island takes whatever part of the tile it lands on, so broad patches break
    into hard-edged squares at every seam; the broad patina is baked in object space instead."""
    import numpy as np
    lum = a.mean(-1, keepdims=True)
    if highpass:
        b = lum[..., 0]
        for ax in (0, 1):
            c = np.cumsum(np.concatenate([b.take(range(-highpass, 0), ax), b, b.take(range(highpass), ax)], ax), ax)
            n = b.shape[ax]
            b = (c.take(range(2 * highpass, 2 * highpass + n), ax) - c.take(range(0, n), ax)) / (2 * highpass)
        return 1.0 + (lum / np.maximum(b[..., None], 1e-3) - 1.0) * contrast
    return 1.0 + (lum / max(float(lum.mean()), 1e-3) - 1.0) * contrast


def build_atlas():
    import numpy as np
    mc, CELL, ATLAS = L["mc"], L["CELL"], L["ATLAS"]
    sp = CELLS["smalls"]
    mc.TILES.clear()
    mc.TILES.update({"coat": sp, "steel": sp, "leather": CELLS["leather"], "cloth": sp, "brass": sp,
                     "wood": CELLS["wood"], "hair": sp, "hoof": sp, "shield": sp})
    ccol, cmr = mc.paint_atlas()
    col = np.array(ccol.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    mr = np.array(cmr.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    bpy.data.images.remove(ccol); bpy.data.images.remove(cmr)

    def box(key):
        u0, v0, du, dv = CELLS[key]
        return slice(int(v0 * CELL), int((v0 + dv) * CELL)), slice(int(u0 * CELL), int((u0 + du) * CELL))

    def put(key, trip):
        c, r, m = trip
        ys, xs = box(key)
        col[ys, xs, :3] = c
        mr[ys, xs, 0] = 1.0
        mr[ys, xs, 1] = r
        mr[ys, xs, 2] = m
    H = CELL // 2
    # steel: the aged tint (steel_tile) carrying D1's scratches, pits and dull patches, 3 x 3 over its cells
    c, r, m = L["steel_tile"](3 * CELL, 3 * CELL)
    d1 = detail(swatch("D1_steel_worn.png", CELL, 3), 0.6, highpass=6)   # fine scratches only: coarser broke at seams
    # metallic well under 1: in the game's sky light a fully metallic dark plate reads BLACK at a
    # piece's 30 px (the cavalry paid for this once, README); STEEL_METAL brackets it
    m = np.full_like(m, float(os.environ.get("STEEL_METAL", "0.25")))
    put("steel", (np.clip(c * d1, 0, 1), np.clip(r + (1 - d1[..., 0]) * 0.5, 0.2, 0.95), m))
    mail = swatch("D6b_mail.png", CELL // 3 + 1, 3)[:CELL, :CELL]
    put("mail", (np.clip(mail * 0.55, 0, 1), np.clip(0.45 + (0.5 - mail.mean(-1)) * 0.6, 0.3, 0.9), np.full((CELL, CELL), 0.8, np.float32)))
    # the cloak: D4's felted twill, dyed the shield's green (owner: 和盾牌同色)
    cloak = np.array([float(x) for x in os.environ["CLOAK_RGB"].split(",")], np.float32) * detail(swatch("D4_red_wool.png", CELL // 3 + 1, 3)[:CELL, :CELL], 0.7)
    put("cloak", (np.clip(cloak, 0, 1), np.full((CELL, CELL), 0.93, np.float32), np.zeros((CELL, CELL), np.float32)))
    leather = swatch("D5_leather.png", CELL)
    put("leather", (leather * 0.58, np.full((CELL, CELL), 0.62, np.float32), np.zeros((CELL, CELL), np.float32)))
    wood = swatch("D7b_ash_wood.png", CELL)
    grey = wood.mean(-1, keepdims=True)
    put("wood", (np.clip((wood * 0.55 + grey * 0.45) * 0.62, 0, 1), np.full((CELL, CELL), 0.78, np.float32), np.zeros((CELL, CELL), np.float32)))   # weathered ash
    put("shield", (np.full((CELL, CELL, 3), 0.3, np.float32), np.full((CELL, CELL), 0.82, np.float32),
                   np.zeros((CELL, CELL), np.float32)))
    put("dark", (np.full((H, H, 3), 0.015, np.float32), np.full((H, H), 0.8, np.float32), np.full((H, H), 0.2, np.float32)))
    d8 = swatch("D8_brass_rivets.png", 512)
    px = d8.reshape(-1, 3)
    px = px[(px[:, 0] > px[:, 2] + 0.12) & (px[:, 0] > 0.35)]                 # the brass heads, not the steel between
    brass = px.mean(0).astype(np.float32) * (1 + L["fbm"](H, H, 24, 3)[..., None] * 0.18)
    put("brass", (np.clip(brass, 0, 1), np.clip(0.42 + L["fbm"](H, H, 16, 3) * 0.2, 0.25, 0.75), np.full((H, H), 1.0, np.float32)))
    ys, xs = box("leather")
    yd, xd = box("leather_dark")
    col[yd, xd, :3] = col[ys, xs, :3] * np.array([0.82, 0.68, 0.58], np.float32)   # dark brown (0.5 read black on the map)
    mr[yd, xd] = mr[ys, xs]
    mr[yd, xd, 1] = np.clip(mr[ys, xs, 1] + 0.1, 0, 1)

    def image(name, arr, colour):
        img = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False)
        img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        img.pixels.foreach_set(arr.ravel())
        img.pack()
        return img
    col[..., 3] = 1
    mr[..., 3] = 1
    nor = np.zeros((ATLAS, ATLAS, 4), np.float32); nor[..., 0] = 0.5; nor[..., 1] = 0.5; nor[..., 2] = 1; nor[..., 3] = 1
    ys, xs = box("steel")
    nor[ys, xs, 0] += L["fbm"](3 * CELL, 3 * CELL, 128, 2) * 0.10
    return image("infantry_atlas", col, True), image("infantry_atlas_n", nor, False), image("infantry_atlas_mr", mr, False)


def sharp_edges(ob, deg=40.0):
    """Crisp creases: every edge folding more than `deg` is split in the shading (the
    helmet's slit and comb, the rolled rims), so the plate reads as metal, not soap."""
    import bmesh
    bm = bmesh.new(); bm.from_mesh(ob.data)
    lim = math.radians(deg)
    n = 0
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim:
            e.smooth = False
            n += 1
    bm.to_mesh(ob.data); bm.free()
    print("sharp edges:", n)


def main():
    ob, rig = join_pieces()
    sharp_edges(ob)
    L["unwrap_by_material"](ob)
    col, nor, mr = build_atlas()
    rig.data.pose_position = "REST"
    L["patina_bake"](ob, col)
    mat = L["cs"].atlas_material(col, nor, mr)
    mat.name = "infantry_atlas"
    mat.use_backface_culling = False
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.material_index = 0
    rig.data.pose_position = "POSE"
    L["bake_ao"](ob, col)
    col.name = "infantry_atlas_col"
    for scr in bpy.data.screens:
        for area in scr.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.shading.type = "MATERIAL"
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
    print("SAVED", OUT)


main()
