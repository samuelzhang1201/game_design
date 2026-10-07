"""Phase A: the Tripo delivery made the working rig -- one armature `archer_rig`, one mesh `archer`,
helmet crown at HEIGHT, facing -Y (left +X, as it came), each limb bone's tail put on the next
joint (the glTF import guesses tails: a thigh stopped short of its knee), Tripo's own clips dropped
(the clips are actions.py's). The skin is Tripo's, untouched."""
BODY_TRIS = 17000        # the body's budget (the props add ~4.6k): v1 was 18.7k in all
CHAINS = [("thigh_l", "calf_l"), ("calf_l", "foot_l"), ("foot_l", "ball_l"),
          ("thigh_r", "calf_r"), ("calf_r", "foot_r"), ("foot_r", "ball_r"),
          ("upperarm_l", "lowerarm_l"), ("lowerarm_l", "hand_l"),
          ("upperarm_r", "lowerarm_r"), ("lowerarm_r", "hand_r"),
          ("clavicle_l", "upperarm_l"), ("clavicle_r", "upperarm_r"),
          ("pelvis", "spine_01"), ("spine_01", "spine_02"), ("spine_02", "spine_03"), ("spine_03", "neck_01"),
          ("neck_01", "head")]


def import_tripo():
    sc = scene()
    for s in list(bpy.data.scenes):
        if s != sc:
            bpy.data.scenes.remove(s)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for a_ in list(bpy.data.actions):
        bpy.data.actions.remove(a_)
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=TRIPO_FILE)
    new = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in new if o.type == "ARMATURE"][0]
    me = [o for o in new if o.type == "MESH" and o.parent == arm][0]
    for o in new:
        if o not in (arm, me):
            bpy.data.objects.remove(o, do_unlink=True)
    arm.name = arm.data.name = RIG
    me.name = me.data.name = MESH
    c = coll("Archer_Tripo")
    for o in (arm, me):
        for uc in list(o.users_collection):
            uc.objects.unlink(o)
        c.objects.link(o)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    if arm.animation_data:
        arm.animation_data_clear()
    for pb in arm.pose.bones:                  # the import leaves the bones posed on a clip's frame
        pb.matrix_basis = Matrix.Identity(4)
    # scale: the crown at HEIGHT
    bpy.context.view_layer.update()
    zt = max((me.matrix_world @ v.co).z for v in me.data.vertices)
    zb = min((me.matrix_world @ v.co).z for v in me.data.vertices)
    s = HEIGHT / (zt - zb)
    me.parent = None
    me.matrix_world = Matrix.Scale(s, 4) @ me.matrix_world
    arm.matrix_world = Matrix.Scale(s, 4) @ arm.matrix_world
    for o in (me, arm):
        activate(o)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    me.parent = arm
    me.matrix_parent_inverse = arm.matrix_world.inverted()
    # to the game's budget: a collapse (the weights interpolate; the normal map keeps the detail)
    t0 = tris(me)
    dec = me.modifiers.new("budget", "DECIMATE")
    dec.decimate_type = "COLLAPSE"; dec.ratio = BODY_TRIS / t0; dec.use_collapse_triangulate = True
    me.modifiers.move(me.modifiers.find(dec.name), 0)       # before the armature
    activate(me)
    bpy.ops.object.modifier_apply(modifier=dec.name)
    # tails onto the next joint
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for a_, b_ in CHAINS:
        eb[a_].use_connect = False
        eb[a_].tail = eb[b_].head.copy()
    for side in "lr":                          # the toe and the hand: on along their own line
        ball = eb["ball_" + side]                # the toe: level, forward (the import's points into the ground)
        d = ball.tail - ball.head
        ball.tail = ball.head + Vector((d.x, d.y, 0)).normalized() * 0.09
        hand = eb["hand_" + side]
        hand.tail = (eb["middle_01_" + side].head + eb["index_01_" + side].head) / 2
    bpy.ops.object.mode_set(mode="OBJECT")
    return {"scale": round(s, 4), "bones": len(arm.data.bones), "verts": len(me.data.vertices), "tris_from": t0, "tris": tris(me)}


