"""Courier model v3, the texture: reduce the scans, unwrap everything into ONE 2048 atlas,
paint, bake, join (the cavalry's route: cavalry_scan.py's bake_into / atlas_material).

Paint (emission shaders, the bake's source):
  * region base colours from the costume attributes (the rider) and the part tags (tack,
    clothes, props), the horse's marks painted in object space (points, hooves, muzzle,
    mane and tail, eyes) over a soft dapple;
  * the painted material tiles (assets/flux/out/courier_tiles/, TILE below), box-projected
    in object space at a real-world size so they run continuous across UV seams;
  * masks: curvature (Cycles pointiness) wears the edges of leather and metal, dirt rises
    towards the hooves and the boot soles; ambient occlusion is baked separately and
    multiplied in;
  * the motifs (the crosses, the crown, the cloth's border, the cuffs) are geometry in
    their own flat colour, so they bake as crisp shapes.
Bakes: colour (EMIT; the horse and rider selected-to-active from their scans), tangent
normals from the scans, AO over the assembled piece, metal/roughness (EMIT of an MR
variant). Then everything joins into one object on one material.
"""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector

HERE = __file__.rsplit("/", 1)[0]
TILES = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))) + "/assets/flux/out/courier_tiles/"
ATLAS = 2048
MARGIN = 6
BUDGET = {"horse": 5600, "rider": 2900, "rider_head": 1150, "boots": 560}
PART_TRIS = {}
# which painted tile each region wears, and its real-world size (metres per tile repeat)
TILE = {
    "coat": ("zimage_T1_s1.png", 0.9),
    "wool": ("zimage_T2_s2.png", 0.22),
    "leather": ("zimage_T3_s1.png", 0.30),
    "gold": ("zimage_T4_s2.png", 0.08),
    "brass": ("zimage_T5_s1.png", 0.12),
    "felt": ("zimage_T6_s1.png", 0.20),
    "canvas": ("zimage_T7_s1.png", 0.18),
}


