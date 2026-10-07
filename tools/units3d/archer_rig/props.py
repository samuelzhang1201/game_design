"""The bowstring and the nocked arrow, built new (Phase 1c deleted Tripo's string: welded to the
bow, it could not be drawn) and joined into `archer`, textured from spots of its own atlas:

  string -- two 6-sided strands, bottom tip -> nock -> top tip, the grip's dark leather;
            each strand graded from its limb's tip (BowLimb.U / .D, 1 at the tip) to the nock
            (String, 1 at the nock), so it stays on the tips as the limbs bend and runs straight
            to wherever String is drawn;
  arrow  -- a 76 cm shaft (the bow's wood) on Arrow, three grey goose vanes (the quiver's
            fletching), a steel bodkin (the helmet's steel); rigid on Arrow, hidden by scaling
            Arrow to 0 whenever no arrow is on the string.
"""
STRING_R = 0.0025
SHAFT_R = 0.004
SIDES = 6


def uv_at(pick):
    """The UV (and colour) of the vertex the predicate `pick(P, lab)` -> index chooses."""
    o = mesh()
    P = co(o); lab = roles()
    i = pick(P, lab)
    uv = o.data.uv_layers.active.data
    for loop in o.data.loops:
        if loop.vertex_index == i:
            return tuple(uv[loop.index].uv)
    raise ValueError("no loop for vertex %d" % i)


def spots():
    a = rig().data.bones
    gl, gh = a["BowLimb.D"].head_local, a["BowLimb.U"].head_local
    bow, quiver, head = ROLES.index("bow"), ROLES.index("quiver"), ROLES.index("head")

    def grip(P, lab):          # the leather wrap: a bow vertex at the grip's middle
        k = np.nonzero(lab == bow)[0]
        mid = (np.array(gl) + np.array(gh)) / 2
        return k[np.argmin(np.linalg.norm(P[k] - mid, axis=1))]

    def wood(P, lab):          # a limb halfway up
        k = np.nonzero(lab == bow)[0]
        z = gh.z + 0.4
        return k[np.argmin(np.abs(P[k, 2] - z) + 0.5 * np.abs(P[k, 0] - P[k, 0].mean()))]

    def feather(P, lab):       # the highest quiver vertex: a fletching
        k = np.nonzero(lab == quiver)[0]
        return k[np.argmax(P[k, 2])]

    def steel(P, lab):         # the helmet's crown
        k = np.nonzero(lab == head)[0]
        return k[np.argmax(P[k, 2])]
    return {"grip": uv_at(grip), "wood": uv_at(wood), "feather": uv_at(feather), "steel": uv_at(steel)}


def _frame(d):
    d = d.normalized()
    u = d.orthogonal().normalized()
    return u, d.cross(u).normalized()


def tube(bm, a, b, r, uvl, uv, sides=SIDES, rings=6):
    """A capped tube a -> b; returns [(vert, t)] with t 0 at a, 1 at b."""
    a, b = Vector(a), Vector(b)
    u, w = _frame(b - a)
    out, rows = [], []
    for k in range(rings + 1):
        t = k / rings
        c = a.lerp(b, t)
        row = [bm.verts.new(c + (u * math.cos(2 * math.pi * s / sides) + w * math.sin(2 * math.pi * s / sides)) * r)
               for s in range(sides)]
        rows.append(row)
        out += [(v, t) for v in row]
    for k in range(rings):
        for s in range(sides):
            bm.faces.new((rows[k][s], rows[k][(s + 1) % sides], rows[k + 1][(s + 1) % sides], rows[k + 1][s]))
    for row, rev in ((rows[0], True), (rows[-1], False)):
        bm.faces.new(list(reversed(row)) if rev else row)
    for f in bm.faces:
        for l in f.loops:
            if l[uvl] is not None and tuple(l[uvl].uv) == (0.0, 0.0):
                l[uvl].uv = uv
    return out