# ---------------------------------------------------------------- fingers ----
PALM = Vector((0, 0, -1))          # the T-pose's palms face down (thumbs forward, -Y)
FIST = {"thumb": (0, 0, 80), "index": (70, 95, 60), "middle": (75, 98, 60), "ring": (78, 98, 60), "pinky": (80, 95, 60)}
THUMB = (15.0, -50.0)              # the thumb's base (down the fist's front, across it): fitted so its tip rests on the index's middle joint


def finger_axis(arm, side, finger):
    """The world axis a finger curls about in the T-pose: + brings its tip toward the palm."""
    B = arm.data.bones
    d = (B["%s_03_%s" % (finger, side)].tail_local - B["%s_01_%s" % (finger, side)].head_local).normalized()
    return d.cross(PALM).normalized()


def store_local_axes(arm):
    """Before the rest pose leaves the T-pose (rebind_rest), each finger bone's curl axis and the
    thumb's turn axes are kept in the bones' own frames (custom properties): local axes go with the
    bone wherever its rest goes."""
    B = arm.data.bones
    for side in "lr":
        hand_ax = (B["hand_" + side].tail_local - B["hand_" + side].head_local).normalized()
        for f in FINGERS:
            ax = finger_axis(arm, side, "index" if f == "thumb" else f)
            for k in ("01", "02", "03"):
                b = B["%s_%s_%s" % (f, k, side)]
                Ri = b.matrix_local.to_3x3().inverted()
                b["curl"] = tuple((Ri @ ax).normalized())
                if f == "thumb" and k == "01":
                    b["turn_down"] = tuple((Ri @ hand_ax).normalized())
                    b["turn_across"] = tuple((Ri @ PALM).normalized())


def pose_fingers(arm, side, curls, thumb=None):
    """Curl each finger's three bones by curls[finger] = (deg, deg, deg) about its curl axis, in
    each bone's own frame (the chain's rotations compose down it). The thumb: its base turned down
    the front of the fist (thumb = (down deg, across deg)) and its two joints curled the fingers'
    way, so it lies across them."""
    B = arm.data.bones
    sgn = 1 if side == "l" else -1
    for f in FINGERS:
        for k, ang in zip(("01", "02", "03"), curls.get(f, (0, 0, 0))):
            b = "%s_%s_%s" % (f, k, side)
            if "curl" in B[b]:
                ax_l = Vector(B[b]["curl"])
            else:
                ax_l = (B[b].matrix_local.to_3x3().inverted() @ finger_axis(arm, side, "index" if f == "thumb" else f)).normalized()
            q = Quaternion(ax_l, math.radians(ang))
            if f == "thumb" and k == "01":
                down, across = thumb if thumb is not None else THUMB
                Ri = B[b].matrix_local.to_3x3().inverted()
                hd = Vector(B[b]["turn_down"]) if "turn_down" in B[b] else (Ri @ (B["hand_" + side].tail_local - B["hand_" + side].head_local)).normalized()
                pa = Vector(B[b]["turn_across"]) if "turn_across" in B[b] else (Ri @ PALM).normalized()
                q = Quaternion(hd, math.radians(sgn * -down)) @ Quaternion(pa, math.radians(sgn * across))
            pb = arm.pose.bones[b]
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q
    bpy.context.view_layer.update()


def fist_centre(arm, side):
    """The hole the curled fist leaves: the middle of the index-to-pinky fingers' rings (world)."""
    pts = []
    for f in ("index", "middle", "ring", "pinky"):
        for k in ("01", "02", "03"):
            pb = arm.pose.bones["%s_%s_%s" % (f, k, side)]
            pts.append(arm.matrix_world @ pb.head)
        pts.append(arm.matrix_world @ arm.pose.bones["%s_03_%s" % (f, side)].tail)
    return sum(pts, Vector()) / len(pts)


# ---------------------------------------------------------------- props ----
GRIP_HALF = 0.06        # the grip's half length along the bow (the fist's width): rigid on Bow
STRING_R, SHAFT_R, SIDES = 0.0025, 0.004, 6
PARTS = ("body", "bow", "string", "arrow", "quiver")