def lin(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


# ---------------------------------------------------------------- node helpers
class NT:
    def __init__(self, mat):
        mat.use_nodes = True
        self.nt = mat.node_tree
        for n in list(self.nt.nodes):
            self.nt.nodes.remove(n)
        self.out = self.nt.nodes.new("ShaderNodeOutputMaterial")

    def n(self, kind, **kw):
        node = self.nt.nodes.new(kind)
        for k, v in kw.items():
            setattr(node, k, v)
        return node

    def L(self, a, b):
        self.nt.links.new(a, b)

    def rgb(self, col):
        n = self.n("ShaderNodeRGB")
        n.outputs[0].default_value = (*col, 1.0)
        return n.outputs[0]

    def value(self, v):
        n = self.n("ShaderNodeValue")
        n.outputs[0].default_value = v
        return n.outputs[0]

    def tile(self, key, tint=None, gain=1.0):
        """The painted tile, box-projected on object coordinates at its real size."""
        fname, size = TILE[key]
        img = bpy.data.images.get(fname) or bpy.data.images.load(TILES + fname)
        tc = self.n("ShaderNodeTexCoord")
        mp = self.n("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (1 / size, 1 / size, 1 / size)
        tx = self.n("ShaderNodeTexImage")
        tx.image = img
        tx.projection = "BOX"
        tx.projection_blend = 0.3
        self.L(tc.outputs["Object"], mp.inputs["Vector"])
        self.L(mp.outputs["Vector"], tx.inputs["Vector"])
        out = tx.outputs["Color"]
        if tint is not None:
            out = self.mul(out, self.rgb(tint))
        if gain != 1.0:
            out = self.mul(out, self.rgb((gain, gain, gain)))
        return out

    def mul(self, a, b):
        m = self.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
        m.inputs["Factor"].default_value = 1.0
        self.L(a, m.inputs[6])
        self.L(b, m.inputs[7])
        return m.outputs[2]

    def mix(self, fac, a, b):
        m = self.n("ShaderNodeMix", data_type="RGBA")
        if isinstance(fac, float):
            m.inputs["Factor"].default_value = fac
        else:
            self.L(fac, m.inputs["Factor"])
        self.L(a, m.inputs[6])
        self.L(b, m.inputs[7])
        return m.outputs[2]

    def attr(self, name, channel=None):
        a = self.n("ShaderNodeAttribute")
        a.attribute_name = name
        if channel is None:
            return a.outputs["Color"]
        if channel == "Alpha":
            return a.outputs["Alpha"]
        sep = self.n("ShaderNodeSeparateColor")
        self.L(a.outputs["Color"], sep.inputs["Color"])
        return sep.outputs[channel]

    def sharp(self, v, lo=0.4, hi=0.6):
        r = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        r.inputs["From Min"].default_value = lo
        r.inputs["From Max"].default_value = hi
        self.L(v, r.inputs["Value"])
        return r.outputs["Result"]

    def zramp(self, z0, z1):
        """0 at z0 rising to 1 at z1 (object z)."""
        tc = self.n("ShaderNodeTexCoord")
        sep = self.n("ShaderNodeSeparateXYZ")
        self.L(tc.outputs["Object"], sep.inputs["Vector"])
        r = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        r.inputs["From Min"].default_value = z0
        r.inputs["From Max"].default_value = z1
        self.L(sep.outputs["Z"], r.inputs["Value"])
        return r.outputs["Result"]

    def noise(self, scale, detail=3.0):
        tc = self.n("ShaderNodeTexCoord")
        nz = self.n("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = scale
        nz.inputs["Detail"].default_value = detail
        self.L(tc.outputs["Object"], nz.inputs["Vector"])
        return nz.outputs["Fac"]

    def wear(self, col, amount, lighten=(0.9, 0.8, 0.65)):
        """Curvature wear: the convex edges (pointiness) go paler."""
        g = self.n("ShaderNodeNewGeometry")
        r = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        r.inputs["From Min"].default_value = 0.6
        r.inputs["From Max"].default_value = 0.75
        r.inputs["To Max"].default_value = amount
        self.L(g.outputs["Pointiness"], r.inputs["Value"])
        return self.mix(r.outputs["Result"], col, self.rgb(lin("D8C8A8")))

    def dirt(self, col, z0, z1, amount=0.5, tint="5A4A38"):
        f = self.n("ShaderNodeMath", operation="MULTIPLY")
        self.L(self.zramp(z1, z0), f.inputs[0])
        f.inputs[1].default_value = amount
        return self.mix(f.outputs[0], col, self.mul(col, self.rgb(lin(tint))))

    def emit(self, col):
        e = self.n("ShaderNodeEmission")
        self.L(col, e.inputs["Color"])
        self.L(e.outputs["Emission"], self.out.inputs["Surface"])


# ---------------------------------------------------------------- the paint
def paint_tag(mat):
    """Colour paint for a part-tag material (tack, clothes, props, boots)."""
    t = NT(mat)
    tag = mat.name.split(".")[0]
    if tag in ("cloth_blue", "doublet"):
        col = t.tile("wool", tint=(1.25, 1.25, 1.35))
    elif tag == "gold":
        col = t.wear(t.tile("gold", gain=1.1), 0.25)
    elif tag == "brass":
        col = t.wear(t.tile("brass", gain=1.2), 0.3)
    elif tag == "leather":
        col = t.dirt(t.wear(t.tile("leather", tint=lin("5E4436")), 0.1), 1.0, 1.35, 0.3)
    elif tag == "leather_case":
        col = t.wear(t.tile("leather", tint=lin("E8C8B0")), 0.4)
    elif tag == "boot":
        col = t.dirt(t.wear(t.tile("leather", tint=lin("4A3A32")), 0.3), 0.86, 1.02, 0.6)
    elif tag == "hat_felt":
        col = t.tile("felt", gain=1.05)
    elif tag == "hat_band":
        col = t.tile("felt", tint=lin("5A5A50"))
    elif tag in ("linen", "hose"):
        col = t.tile("canvas", gain=1.08)
    elif tag == "feather":
        col = t.mix(t.zramp(2.55, 2.75), t.rgb(lin("F2EEE4")), t.rgb(lin("B89A78")))
    elif tag == "steel":
        col = t.wear(t.mix(t.noise(40.0), t.rgb(lin("8C9096")), t.rgb(lin("B4B8BC"))), 0.4)
    elif tag == "wood":
        col = t.mix(t.noise(28.0, 6.0), t.rgb(lin("5C3A22")), t.rgb(lin("7E5234")))
    elif tag == "skin":
        col = t.mix(t.noise(80.0), t.rgb(lin("C0876A")), t.rgb(lin("D09A7C")))
    elif tag == "horse_eye":
        # a dark brown iris with a darker pupil band across it; the gloss is in the MR
        tc = t.n("ShaderNodeTexCoord")
        sep = t.n("ShaderNodeSeparateXYZ")
        t.L(tc.outputs["Object"], sep.inputs["Vector"])
        col = t.mix(t.noise(200.0), t.rgb(lin("1E120C")), t.rgb(lin("3A2416")))
    elif tag == "horse_lid":
        col = t.rgb(lin("4E4C4C"))
    elif tag == "horse_mane":
        roots = t.zramp(1.2, 1.9)
        base = t.mix(t.noise(140.0, 8.0), t.rgb(lin("CFC8BA")), t.rgb(lin("F4F0E8")))
        col = t.mix(t.sharp(t.noise(30.0, 2.0), 0.35, 0.75), t.mul(base, t.rgb((0.9, 0.9, 0.9))), base)
    else:
        col = t.rgb(lin("BBBBBB"))
    t.emit(col)


MR = {"horse_eye": (0.08, 0.0), "horse_lid": (0.5, 0.0), "horse_mane": (0.7, 0.0), "gold": (0.35, 0.9), "brass": (0.4, 0.85), "steel": (0.35, 0.9), "leather": (0.55, 0.0),
      "leather_case": (0.5, 0.0), "boot": (0.45, 0.0), "wood": (0.7, 0.0)}


def paint_mr(mat):
    t = NT(mat)
    rough, metal = MR.get(mat.name.split(".")[0], (0.85, 0.0))
    t.emit(t.rgb((1.0, rough, metal)))


def paint_rider(mat):
    """The costumed body: skin, overlaid by the costume regions (rgn_a / rgn_b)."""
    t = NT(mat)
    skin = t.mix(t.noise(60.0), t.rgb(lin("C28A6A")), t.rgb(lin("D29C7C")))
    col = skin
    regions_a = [("Red", t.tile("wool", tint=(1.25, 1.25, 1.35))),                        # doublet
                 ("Green", t.tile("canvas", gain=1.05)),                                     # hose
                 ("Blue", t.dirt(t.tile("leather", tint=lin("4A3A32")), 0.86, 1.1, 0.5)),  # boot
                 ("Alpha", None)]
    for ch, c in regions_a[:3]:
        col = t.mix(t.sharp(t.attr("rgn_a", ch)), col, c)
    a = t.n("ShaderNodeAttribute")
    a.attribute_name = "rgn_a"
    col = t.mix(t.sharp(a.outputs["Alpha"]), col, t.tile("canvas", gain=1.15))              # linen
    # v3: the face's own paint (costume.face_masks): a flush, the lips, the brows, a trimmed
    # beard and moustache as stippled short hair
    face_flush = t.attr("face", "Alpha")
    col = t.mix(face_flush, col, t.mul(col, t.rgb((1.04, 0.86, 0.84))))
    col = t.mix(t.sharp(t.attr("face", "Blue"), 0.3, 0.7), col, t.rgb(lin("A8645A")))
    stub = t.mix(t.noise(420.0, 4.0), t.rgb(lin("3A2214")), t.rgb(lin("6E4830")))
    bw = t.n("ShaderNodeMath", operation="MULTIPLY")
    t.L(t.sharp(t.attr("face", "Red"), 0.25, 0.6), bw.inputs[0])
    t.L(t.sharp(t.noise(260.0, 2.0), 0.3, 0.55), bw.inputs[1])
    beardmask = t.n("ShaderNodeMath", operation="MAXIMUM")
    t.L(bw.outputs[0], beardmask.inputs[0])
    t.L(t.sharp(t.attr("face", "Red"), 0.6, 0.85), beardmask.inputs[1])
    col = t.mix(beardmask.outputs[0], col, stub)
    col = t.mix(t.sharp(t.attr("face", "Green"), 0.3, 0.7), col, t.rgb(lin("3A2416")))
    hair = t.mix(t.noise(90.0, 8.0), t.rgb(lin("3E2616")), t.rgb(lin("6A4428")))
    col = t.mix(t.sharp(t.attr("rgn_b", "Red")), col, hair)
    col = t.mix(t.sharp(t.attr("rgn_b", "Green"), 0.3, 0.7), col, t.mul(hair, t.rgb((0.9, 0.9, 0.9))))
    col = t.mix(t.sharp(t.attr("rgn_b", "Blue")), col, t.rgb(lin("EDE8E0")))
    b = t.n("ShaderNodeAttribute")
    b.attribute_name = "rgn_b"
    col = t.mix(t.sharp(b.outputs["Alpha"]), col, t.rgb(lin("2A1C12")))
    t.emit(col)


def horse_marks(horse, head):
    """Object-space marks on the scan, as a colour attribute: R the dark points (knees and
    cannons), G the hooves, B mane and tail, A the grey muzzle and eyes."""
    me = horse.data
    co = np.array([v.co[:] for v in me.vertices])
    # the top of the body along y (for the mane's crest and the tail's root)
    ys = np.round(co[:, 1], 2)
    top = {}
    mid = np.abs(co[:, 0]) < 0.06
    for y, z in zip(ys[mid], co[mid, 2]):
        top[y] = max(top.get(y, -1), z)
    tops = np.array([top.get(y, -1) for y in ys])
    rear = co[:, 1].min()
    poll = head["poll"]
    nose = head["nose"]
    z = co[:, 2]
    points = np.clip((0.56 - z) / 0.16, 0, 1) * (1 - np.clip((0.2 - z) / 0.06, 0, 1) * 0.55)
    hoof = (z < 0.075).astype(float)
    mane = ((co[:, 1] > 0.55) & (co[:, 1] < poll[1] - 0.05) & (np.abs(co[:, 0] - 0.0) < 0.11)
            & (z > tops - 0.09)).astype(float)
    tail = ((co[:, 1] < rear + 0.2) & (z < tops - 0.05) & (z > 0.3)).astype(float)
    dm = np.linalg.norm(co - nose, axis=1)
    muzzle = np.clip((0.16 - dm) / 0.08, 0, 1)
    # v3: the eyeball is geometry now (build_v3.horse_eyes); the paint only greys a small
    # socket round it, at the same EYE_AT the eyeball uses (the v2 estimate from the old head
    # frame left a dark blob behind the eye).
    import build_v3
    ey, ez = build_v3.EYE_AT
    eye = np.zeros(len(co))
    for s in (1, -1):
        cand = co[(np.abs(co[:, 1] - ey) < 0.03) & (np.abs(co[:, 2] - ez) < 0.03) & (co[:, 0] * s > 0)]
        if len(cand):
            e = cand[np.argmax(cand[:, 0] * s)]
            eye = np.maximum(eye, 0.6 * np.clip((0.034 - np.linalg.norm(co - e, axis=1)) / 0.014, 0, 1))
    A = np.maximum(muzzle * 0.8, eye)
    at = me.color_attributes.new("marks", "FLOAT_COLOR", "POINT")
    at.data.foreach_set("color", np.stack([points, hoof, np.maximum(mane, tail), A], 1).ravel())


def paint_horse(mat):
    """v3: a finer dapple, as the pick's - small grey rings round pale spots (a fine
    voronoi), a speckle over it, both denser over the hindquarters and belly and toward the
    legs; the dark points, hooves, grey muzzle and the cream mane and tail as before."""
    t = NT(mat)
    tc = t.n("ShaderNodeTexCoord")
    vor = t.n("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 24.0          # v3: finer, denser (17 read as polka dots)
    vor.inputs["Randomness"].default_value = 0.85
    t.L(tc.outputs["Object"], vor.inputs["Vector"])
    ramp = t.n("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.32
    ramp.color_ramp.elements[0].color = (*lin("F2F2F0"), 1)
    ramp.color_ramp.elements[1].position = 0.62
    ramp.color_ramp.elements[1].color = (*lin("AEB1B5"), 1)
    t.L(vor.outputs["Distance"], ramp.inputs["Fac"])
    # where the dapple is strong: the hindquarters, the barrel's lower half, the legs
    tcs = t.n("ShaderNodeSeparateXYZ")
    t.L(tc.outputs["Object"], tcs.inputs["Vector"])
    rear = t.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
    rear.inputs["From Min"].default_value = 0.6
    rear.inputs["From Max"].default_value = -0.5
    t.L(tcs.outputs["Y"], rear.inputs["Value"])
    low = t.zramp(1.45, 0.9)
    amt = t.n("ShaderNodeMath", operation="MAXIMUM")
    t.L(rear.outputs["Result"], amt.inputs[0])
    t.L(low, amt.inputs[1])
    amt2 = t.n("ShaderNodeMapRange")
    amt2.inputs["To Min"].default_value = 0.12
    amt2.inputs["To Max"].default_value = 0.6
    t.L(amt.outputs[0], amt2.inputs["Value"])
    dap = t.mix(amt2.outputs["Result"], t.rgb(lin("F0F0EE")), ramp.outputs["Color"])
    speck = t.sharp(t.noise(110.0, 3.0), 0.55, 0.7)
    dap = t.mix(speck, dap, t.mul(dap, t.rgb((0.86, 0.86, 0.88))))
    hair = t.mix(0.78, t.tile("coat", gain=1.02), t.rgb((1.0, 1.0, 1.0)))
    coat = t.mul(dap, hair)
    points = t.mix(t.noise(14.0), t.rgb(lin("55585C")), t.rgb(lin("7E8185")))
    points = t.mix(t.sharp(t.noise(60.0), 0.45, 0.6), points, t.rgb(lin("A2A5A8")))       # mottled
    col = t.mix(t.attr("marks", "Red"), coat, points)
    col = t.mix(t.attr("marks", "Alpha"), col, t.rgb(lin("46464A")))
    mane = t.mix(t.noise(70.0, 8.0), t.rgb(lin("D6D0C4")), t.rgb(lin("F2EEE6")))
    col = t.mix(t.attr("marks", "Blue"), col, mane)
    col = t.mix(t.attr("marks", "Green"), col, t.rgb(lin("2E2A28")))
    col = t.dirt(col, 0.02, 0.32, 0.45, "6A5A48")
    t.emit(col)


# ---------------------------------------------------------------- reduce, unwrap
def activate(ob):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def reduce(high, name, tris):
    low = high.copy()
    low.data = high.data.copy()
    low.name = low.data.name = name
    bpy.context.scene.collection.objects.link(low)
    for layer in list(low.data.uv_layers):
        low.data.uv_layers.remove(layer)
    for a in list(low.data.color_attributes):
        low.data.color_attributes.remove(a)
    cur = sum(len(p.vertices) - 2 for p in low.data.polygons)
    d = low.modifiers.new("decimate", "DECIMATE")
    d.ratio = min(1.0, tris / max(1, cur))
    activate(low)
    bpy.ops.object.modifier_apply(modifier=d.name)
    return low


def unwrap_all(objs, weights):
    """Smart-project each part, scale its islands by its weight (texel density), then pack
    every part together into the one atlas."""
    for ob in objs:
        activate(ob)
        if not ob.data.uv_layers:
            ob.data.uv_layers.new(name="UVMap")
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002, scale_to_bounds=False)
        bpy.ops.object.mode_set(mode="OBJECT")
        # smart project normalises per object: bring islands back to real metres, weighted
        me = ob.data
        uv = np.zeros(len(me.loops) * 2)
        me.uv_layers.active.data.foreach_get("uv", uv)
        uv = uv.reshape(-1, 2)
        area3 = sum(p.area for p in me.polygons)
        a2 = 0.0
        for p in me.polygons:
            idx = list(p.loop_indices)
            q = uv[idx]
            a2 += 0.5 * abs(np.dot(q[:, 0], np.roll(q[:, 1], 1)) - np.dot(q[:, 1], np.roll(q[:, 0], 1)))
        s = math.sqrt(area3 / max(a2, 1e-9)) * weights.get(ob.name, 1.0)
        me.uv_layers.active.data.foreach_set("uv", (uv * s).ravel())
    # everything into the one 0..1 tile first (islands in metres spill into other UDIM
    # tiles, and the pack keeps each island in its closest tile: they overlapped the horse)
    mx = 0.0
    for ob in objs:
        uv = np.zeros(len(ob.data.loops) * 2)
        ob.data.uv_layers.active.data.foreach_get("uv", uv)
        mx = max(mx, np.abs(uv).max())
    for ob in objs:
        uv = np.zeros(len(ob.data.loops) * 2)
        ob.data.uv_layers.active.data.foreach_get("uv", uv)
        ob.data.uv_layers.active.data.foreach_set("uv", uv / (mx * 1.01))
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    try:
        bpy.ops.uv.pack_islands(udim_source="ACTIVE_UDIM", rotate=True, margin=0.004)
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------- bakes
def new_image(name, colour, fill):
    img = bpy.data.images.get(name)
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    img.generated_color = fill
    return img


def target_node(mat, image):
    nt = mat.node_tree
    key = "bake_" + image.name
    node = nt.nodes.get(key)
    if node is None:
        node = nt.nodes.new("ShaderNodeTexImage")
        node.name = key
        node.image = image
    for n in nt.nodes:
        n.select = False
    node.select = True
    nt.nodes.active = node


def bake(low, image, kind, high=None):
    sc = bpy.context.scene
    for m in low.data.materials:
        target_node(m, image)
    activate(low)
    b = sc.render.bake
    b.use_selected_to_active = high is not None
    if high is not None:
        high.select_set(True)
        bpy.context.view_layer.objects.active = low
        b.cage_extrusion = 0.03
        b.max_ray_distance = 0.08
    b.margin = MARGIN
    b.use_clear = False
    b.target = "IMAGE_TEXTURES"
    if kind == "NORMAL":
        b.normal_space = "TANGENT"
    bpy.ops.object.bake(type=kind)


def atlas_material(col, nor, mr):
    mat = bpy.data.materials.new("courier_atlas")
    mat.use_nodes = True
    mat.use_backface_culling = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tc = nt.nodes.new("ShaderNodeTexImage"); tc.image = col
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = nor
    nm = nt.nodes.new("ShaderNodeNormalMap")
    tm = nt.nodes.new("ShaderNodeTexImage"); tm.image = mr
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(tm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    return mat


def split_copy(high, name, keep):
    """A copy of `high` keeping only the faces keep(centre) says yes to."""
    import bmesh
    ob = high.copy()
    ob.data = high.data.copy()
    ob.name = ob.data.name = name
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    gone = [f for f in bm.faces if not keep(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    return ob


PART_ORDER = []          # the joined parts' names, by the `part_id` attribute


def run(objs, head, out_dir, PJ):
    sc = bpy.context.scene
    horse_high, rider_high = objs["horse_high"], objs["rider_high"]
    horse_low = objs.get("horse_low") or reduce(horse_high, "horse", BUDGET["horse"])
    # v3: the rider's head gets its own reduction and its own share of the atlas; both halves
    # bake from the one Multires body. The cut runs under the collar.
    cut_z = PJ["neck:h"].z + 0.004
    hc = PJ["head:h"] * 0.5 + PJ["head:t"] * 0.5
    is_head = lambda c: c.z > cut_z and (c - hc).length < 0.22
    head_src = split_copy(rider_high, "rider_head_src", is_head)
    body_src = split_copy(rider_high, "rider_body_src", lambda c: not is_head(c))
    rider_head = reduce(head_src, "rider_head", BUDGET["rider_head"])
    rider_low = reduce(body_src, "rider", BUDGET["rider"])
    for o in (head_src, body_src):
        bpy.data.objects.remove(o, do_unlink=True)
    boots = objs["rider_boots"]
    d = boots.modifiers.new("decimate", "DECIMATE")
    d.ratio = BUDGET["boots"] / max(1, sum(len(p.vertices) - 2 for p in boots.data.polygons))
    activate(boots)
    bpy.ops.object.modifier_apply(modifier=d.name)
    boots.data.materials.clear()
    boots.data.materials.append(bpy.data.materials.get("boot") or bpy.data.materials.new("boot"))
    hands, hands_high = objs["rider_hands"], objs["rider_hands_high"]
    parts = [horse_low, rider_low, rider_head, hands, boots] + [objs[k] for k in (
        "tack", "bridle", "clothes", "clothes_trim", "props", "props_crowns", "horse_hair", "horse_eyes", "boot_bands")]
    for p in parts:
        activate(p)
        bpy.ops.object.shade_smooth()
        PART_TRIS[p.name] = sum(len(q.vertices) - 2 for q in p.data.polygons)
    weights = {"rider": 1.6, "rider_head": 3.4, "rider_hands": 2.4, "rider_boots": 1.3, "props": 1.3,
               "clothes": 1.4, "clothes_trim": 1.6, "props_crowns": 1.6, "horse": 1.0, "tack": 1.15,
               "bridle": 1.3, "horse_hair": 1.0, "horse_eyes": 2.5, "boot_bands": 1.3}
    unwrap_all(parts, weights)

    # the paint
    horse_marks(horse_high, head)
    hm = bpy.data.materials.new("paint_horse"); paint_horse(hm)
    horse_high.data.materials.clear(); horse_high.data.materials.append(hm)
    rm = bpy.data.materials.new("paint_rider"); paint_rider(rm)
    rider_high.data.materials.clear(); rider_high.data.materials.append(rm)
    sm = bpy.data.materials.new("skin_high"); paint_tag(bpy.data.materials.new("skin"))
    hands_high.data.materials.clear(); hands_high.data.materials.append(bpy.data.materials["skin"])
    scanned = {horse_low: horse_high, rider_low: rider_high, rider_head: rider_high, hands: hands_high}
    for low in scanned:
        m = bpy.data.materials.new("target_" + low.name)
        m.use_nodes = True
        low.data.materials.clear(); low.data.materials.append(m)
    tagged = [p for p in parts if p not in scanned]
    tag_mats = sorted({m for p in tagged for m in p.data.materials if m}, key=lambda m: m.name)
    for m in tag_mats:
        paint_tag(m)

    col = new_image("courier_atlas", True, (0.5, 0.5, 0.5, 1))
    nor = new_image("courier_atlas_n", False, (0.5, 0.5, 1.0, 1))
    mr = new_image("courier_atlas_mr", False, (1.0, 0.85, 0.0, 1))
    ao = new_image("courier_atlas_ao", False, (1.0, 1.0, 1.0, 1))
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 1
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for dv in prefs.devices:
            dv.use = True
        sc.cycles.device = "GPU"
    except Exception as ex:
        print("GPU not set:", ex)
    for low, high in scanned.items():
        bake(low, col, "EMIT", high)
    for p in tagged:
        bake(p, col, "EMIT")
    for low, high in scanned.items():
        bake(low, nor, "NORMAL", high)
    for m in tag_mats:
        paint_mr(m)
    for p in tagged:
        bake(p, mr, "EMIT")
    for high in (horse_high, rider_high, hands_high):
        high.hide_render = True
    sc.cycles.samples = 48
    sc.world = sc.world or bpy.data.worlds.new("w")
    for p in parts:
        # v3b: the reins and the pole run THROUGH the closed fists; left in, they darkened
        # the rein hand to a brown blob. The fists' AO sees only the rider and the horse.
        grip = [o for o in bpy.data.objects if o.name in ("bridle", "props", "props_crowns")] \
            if p is hands else []
        for o in grip:
            o.hide_render = True
        bake(p, ao, "AO")
        for o in grip:
            o.hide_render = False
    # v3: the AO kept light - only the creases and the undersides go darker
    c = np.array(col.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    a_ = np.array(ao.pixels[:], np.float32).reshape(ATLAS, ATLAS, 4)
    occl = 0.62 + 0.38 * np.clip(a_[..., :1] * 1.1, 0, 1)
    c[..., :3] *= occl
    col.pixels.foreach_set(c.ravel())
    for img in (col, nor, mr, ao):
        img.filepath_raw = os.path.join(out_dir, img.name + ".png")
        img.file_format = "PNG"
        img.save()
    mat = atlas_material(col, nor, mr)
    for p in parts:
        p.data.materials.clear()
        p.data.materials.append(mat)
    # which part each vertex came from (the rig weights each part its own way); the
    # rig drops the attribute before export
    PART_ORDER[:] = [p.name for p in parts]
    for i, p in enumerate(parts):
        at = p.data.attributes.new("part_id", "INT", "POINT")
        at.data.foreach_set("value", [i] * len(p.data.vertices))
    activate(parts[0])
    for p in parts[1:]:
        p.select_set(True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = "courier"
    for poly in ob.data.polygons:
        poly.material_index = 0
    for a2 in [a2 for a2 in ob.data.attributes if a2.name in ("rgn_a", "rgn_b", "part_code", "marks", "face")]:
        ob.data.attributes.remove(a2)
    return ob, None