def build():
    """Two objects, archer_string and archer_arrow, weighted and joined into `archer`."""
    import bmesh as bmm
    sp = spots()
    a = rig().data.bones
    top, bot = a["BowLimb.U"].tail_local, a["BowLimb.D"].tail_local
    cx, cy = eval(open(SRC + "string_fit.txt").read())
    sline = lambda z: Vector((cx[0] * z + cx[1], cy[0] * z + cy[1], z))
    s_top, s_bot = sline(top.z), sline(bot.z)
    nock = a["String"].head_local
    made = []
    for name in ("archer_string", "archer_arrow"):
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
    # --- string
    me = bpy.data.meshes.new("archer_string")
    bm = bmm.new(); uvl = bm.loops.layers.uv.new(mesh().data.uv_layers.active.name)
    wts = []
    for end, limb in ((s_top, "BowLimb.U"), (s_bot, "BowLimb.D")):
        for v, t in tube(bm, end, nock, STRING_R, uvl, sp["grip"]):
            wts.append((v, {limb: 1 - t, "String": t}))
    bm.verts.index_update()
    W = [(v.index, w) for v, w in wts]
    bm.to_mesh(me); bm.free()
    so = bpy.data.objects.new("archer_string", me)
    coll("Archer_Rig").objects.link(so)
    for i, w in W:
        for g, x in w.items():
            if x > 0.0:
                (so.vertex_groups.get(g) or so.vertex_groups.new(name=g)).add([i], x, "REPLACE")
    made.append(so)
    # --- arrow, along the Arrow bone (head = nock, tail = point)
    ab = a["Arrow"]
    h, t_ = ab.head_local, ab.tail_local
    d = (t_ - h).normalized()
    me = bpy.data.meshes.new("archer_arrow")
    bm = bmm.new(); uvl = bm.loops.layers.uv.new(mesh().data.uv_layers.active.name)
    tube(bm, h, t_ - d * 0.04, SHAFT_R, uvl, sp["wood"], rings=2)
    n = len(bm.faces)
    # bodkin: a four-sided spike
    u, w = _frame(d)
    base = t_ - d * 0.045
    ring = [bm.verts.new(base + (u * math.cos(k * math.pi / 2) + w * math.sin(k * math.pi / 2)) * 0.007) for k in range(4)]
    tip = bm.verts.new(t_)
    for k in range(4):
        bm.faces.new((ring[k], ring[(k + 1) % 4], tip))
    bm.faces.new(list(reversed(ring)))
    for f in list(bm.faces)[n:]:
        for l in f.loops:
            l[uvl].uv = sp["steel"]
    n = len(bm.faces)
    # three vanes, 12 cm long from 2 cm before the nock
    for k in range(3):
        ang = 2 * math.pi * k / 3
        out = (u * math.cos(ang) + w * math.sin(ang))
        p0 = h + d * 0.025
        p1 = h + d * 0.145
        pts = [p0 + out * SHAFT_R, p1 + out * SHAFT_R, p1 - d * 0.02 + out * 0.016, p0 + d * 0.01 + out * 0.018]
        bm.faces.new([bm.verts.new(x) for x in pts])
        bm.faces.new([bm.verts.new(x) for x in reversed(pts)])      # two-sided: its own verts
    for f in list(bm.faces)[n:]:
        for l in f.loops:
            l[uvl].uv = sp["feather"]
    bm.to_mesh(me); bm.free()
    ao = bpy.data.objects.new("archer_arrow", me)
    coll("Archer_Rig").objects.link(ao)
    ao.vertex_groups.new(name="Arrow").add(list(range(len(me.vertices))), 1.0, "REPLACE")
    made.append(ao)
    # join both into the archer (same material, same UV map, groups merge by name)
    o = mesh()
    for m in made:
        m.data.materials.append(o.data.materials[0])
    for x in bpy.context.view_layer.objects:
        x.select_set(False)
    for m in made:
        m.select_set(True)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    nv = len(o.data.vertices)
    bpy.ops.object.join()
    # the role attribute: the new vertices are bow (the string) or a role of their own? keep "bow"
    lab = o.data.attributes["role"]
    vals = np.empty(len(o.data.vertices), int)
    lab.data.foreach_get("value", vals)
    vals[nv:] = ROLES.index("bow")
    lab.data.foreach_set("value", vals)
    return {"spots": sp, "added_verts": len(o.data.vertices) - nv, "tris": tris(o)}