def _v1():
    j = json.load(open(PROPS_INFO))
    V = lambda b, k="head": Vector(j[b][k])
    grip = (V("Bow") + V("Bow", "tail")) / 2
    top, bot = V("BowLimb.U", "tail"), V("BowLimb.D", "tail")
    chord = (top - bot).normalized()
    nock = V("String")
    v = nock - grip
    draw = (v - chord * v.dot(chord)).normalized()
    cx, cy = eval(j["string_fit"])
    sline = lambda z: Vector((cx[0] * z + cx[1], cy[0] * z + cy[1], z))
    return dict(grip=grip, chord=chord, draw=draw, top=top, bot=bot, nock=nock,
                s_top=sline(top.z), s_bot=sline(bot.z), chest=V("Chest"), quiver=(V("Quiver"), V("Quiver", "tail")))


def frame(chord, draw):
    c = chord.normalized(); d = (draw - c * draw.dot(c)).normalized()
    return Matrix((d, c, d.cross(c))).transposed()


def bow_transform(arm):
    """The v1 bow's rest -> this rig's: its grip in the fisted left hand's hole, its chord along the
    knuckles (the upper tip on the thumb's side, as in v1), the string toward the forearm."""
    o = _v1()
    pose_fingers(arm, "l", FIST)
    g = fist_centre(arm, "l")
    pb = arm.pose.bones
    chord = (pb["index_01_l"].head - pb["pinky_01_l"].head).normalized()
    fore = (arm.data.bones["hand_l"].head_local - arm.data.bones["lowerarm_l"].head_local).normalized()
    R = frame(chord, -fore) @ frame(o["chord"], o["draw"]).transposed()
    T = Matrix.Translation(g) @ R.to_4x4() @ Matrix.Translation(-o["grip"])
    return T, o


def import_props():
    c = coll("Props_v1")
    for x in list(c.objects):
        bpy.data.objects.remove(x, do_unlink=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=PROPS_FILE)
    new = [x for x in bpy.data.objects if x not in before]
    for x in new:
        for uc in list(x.users_collection):
            uc.objects.unlink(x)
        c.objects.link(x)
    bpy.context.view_layer.update()
    out = {}
    for x in new:
        if x.type == "MESH":
            x.data.transform(x.matrix_world); x.matrix_world = Matrix.Identity(4); x.parent = None
            out["bow" if "bow" in x.name else "quiver"] = x
        else:
            bpy.data.objects.remove(x, do_unlink=True)
    return out


def place_props():
    """Bow into the fist, quiver onto the back (its inner face 6 mm off the coat), the bow and quiver
    bones added; returns the placed objects (not yet joined)."""
    arm, body = rig(), mesh()
    props = import_props()
    T, o = bow_transform(arm)
    props["bow"].data.transform(T)
    # the quiver: v1's place on the chest, then onto this back
    qv = props["quiver"]
    chest_new = arm.data.bones["spine_03"].head_local
    qv.data.transform(Matrix.Translation(Vector((0, 0, chest_new.z - o["chest"].z))))
    Q = co(qv); Bd = co(body)
    near = Bd[(Bd[:, 2] > Q[:, 2].min()) & (Bd[:, 2] < Q[:, 2].max()) & (np.abs(Bd[:, 0] - Q[:, 0].mean()) < 0.12)]
    back = near[:, 1].max()
    front = np.percentile(Q[:, 1], 2)                      # the quiver's face toward him
    qv.data.transform(Matrix.Translation(Vector((0, back + 0.006 - front, 0))))
    reset_pose(arm)
    # bones
    q0, q1 = o["quiver"]
    dq = Vector((0, 0, chest_new.z - o["chest"].z)) + Vector((0, back + 0.006 - front, 0))
    tip_u, tip_d, nock = T @ o["top"], T @ o["bot"], T @ o["nock"]
    g = T @ o["grip"]
    chord = (tip_u - tip_d).normalized()
    draw = (T.to_3x3() @ o["draw"]).normalized()
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for n in ("Bow", "BowLimb.U", "BowLimb.D", "String", "Arrow", "Quiver"):
        if n in eb:
            eb.remove(eb[n])

    def B(n, h, t, parent, z):
        b = eb.new(n); b.head = h; b.tail = t; b.parent = eb[parent]; b.align_roll(z); b.use_deform = True
        return b
    B("Bow", g - chord * GRIP_HALF, g + chord * GRIP_HALF, "hand_l", draw)
    B("BowLimb.U", g + chord * GRIP_HALF, tip_u, "Bow", draw)
    B("BowLimb.D", g - chord * GRIP_HALF, tip_d, "Bow", draw)
    B("String", nock, nock + draw * 0.08, "Bow", chord)
    a0 = nock - chord * 0.40
    B("Arrow", a0, a0 + chord * 0.76, "Bow", Vector((0, 0, 1)) if abs(chord.z) < 0.9 else Vector((1, 0, 0)))
    B("Quiver", q0 + dq, q1 + dq, "spine_03", Vector((0, -1, 0)))
    bpy.ops.object.mode_set(mode="OBJECT")
    props["T"] = T
    return props


