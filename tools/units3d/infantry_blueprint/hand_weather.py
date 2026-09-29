"""The hand-built man-at-arms dressed in REAL materials: one 2048 atlas whose
steel is the Cleveland 1964.88 scan's own patina (its colour blurred into a
wash, grain and fine scratches over it, so no engraving is recognisable), a
mail tile cut from the scan's mail, procedural wool / leather / brass / wood
/ paint, and the whole figure's ambient occlusion multiplied in.

  blender -b infantry_hand.blend --python hand_weather.py -- OUT.blend
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector

sys.path.insert(0, "/Users/samuelzhang/game_design/tools/units3d")
import model_cavalry as mc
import cavalry_scan as cs

OUT = sys.argv[sys.argv.index("--") + 1]
TEX = "/Users/samuelzhang/game_design/assets/units3d/ai_src/cc0/cleveland_armor/textures/"
ATLAS = 2048
CELL = ATLAS // 4
TILES = {"steel": (0, 0, 2, 2), "mail": (2, 0, 1, 1), "cloth": (3, 0, 1, 1), "leather": (2, 1, 1, 1),
         "brass": (3, 1, 1, 1), "wood": (0, 2, 1, 1), "green": (1, 2, 1, 1), "white": (2, 2, 1, 1),
         "dark": (3, 2, 1, 1)}
MAT_TILE = {"steel": "steel", "brass": "brass", "mail": "mail", "leather": "leather", "visor_dark": "dark",
            "red_wool": "cloth", "ash_wood": "wood", "shield_green": "green", "shield_white": "white"}
AO_FLOOR = 0.52
rng = np.random.default_rng(20260928)


def fbm(h, w, base=4, octaves=5, stretch=(1, 1)):
    def up(a, H, W):
        ys, xs = np.linspace(0, a.shape[0] - 1, H), np.linspace(0, a.shape[1] - 1, W)
        y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
        y1, x1 = np.minimum(y0 + 1, a.shape[0] - 1), np.minimum(x0 + 1, a.shape[1] - 1)
        fy, fx = (ys - y0)[:, None], (xs - x0)[None, :]
        return (a[y0][:, x0] * (1 - fy) * (1 - fx) + a[y1][:, x0] * fy * (1 - fx)
                + a[y0][:, x1] * (1 - fy) * fx + a[y1][:, x1] * fy * fx)
    out = np.zeros((h, w)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        n = base * 2 ** o
        out += up(rng.random((max(2, n // stretch[0]), max(2, n // stretch[1]))), h, w) * amp
        tot += amp; amp *= 0.55
    return out / tot - 0.5


HERE = "/private/tmp/claude-501/-Users-samuelzhang-game-design/3231b72e-f72f-4faa-880f-fd950337854e/scratchpad/inf/hand"
# (Blender's Python has no PIL: the scan crops are cut beforehand into .npy —
#  wash.npy, the breastplate blurred 10 px at 256; mail.npy, a clean mail patch)


def resize(a, h, w):
    ys = np.linspace(0, a.shape[0] - 1, h).astype(int)
    xs = np.linspace(0, a.shape[1] - 1, w).astype(int)
    return a[ys][:, xs]


def blur1(a, r):
    """A small box blur, for the scratch lines."""
    out = a.copy()
    for ax in (0, 1):
        out = (np.roll(out, 1, ax) + out + np.roll(out, -1, ax)) / 3
    return out


def mirror_fill(a, h, w):
    """Tile a patch by mirroring, so its edges meet seamlessly."""
    row = np.concatenate([a, a[:, ::-1]], axis=1)
    blk = np.concatenate([row, row[::-1]], axis=0)
    reps = (h // blk.shape[0] + 1, w // blk.shape[1] + 1, 1)
    return np.tile(blk, reps)[:h, :w]


def steel_tile(h, w):
    """The scan's patina as a wash (heavily blurred colour, no engraving left),
    fine grain and scratches over it."""
    wash = np.load(os.path.join(HERE, "wash.npy"))
    wash = mirror_fill(wash, 512, 512)
    wash = resize(wash, h, w)
    lum = wash.mean(-1, keepdims=True)
    tint = np.array([float(x) for x in os.environ.get("STEEL_RGB", "0.50,0.47,0.43").split(",")], np.float32)  # worn field plate
    # the low-frequency patina is NOT painted here: a UV island takes whatever
    # part of the tile it lands on, so it would break at every seam; it is
    # baked over the model in object space instead (patina_bake)
    c = tint * np.ones_like(lum) * 0.88
    c = c * (1 + fbm(h, w, 48, 3)[..., None] * 0.10)              # fine mottle
    c = c * (1 + fbm(h, w, 64, 3, (1, 10))[..., None] * 0.10)      # brushed grain
    # scratches: thin random lines, lighter
    sc = np.zeros((h, w), np.float32)
    for _ in range(420):
        x0, y0 = rng.random() * w, rng.random() * h
        ang = rng.random() * math.pi
        L = 8 + rng.random() * 60
        n = int(L)
        xs = (x0 + np.cos(ang) * np.arange(n)).astype(int) % w
        ys = (y0 + np.sin(ang) * np.arange(n)).astype(int) % h
        sc[ys, xs] = np.maximum(sc[ys, xs], 0.5 + 0.5 * rng.random())
    sc = blur1(sc, 1)
    c = c + sc[..., None] * 0.10
    # dark pitting / grime spots
    pits = np.clip((fbm(h, w, 90, 2) - 0.28) * 6, 0, 1)
    c = c * (1 - pits[..., None] * 0.45)
    base_rough = float(os.environ.get("STEEL_ROUGH", "0.46"))        # satin, not polished: no hot CG highlights
    rough = np.clip(base_rough + fbm(h, w, 8, 4) * 0.25 + pits * 0.3 - sc * 0.1, 0.12, 0.95)
    return np.clip(c, 0, 1), rough, np.full((h, w), 0.85, np.float32)


def mail_tile(h, w):
    m = np.load(os.path.join(HERE, "mail.npy"))
    m = resize(m, m.shape[0] // 3, m.shape[1] // 3)       # rings at a man's scale on this tile
    m = mirror_fill(m, h, w)
    lum = m.mean(-1, keepdims=True)
    lum = lum / max(float(lum.mean()), 1e-3)
    lum = 1 + (lum - 1) * 0.45                            # the rings, not a chequer
    c = np.array([0.30, 0.29, 0.27], np.float32) * lum
    rough = np.clip(0.5 + (1 - lum[..., 0]) * 0.4, 0.25, 0.9)
    return np.clip(c, 0, 1), rough, np.full((h, w), 0.8, np.float32)


def wool_tile(h, w):
    yy, xx = np.mgrid[0:h, 0:w]
    weave = (np.sin(xx * 1.3) * np.sin(yy * 1.3)) * 0.04
    base = np.array([float(x) for x in os.environ.get("CLOAK_RGB", "0.36,0.055,0.045").split(",")], np.float32)
    c = base * (1 + fbm(h, w, 8, 5)[..., None] * 0.35 + weave[..., None] + fbm(h, w, 96, 2)[..., None] * 0.15)
    # faded, dusty toward the hem (the tile's bottom rows are the cloak's lower end is not known: keep uniform)
    return np.clip(c, 0, 1), np.full((h, w), 0.93, np.float32), np.zeros((h, w), np.float32)


def paint_tile(rgb, h, w, rough=0.55):
    base = np.array(rgb, np.float32)
    c = base * (1 + fbm(h, w, 6, 5)[..., None] * 0.18)
    chips = np.clip((fbm(h, w, 40, 3) - 0.30) * 8, 0, 1)            # small chips showing wood
    c = c * (1 - chips[..., None]) + np.array([0.30, 0.20, 0.11]) * chips[..., None]
    grime = np.clip(fbm(h, w, 5, 4) * 1.5, -0.2, 0.3)
    c = c * (1 - grime[..., None] * 0.4)
    return np.clip(c, 0, 1), np.full((h, w), rough, np.float32) + chips * 0.2, np.zeros((h, w), np.float32)


def build_atlas():
    # model_cavalry's leather / brass / wood, painted where this atlas wants them
    mc.TILES.clear()
    mc.TILES.update({"coat": (0, 3, 1, 1), "steel": (1, 3, 1, 1), "leather": TILES["leather"], "cloth": (2, 3, 1, 1),
                     "brass": TILES["brass"], "wood": TILES["wood"], "hair": (3, 3, 1, 1), "hoof": (3, 3, 1, 1),
                     "shield": (0, 3, 1, 1)})
    ccol, cmr = mc.paint_atlas()
    col = np.array(ccol.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    mr = np.array(cmr.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    bpy.data.images.remove(ccol); bpy.data.images.remove(cmr)

    def put(key, trip):
        c, r, m = trip
        u0, v0, du, dv = TILES[key]
        ys, xs = slice(v0 * CELL, (v0 + dv) * CELL), slice(u0 * CELL, (u0 + du) * CELL)
        col[ys, xs, :3] = c
        mr[ys, xs, 0] = 1.0
        mr[ys, xs, 1] = r
        mr[ys, xs, 2] = m
    put("steel", steel_tile(2 * CELL, 2 * CELL))
    put("mail", mail_tile(CELL, CELL))
    put("cloth", wool_tile(CELL, CELL))
    put("green", paint_tile((0.05, 0.24, 0.09), CELL, CELL))
    put("white", paint_tile((0.72, 0.70, 0.64), CELL, CELL))
    put("dark", (np.full((CELL, CELL, 3), 0.02, np.float32), np.full((CELL, CELL), 0.7, np.float32),
                 np.full((CELL, CELL), 0.3, np.float32)))
    # the brass a little duller, the leather darker
    for key, k in (("brass", 0.85), ("leather", 0.8)):
        u0, v0, du, dv = TILES[key]
        col[v0 * CELL:(v0 + dv) * CELL, u0 * CELL:(u0 + du) * CELL, :3] *= k

    def image(name, arr, colour):
        img = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False)
        img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        img.pixels.foreach_set(arr.ravel())
        img.pack()
        return img
    col[..., 3] = 1
    mr[..., 3] = 1
    nor = np.zeros((ATLAS, ATLAS, 4), np.float32); nor[..., 0] = 0.5; nor[..., 1] = 0.5; nor[..., 2] = 1; nor[..., 3] = 1
    # a whisper of the steel grain in the normal map, so highlights break up
    u0, v0, du, dv = TILES["steel"]
    g = fbm(dv * CELL, du * CELL, 128, 2) * 0.10
    nor[v0 * CELL:(v0 + dv) * CELL, u0 * CELL:(u0 + du) * CELL, 0] += g
    return image("infantry_atlas", col, True), image("infantry_atlas_n", nor, False), image("infantry_atlas_mr", mr, False)


def unwrap_by_material(ob):
    me = ob.data
    for layer in list(me.uv_layers):
        me.uv_layers.remove(layer)
    me.uv_layers.new(name="UVMap")
    mc.activate(ob)
    for mi, mat in enumerate(me.materials):
        key = MAT_TILE[mat.name]
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        for p in me.polygons:
            p.select = (p.material_index == mi)
        if not any(p.select for p in me.polygons):
            continue
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        # into its tile, uniformly scaled, inset
        uv = me.uv_layers.active.data
        loops = [li for p in me.polygons if p.material_index == mi for li in p.loop_indices]
        us = [uv[i].uv[0] for i in loops]; vs = [uv[i].uv[1] for i in loops]
        lo_u, lo_v = min(us), min(vs)
        span = max(max(us) - lo_u, max(vs) - lo_v, 1e-6)
        u0, v0, du, dv = TILES[key]
        inset = 8 / ATLAS
        size = min(du, dv) / 4 - 2 * inset
        for i in loops:
            u, v = uv[i].uv
            uv[i].uv = (u0 / 4 + inset + (u - lo_u) / span * size, v0 / 4 + inset + (v - lo_v) / span * size)


def arms_clear(on):
    """For the occlusion bake only: at rest the left fist and the shield hang
    5 cm before the chest and the right fist before the hip, and baked a black
    blot into the plate under them (owner 2026-09-28). The arms are swung down
    and out for the bake and put back after."""
    from mathutils import Vector, Matrix
    rig = bpy.data.objects.get("infantry_rig")
    if not rig:
        return
    pb = rig.pose.bones
    if not on:
        for b in pb:
            b.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()
        return
    for name, d in (("upperarm_l", (-0.45, -0.05, -1.0)), ("forearm_l", (-0.45, -0.05, -1.0)),
                    ("upperarm_r", (0.45, -0.05, -1.0)), ("forearm_r", (0.45, -0.05, -1.0))):
        b = pb[name]
        bpy.context.view_layer.update()
        cur = b.matrix.to_3x3()
        y = (cur @ Vector((0, 1, 0))).normalized()
        q = y.rotation_difference(Vector(d).normalized()).to_matrix()
        b.matrix = Matrix.Translation(b.head) @ (q @ cur).to_4x4()
    bpy.context.view_layer.update()


def bake_ao(ob, col):
    arms_clear(True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 64
    sc.cycles.device = "GPU"
    ao = bpy.data.images.new("ao_tmp", ATLAS, ATLAS, alpha=False, float_buffer=False)
    ao.colorspace_settings.name = "Non-Color"
    mat = ob.data.materials[0]
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = ao
    for n in mat.node_tree.nodes:
        n.select = False
    node.select = True
    mat.node_tree.nodes.active = node
    mc.activate(ob)
    sc.render.bake.use_selected_to_active = False
    sc.render.bake.use_clear = True
    sc.render.bake.margin = 6
    sc.world = sc.world or bpy.data.worlds.new("w")
    sc.world.light_settings.distance = 0.07          # crevices only: the mail under the plates must not shade them
    bpy.ops.object.bake(type="AO")
    mat.node_tree.nodes.remove(node)
    a = np.array(ao.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)[..., :1]
    c = np.array(col.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    baked = np.array(ao.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)[..., 0] < 0.999
    k = np.where(baked[..., None], AO_FLOOR + (1 - AO_FLOOR) * a, 1.0)
    occl = np.where(baked[..., None], 1.0 - a, 0.0)
    rust = np.array([0.30, 0.15, 0.07], np.float32)
    c[..., :3] = c[..., :3] * k * (1 - 0.35 * occl) + rust * 0.35 * occl * k
    col.pixels.foreach_set(c.ravel())
    col.pack()
    bpy.data.images.remove(ao)
    arms_clear(False)


ETCH_BANDS = (0.0, -0.078, 0.078)       # x of each vertical band on breast and back plate
ETCH_W = 0.017                          # half width
ETCH_Z = (1.00, 1.50)


def etched_bands(nt, tc, colour):
    """Three vertical etched bands down breast and back plate, as the scanned
    close helmet carries: a dark double border and a dark scrolling ground
    inside, in object space so they run straight across UV seams."""
    L = nt.links.new
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    L(tc.outputs["Object"], sep.inputs["Vector"])

    def mr(val, a, b, c=0.0, d=1.0, smooth=True):
        m = nt.nodes.new("ShaderNodeMapRange")
        m.interpolation_type = "SMOOTHSTEP" if smooth else "LINEAR"
        m.inputs["From Min"].default_value = a
        m.inputs["From Max"].default_value = b
        m.inputs["To Min"].default_value = c
        m.inputs["To Max"].default_value = d
        L(val, m.inputs["Value"])
        return m.outputs["Result"]

    def math(op, a, b=None):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = op
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, float):
                n.inputs[i].default_value = v
            else:
                L(v, n.inputs[i])
        return n.outputs["Value"]
    band = border = None
    for c in ETCH_BANDS:
        d = math("ABSOLUTE", math("SUBTRACT", sep.outputs["X"], c))
        inside = mr(d, ETCH_W, ETCH_W - 0.0012)                # 1 inside the band
        inner = mr(d, ETCH_W - 0.0032, ETCH_W - 0.0044)        # 1 inside the inner border line
        line = math("SUBTRACT", inside, inner)                 # the outer border line
        mid = math("SUBTRACT", mr(d, ETCH_W - 0.0060, ETCH_W - 0.0072), mr(d, ETCH_W - 0.0084, ETCH_W - 0.0096))
        bl = math("MAXIMUM", line, mid)
        band = inner if band is None else math("MAXIMUM", band, inner)
        border = bl if border is None else math("MAXIMUM", border, bl)
    zm = math("MULTIPLY", mr(sep.outputs["Z"], ETCH_Z[0], ETCH_Z[0] + 0.012),
              mr(sep.outputs["Z"], ETCH_Z[1], ETCH_Z[1] - 0.012))
    # the etched ground: a scrolling wave pattern broken by noise
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.inputs["Scale"].default_value = 60.0
    wave.inputs["Distortion"].default_value = 9.0
    wave.inputs["Detail"].default_value = 3.0
    L(tc.outputs["Object"], wave.inputs["Vector"])
    ground = mr(wave.outputs["Fac"], 0.55, 0.75)
    inner_band = math("SUBTRACT", band, border)
    dark = math("ADD", math("MULTIPLY", border, 0.55), math("MULTIPLY", math("MULTIPLY", inner_band, ground), 0.38))
    dark = math("MULTIPLY", dark, zm)
    keep = math("SUBTRACT", 1.0, dark)
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    L(colour, mix.inputs["A"])
    comb = nt.nodes.new("ShaderNodeCombineColor")
    for ch in ("Red", "Green", "Blue"):
        L(keep, comb.inputs[ch])
    L(comb.outputs["Color"], mix.inputs["B"])
    return mix.outputs["Result"]


def patina_bake(ob, col):
    """Every slot re-emits its atlas colour; steel and mail are multiplied by
    object-space patina (blotches ~25 cm) and grime that thickens toward the
    feet. Baked back into the atlas, so the patina runs across UV seams."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 1
    sc.cycles.device = "GPU"
    out = bpy.data.images.new("patina_tmp", ATLAS, ATLAS, alpha=False, float_buffer=False)
    out.colorspace_settings.name = "sRGB"
    saved = list(ob.data.materials)
    for i, m in enumerate(saved):
        key = MAT_TILE[m.name]
        em = bpy.data.materials.new("emit_" + m.name)
        em.use_nodes = True
        nt = em.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        e = nt.nodes.new("ShaderNodeEmission")
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = col; t.interpolation = "Closest"
        colour = t.outputs["Color"]
        if key in ("steel", "mail", "dark", "brass"):
            tc = nt.nodes.new("ShaderNodeTexCoord")
            nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 3.5
            nz.inputs["Detail"].default_value = 6.0; nz.inputs["Roughness"].default_value = 0.6
            ramp = nt.nodes.new("ShaderNodeValToRGB")
            ramp.color_ramp.elements[0].position = 0.32; ramp.color_ramp.elements[0].color = (0.70, 0.64, 0.58, 1)
            ramp.color_ramp.elements[1].position = 0.65; ramp.color_ramp.elements[1].color = (1.06, 1.05, 1.03, 1)
            sep = nt.nodes.new("ShaderNodeSeparateXYZ")
            grime = nt.nodes.new("ShaderNodeMapRange")          # z 0 m -> 0.72, z 0.6 m -> 1
            grime.inputs["From Min"].default_value = 0.0; grime.inputs["From Max"].default_value = 0.6
            grime.inputs["To Min"].default_value = 0.62; grime.inputs["To Max"].default_value = 1.0
            m1 = nt.nodes.new("ShaderNodeMix"); m1.data_type = "RGBA"; m1.blend_type = "MULTIPLY"
            m1.inputs["Factor"].default_value = 1.0
            m2 = nt.nodes.new("ShaderNodeMix"); m2.data_type = "RGBA"; m2.blend_type = "MULTIPLY"
            m2.inputs["Factor"].default_value = 1.0
            L = nt.links.new
            L(tc.outputs["Object"], nz.inputs["Vector"]); L(nz.outputs["Fac"], ramp.inputs["Fac"])
            L(tc.outputs["Object"], sep.inputs["Vector"]); L(sep.outputs["Z"], grime.inputs["Value"])
            L(colour, m1.inputs["A"]); L(ramp.outputs["Color"], m1.inputs["B"])
            L(m1.outputs["Result"], m2.inputs["A"]); L(grime.outputs["Result"], m2.inputs["B"])
            colour = m2.outputs["Result"]
            head = os.environ.get("SPEARHEAD_RGB")
            if head and key == "steel":
                # a blackened harness, but the spearhead is bright steel (it is the only steel above 1.9 m)
                sepz = nt.nodes.new("ShaderNodeSeparateXYZ")
                hm = nt.nodes.new("ShaderNodeMapRange")
                hm.inputs["From Min"].default_value = 1.88; hm.inputs["From Max"].default_value = 1.92
                hx = nt.nodes.new("ShaderNodeMix"); hx.data_type = "RGBA"
                hx.inputs["B"].default_value = tuple(float(x) for x in head.split(",")) + (1.0,)
                nt.links.new(tc.outputs["Object"], sepz.inputs["Vector"])
                nt.links.new(sepz.outputs["Z"], hm.inputs["Value"])
                nt.links.new(hm.outputs["Result"], hx.inputs["Factor"])
                nt.links.new(colour, hx.inputs["A"])
                colour = hx.outputs["Result"]
            if key == "steel" and not os.environ.get("NO_ETCH"):
                colour = etched_bands(nt, tc, colour)
            edge = os.environ.get("EDGE_WEAR")
            if edge and key in ("steel", "dark"):
                geo = nt.nodes.new("ShaderNodeNewGeometry")
                er = nt.nodes.new("ShaderNodeMapRange")
                er.inputs["From Min"].default_value = 0.54; er.inputs["From Max"].default_value = 0.64
                er.inputs["To Min"].default_value = 0.0; er.inputs["To Max"].default_value = 0.45   # rubbed, not painted
                mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"; mx.blend_type = "MIX"
                mx.inputs["B"].default_value = tuple(float(x) for x in edge.split(",")) + (1.0,)
                nt.links.new(geo.outputs["Pointiness"], er.inputs["Value"])
                nt.links.new(er.outputs["Result"], mx.inputs["Factor"])
                nt.links.new(colour, mx.inputs["A"])
                colour = mx.outputs["Result"]
        nt.links.new(colour, e.inputs["Color"])
        nt.links.new(e.outputs["Emission"], o.inputs["Surface"])
        tgt = nt.nodes.new("ShaderNodeTexImage"); tgt.image = out
        for n in nt.nodes:
            n.select = False
        tgt.select = True
        nt.nodes.active = tgt
        ob.data.materials[i] = em
    mc.activate(ob)
    sc.render.bake.use_selected_to_active = False
    sc.render.bake.use_clear = True
    sc.render.bake.margin = 8
    bpy.ops.object.bake(type="EMIT")
    for i, m in enumerate(saved):
        ob.data.materials[i] = m
    a = np.array(out.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    c = np.array(col.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    filled = a[..., :3].sum(-1) > 1e-4
    c[filled, :3] = a[filled, :3]
    col.pixels.foreach_set(c.ravel())
    col.pack()
    bpy.data.images.remove(out)


def pleat_cloak(ob):
    """The cloak subdivided and folded: vertical pleats that deepen toward the
    hem, a hem that rises and falls with them — a sheet of wool, not a board."""
    me = ob.data
    wool = next(i for i, m in enumerate(me.materials) if m.name == "red_wool")
    bm = bmesh.new()
    bm.from_mesh(me)
    faces = [f for f in bm.faces if f.material_index == wool]
    edges = list({e for f in faces for e in f.edges})
    bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)
    bm.faces.ensure_lookup_table()
    verts = {v for f in bm.faces if f.material_index == wool for v in f.verts}
    zs = [v.co.z for v in verts]
    ztop, zbot = max(zs), min(zs)
    cy = sum(v.co.y for v in verts) / len(verts) + 0.10     # the axis the cloak wraps round, in front of it
    for v in verts:
        t = (ztop - v.co.z) / max(ztop - zbot, 1e-3)
        ang = math.atan2(v.co.x, -(v.co.y - cy))
        amp = 0.004 + 0.030 * t ** 1.1
        d = Vector((v.co.x, v.co.y - cy, 0.0))
        if d.length < 1e-4:
            continue
        d.normalize()
        fold = math.sin(ang * 9.0 + 0.6 * math.sin(ang * 3.0)) + 0.35 * math.sin(ang * 17.0 + 1.3)
        v.co += d * amp * fold
        if t > 0.9:
            v.co.z += 0.018 * math.sin(ang * 9.0 + 1.2) * (t - 0.9) / 0.1
    # the cloak hangs, it does not stand off the back: its lower half is drawn
    # in toward the legs (it flared out to the calf at rest)
    for v in verts:
        t = (ztop - v.co.z) / max(ztop - zbot, 1e-3)
        if t > 0.35 and v.co.y < 0:
            k = min(1.0, (t - 0.35) / 0.65)
            v.co.y = v.co.y * (1 - 0.16 * k)
    bm.to_mesh(me)
    bm.free()
    me.update()


def main():
    ob = bpy.data.objects["infantry"]
    if not os.environ.get("NO_CLOAK"):
        pleat_cloak(ob)
    else:
        wool = next(i for i, m in enumerate(ob.data.materials) if m.name == "red_wool")
        bm = bmesh.new(); bm.from_mesh(ob.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index == wool], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(ob.data); bm.free()
    unwrap_by_material(ob)
    col, nor, mr = build_atlas()
    patina_bake(ob, col)
    mat = cs.atlas_material(col, nor, mr)
    mat.name = "infantry_atlas"
    mat.use_backface_culling = False
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.material_index = 0
    bake_ao(ob, col)
    for scr in bpy.data.screens:
        for area in scr.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.shading.type = "MATERIAL"
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
    print("SAVED", OUT)


main()