def rest_arrow_along_string():
    """Migration for a rig built before armature.py laid the Arrow's rest along the string: the bone
    moved there and the arrow's vertices (all on Arrow) moved with it, so every pose is unchanged."""
    a, o = rig(), mesh()
    B = a.data.bones
    old = B["Arrow"].matrix_local.copy()
    lm_top, lm_bot = B["BowLimb.U"].tail_local, B["BowLimb.D"].tail_local
    cx, cy = eval(open(SRC + "string_fit.txt").read())
    sline = lambda z: Vector((cx[0] * z + cx[1], cy[0] * z + cy[1], z))
    chord = (sline(lm_top.z) - sline(lm_bot.z)).normalized()
    nock = B["String"].head_local.copy()
    a0 = nock - chord * 0.40
    activate(a)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = a.data.edit_bones["Arrow"]
    eb.head = a0; eb.tail = a0 + chord * 0.76
    eb.align_roll(Vector((0, -1, 0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    new = a.data.bones["Arrow"].matrix_local.copy()
    T = new @ old.inverted()
    g = o.vertex_groups["Arrow"].index
    moved = 0
    for v in o.data.vertices:
        if any(x.group == g and x.weight > 0.99 for x in v.groups):
            v.co = T @ v.co; moved += 1
    o.data.update()
    return {"moved": moved, "head": [round(x, 3) for x in a0], "tail": [round(x, 3) for x in a0 + chord * 0.76]}


def cut_cuff_scraps():
    """Delete what Tripo welded to the right fist where it hung by the scabbard and the buckler
    (owner 2026-10-07: 右手袖口多出来一块): a ragged leather flap labelled arm_r, found as the arm
    island's vertices that, at MARCH f0 (the arm forward), hang under the wrist (0-14 cm ahead of
    the hand's middle, 0.4-7 cm below it), and the skin-coloured shards left on the coat (islands
    of < 30 vertices labelled lower within 12 cm of the rest hand). Run once on the rigged mesh."""
    import bmesh as bmm
    o, a = mesh(), rig()
    P = co(o); lab = roles()
    hr = a.data.bones["Hand.R"]
    c = np.array((hr.head_local + hr.tail_local) / 2)
    bm = bmm.new(); bm.from_mesh(o.data); bm.verts.ensure_lookup_table()
    seen = np.full(len(bm.verts), -1); comps = []
    for v0 in bm.verts:
        if seen[v0.index] >= 0:
            continue
        stack = [v0]; seen[v0.index] = len(comps); mem = []
        while stack:
            v = stack.pop(); mem.append(v.index)
            for e in v.link_edges:
                w = e.other_vert(v)
                if seen[w.index] < 0:
                    seen[w.index] = len(comps); stack.append(w)
        comps.append(mem)
    arm = ROLES.index("arm_r"); lower = ROLES.index("lower")
    arm_isl = max((m for m in comps if lab[m[0]] == arm), key=len)
    shards = [i for m in comps if len(m) < 30 and all(lab[j] == lower for j in m)
              and np.linalg.norm(P[m] - c, axis=1).min() < 0.12 for i in m]
    # the flap: pose MARCH f0 and pick by place
    R = Rest(); calibrate(); ch, N = march(R)
    PREV_W.clear()
    for f in range(N):
        apply_pose(ch, float(f), R)
    apply_pose(ch, 0.0, R)
    hand = a.pose.bones["Hand.R"]; hc = np.array((hand.head + hand.tail) / 2)
    dg = bpy.context.evaluated_depsgraph_get(); me = o.evaluated_get(dg).to_mesh()
    Q = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", Q); Q = Q.reshape(-1, 3)
    o.evaluated_get(dg).to_mesh_clear()
    reset()
    idx = np.array(arm_isl); rel = Q[idx] - hc
    flap = idx[(-rel[:, 1] > 0) & (-rel[:, 1] < 0.14) & (rel[:, 2] < -0.004) & (rel[:, 2] > -0.07)].tolist()
    gone = sorted(set(flap) | set(shards))
    bmm.ops.delete(bm, geom=[bm.verts[i] for i in gone], context="VERTS")
    bm.to_mesh(o.data); bm.free(); o.data.update()
    return {"flap": len(flap), "shards": len(shards), "verts": len(o.data.vertices), "tris": tris(o)}