def reset_pose(arm=None):
    arm = arm or rig()
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


GRIP_CUT = 0.135         # the v1 bow's grip, torn where the v1 fist was welded to it, is cut out to here


def _texture_rgb(o):
    """The props' base-colour image as an (h, w, 3) array, and a sampler uv -> rgb."""
    mat = o.data.materials[0]
    node = next(n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image is not None
                and any(l.to_socket.name == "Base Color" for l in n.outputs[0].links))
    im = node.image
    w, h = im.size
    px = np.empty(w * h * 4, np.float32)
    im.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)[:, :, :3]
    return lambda uv: px[min(h - 1, max(0, int(uv[1] * h))), min(w - 1, max(0, int(uv[0] * w)))]


def drop_coat_scraps(o):
    """Delete the faces whose texture is the coat's green (scraps of the v1 body cut out with it)."""
    rgb = _texture_rgb(o)
    uvl = o.data.uv_layers.active.data
    bad = []
    for p in o.data.polygons:
        uv = sum((Vector(uvl[li].uv) for li in p.loop_indices), Vector((0, 0))) / p.loop_total
        r, g, b = rgb(uv)
        if g > r * 1.08 and g > b * 0.95 and g < 0.45:
            bad.append(p.index)
    bm = bmesh.new(); bm.from_mesh(o.data); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in bad], context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(o.data); bm.free()
    return len(bad)


def mend_grip(bow, arm):
    """Cut the torn v1 grip out and bridge the limbs with a leather-wrapped round grip."""
    B = arm.data.bones
    g = (B["Bow"].head_local + B["Bow"].tail_local) / 2
    c = (B["BowLimb.U"].tail_local - B["BowLimb.D"].tail_local).normalized()
    P = co(bow)
    s = (P - np.array(g)) @ np.array(c)
    uvl = bow.data.uv_layers.active.data
    rgb = _texture_rgb(bow)
    wrap_uv, dark = None, 9.0                       # the wrap: the darkest brown of the old grip
    for l in bow.data.loops:
        if abs(s[l.vertex_index]) < 0.12:
            uv = tuple(uvl[l.index].uv); r_, g_, b_ = rgb(uv)
            lum = 0.3 * r_ + 0.6 * g_ + 0.1 * b_
            if r_ >= g_ >= b_ * 0.8 and lum < dark:
                wrap_uv, dark = uv, lum
    ends = []
    for sg in (1, -1):
        m = (sg * s > GRIP_CUT) & (sg * s < GRIP_CUT + 0.02)
        cen = Vector(P[m].mean(0)); rad = float(np.median(np.linalg.norm(P[m] - np.array(cen), axis=1)))
        ends.append((cen, rad))
    bm = bmesh.new(); bm.from_mesh(bow.data); bm.verts.ensure_lookup_table()
    cut = [bm.verts[i] for i in np.nonzero(np.abs(s) < GRIP_CUT)[0]]
    bmesh.ops.delete(bm, geom=cut, context="VERTS")
    (c1, r1), (c2, r2) = ends
    d = (c1 - c2).normalized()
    a, b = c2 - d * 0.012, c1 + d * 0.012
    r = min(r1, r2) * 0.95
    uvlay = bm.loops.layers.uv.active
    u = d.orthogonal().normalized(); w = d.cross(u)
    rows = []
    for k in range(5):
        cc = a.lerp(b, k / 4)
        rows.append([bm.verts.new(cc + (u * math.cos(2 * math.pi * j / 10) + w * math.sin(2 * math.pi * j / 10)) * r) for j in range(10)])
    new = []
    for k in range(4):
        for j in range(10):
            new.append(bm.faces.new((rows[k][j], rows[k][(j + 1) % 10], rows[k + 1][(j + 1) % 10], rows[k + 1][j])))
    new.append(bm.faces.new(list(reversed(rows[0])))); new.append(bm.faces.new(rows[-1]))
    for f in new:
        for l in f.loops:
            l[uvlay].uv = wrap_uv
    bm.to_mesh(bow.data); bm.free()
    return {"grip_r": round(r, 4), "len": round((b - a).length, 3)}


def build_props():
    """Phase B: the v1 bow and quiver placed, cleaned and mended (not yet weighted or joined)."""
    arm = rig()
    p = place_props()
    p["green"] = (drop_coat_scraps(p["bow"]), drop_coat_scraps(p["quiver"]))
    p["grip"] = mend_grip(p["bow"], arm)
    return p


def _tube(bm, a, b, r, uvl, uv, sides=SIDES, rings=6):
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized(); u = d.orthogonal().normalized(); w = d.cross(u)
    rows, out = [], []
    for k in range(rings + 1):
        t = k / rings; c = a.lerp(b, t)
        row = [bm.verts.new(c + (u * math.cos(2 * math.pi * s / sides) + w * math.sin(2 * math.pi * s / sides)) * r) for s in range(sides)]
        rows.append(row); out += [(v, t) for v in row]
    faces = []
    for k in range(rings):
        for s in range(sides):
            faces.append(bm.faces.new((rows[k][s], rows[k][(s + 1) % sides], rows[k + 1][(s + 1) % sides], rows[k + 1][s])))
    faces.append(bm.faces.new(list(reversed(rows[0])))); faces.append(bm.faces.new(rows[-1]))
    for f in faces:
        for l in f.loops:
            l[uvl].uv = uv
    return out


def _uv_of(o, i):
    uvl = o.data.uv_layers.active.data
    for l in o.data.loops:
        if l.vertex_index == i:
            return tuple(uvl[l.index].uv)


def string_and_arrow(p):
    """The drawable string (two strands, tip -> nock, graded limb -> String) and the 76 cm arrow on
    Arrow (shaft, bodkin, three vanes), textured from spots of the props' own texture."""
    import bmesh as bmm
    arm = rig(); B = arm.data.bones
    T = p["T"]; o = _v1()
    s_top, s_bot = T @ o["s_top"], T @ o["s_bot"]
    nock = B["String"].head_local
    bow, qv = p["bow"], p["quiver"]
    Pb, Pq = co(bow), co(qv)
    g = (B["Bow"].head_local + B["Bow"].tail_local) / 2
    c = (B["BowLimb.U"].tail_local - B["BowLimb.D"].tail_local).normalized()
    s = (Pb - np.array(g)) @ np.array(c)
    wood = _uv_of(bow, int(np.argmin(np.abs(s - 0.45))))
    grip = _uv_of(bow, int(np.argmin(np.abs(s))))
    feather = _uv_of(qv, int(np.argmax(Pq[:, 2])))
    mat = bow.data.materials[0]
    made = []
    for name in ("prop_string", "prop_arrow"):
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
    me = bpy.data.meshes.new("prop_string"); bm = bmm.new(); uvl = bm.loops.layers.uv.new("UVMap")
    W = []
    for end, limb in ((s_top, "BowLimb.U"), (s_bot, "BowLimb.D")):
        for v, t in _tube(bm, end, nock, STRING_R, uvl, grip):
            W.append((v, {limb: 1 - t, "String": t}))
    bm.verts.index_update(); W = [(v.index, w) for v, w in W]
    bm.to_mesh(me); bm.free()
    so = bpy.data.objects.new("prop_string", me); coll("Props_v1").objects.link(so)
    for i, w in W:
        for gname, x in w.items():
            if x > 0:
                (so.vertex_groups.get(gname) or so.vertex_groups.new(name=gname)).add([i], x, "REPLACE")
    made.append(so)
    ab = B["Arrow"]; h, t_ = ab.head_local, ab.tail_local; d = (t_ - h).normalized()
    me = bpy.data.meshes.new("prop_arrow"); bm = bmm.new(); uvl = bm.loops.layers.uv.new("UVMap")
    _tube(bm, h, t_ - d * 0.04, SHAFT_R, uvl, wood, rings=2)
    n = len(bm.faces)
    u = d.orthogonal().normalized(); w = d.cross(u)
    base = t_ - d * 0.045
    ring = [bm.verts.new(base + (u * math.cos(k * math.pi / 2) + w * math.sin(k * math.pi / 2)) * 0.007) for k in range(4)]
    tip = bm.verts.new(t_)
    for k in range(4):
        bm.faces.new((ring[k], ring[(k + 1) % 4], tip))
    bm.faces.new(list(reversed(ring)))
    for k in range(3):
        ang = 2 * math.pi * k / 3; out = u * math.cos(ang) + w * math.sin(ang)
        p0, p1 = h + d * 0.025, h + d * 0.145
        pts = [p0 + out * SHAFT_R, p1 + out * SHAFT_R, p1 - d * 0.02 + out * 0.016, p0 + d * 0.01 + out * 0.018]
        bm.faces.new([bm.verts.new(x) for x in pts]); bm.faces.new([bm.verts.new(x) for x in reversed(pts)])
    for f in list(bm.faces)[n:]:
        for l in f.loops:
            l[uvl].uv = feather
    bm.to_mesh(me); bm.free()
    ao = bpy.data.objects.new("prop_arrow", me); coll("Props_v1").objects.link(ao)
    ao.vertex_groups.new(name="Arrow").add(list(range(len(me.vertices))), 1.0, "REPLACE")
    made.append(ao)
    for m in made:
        m.data.materials.append(mat)
    return made


def weight_and_join(p):
    """Weights (the bow graded grip -> tips, the quiver rigid), a `part` attribute, everything
    joined into `archer` (the props keep their own material: a second surface)."""
    arm = rig(); B = arm.data.bones; body = mesh()
    bow, qv = p["bow"], p["quiver"]
    g = (B["Bow"].head_local + B["Bow"].tail_local) / 2
    c = (B["BowLimb.U"].tail_local - B["BowLimb.D"].tail_local).normalized()
    LU = (B["BowLimb.U"].tail_local - g).dot(c); LD = -(B["BowLimb.D"].tail_local - g).dot(c)
    for o_ in (bow, qv):
        o_.vertex_groups.clear()
    P = co(bow); s = (P - np.array(g)) @ np.array(c)
    gb, gu, gd = (bow.vertex_groups.new(name=n) for n in ("Bow", "BowLimb.U", "BowLimb.D"))
    for i, si in enumerate(s):
        if abs(si) <= GRIP_HALF:
            gb.add([i], 1.0, "REPLACE"); continue
        L = LU if si > 0 else LD
        t = min(1.0, (abs(si) - GRIP_HALF) / (L - GRIP_HALF))
        (gu if si > 0 else gd).add([i], t, "REPLACE")
        if t < 1:
            gb.add([i], 1 - t, "REPLACE")
    qv.vertex_groups.new(name="Quiver").add(list(range(len(qv.data.vertices))), 1.0, "REPLACE")
    so, ao = string_and_arrow(p)
    parts = [(body, "body"), (bow, "bow"), (so, "string"), (ao, "arrow"), (qv, "quiver")]
    for o_, n in parts:
        at = o_.data.attributes.get("part") or o_.data.attributes.new("part", "INT", "POINT")
        at.data.foreach_set("value", np.full(len(o_.data.vertices), PARTS.index(n), np.int32))
    # one UV map name, the props' material appended to the body
    uvname = body.data.uv_layers.active.name
    for o_, _ in parts[1:]:
        o_.data.uv_layers.active.name = uvname
    for x in bpy.context.view_layer.objects:
        x.select_set(False)
    for o_, _ in parts:
        o_.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.data.materials[0].name = "archer_body"
    body.data.materials[1].name = "archer_props"
    return {"verts": len(body.data.vertices), "tris": tris(body), "materials": [m.name for m in body.data.materials]}
