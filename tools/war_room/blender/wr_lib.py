# War-room art helpers, exec'd inside the owner's Blender (scene WarRoomArt).
# Game coords (x, y up, z south) -> Blender (x, -z, y).
import bpy, bmesh, math
from mathutils import Vector, Matrix

import os
WR = globals().get("WR", "/Users/samuelzhang/game_design/tools/war_room/blender")
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(WR)))   # the checkout
EXP = ROOT + "/assets/3D/war_room"                    # <name>/<name>.glb
TEX = EXP + "/model_wip/textures"                     # Poly Haven 2k sources + the painted atlases


def G(x, y, z):
    return Vector((x, -z, y))


def coll(name):
    sc = bpy.data.scenes["WarRoomArt"]
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        sc.collection.children.link(c)
    return c


def new_obj(name, bm, collection, mats):
    me = bpy.data.meshes.get(name)
    if me is not None:
        old = bpy.data.objects.get(name)
        if old is not None:
            bpy.data.objects.remove(old, do_unlink=True)
        bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    coll(collection).objects.link(ob)
    return ob


def tag(faces, mat_index):
    for f in faces:
        f.material_index = mat_index


def quad_strip(bm, rows, closed=True, cap_start=False, cap_end=False):
    """rows: list of rings (lists of Vectors, equal length). Returns faces."""
    R = [[bm.verts.new(p) for p in r] for r in rows]
    n = len(rows[0])
    out = []
    for i in range(len(R) - 1):
        for j in range(n if closed else n - 1):
            j2 = (j + 1) % n
            out.append(bm.faces.new((R[i][j], R[i][j2], R[i + 1][j2], R[i + 1][j])))
    if cap_start:
        out += cap(bm, R[0], flip=True)
    if cap_end:
        out += cap(bm, R[-1])
    return out


def cap(bm, ring, flip=False):
    """Close a ring: quads when even (pairs fanned from ring[0]), so no n-gon."""
    n = len(ring)
    faces = []
    if n == 4:
        f = bm.faces.new(list(reversed(ring)) if flip else ring)
        return [f]
    c = sum((v.co for v in ring), Vector()) / n
    cv = bm.verts.new(c)
    # quads around a centre vertex: (ring[j], ring[j+1], ring[j+2], centre) for even n
    if n % 2 == 0:
        for j in range(0, n, 2):
            q = [ring[j], ring[(j + 1) % n], ring[(j + 2) % n], cv]
            faces.append(bm.faces.new(list(reversed(q)) if flip else q))
    else:
        for j in range(n):
            t = [ring[j], ring[(j + 1) % n], cv]
            faces.append(bm.faces.new(list(reversed(t)) if flip else t))
    return faces


def lathe(bm, profile, seg, center, axis_up=Vector((0, 0, 1)), cap_start=False, cap_end=False, phase=0.0):
    """profile: [(radius, height)] bottom->top, around +Z (Blender) at center."""
    rows = []
    for r, h in profile:
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg + phase
            ring.append(center + Vector((math.cos(a) * r, math.sin(a) * r, h)))
        rows.append(ring)
    return quad_strip(bm, rows, True, cap_start, cap_end)


def box(bm, lo, hi, skip=()):
    """Axis-aligned box in Blender coords; skip: subset of ('-x','+x','-y','+y','-z','+z')."""
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    v = [bm.verts.new(p) for p in [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                     (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]]
    F = {'-z': (0, 3, 2, 1), '+z': (4, 5, 6, 7), '-y': (0, 1, 5, 4), '+y': (2, 3, 7, 6),
         '-x': (3, 0, 4, 7), '+x': (1, 2, 6, 5)}
    out = []
    for k, idx in F.items():
        if k in skip:
            continue
        out.append(bm.faces.new([v[i] for i in idx]))
    return out


def sweep(bm, path, section, closed_path=False, up=Vector((0, 0, 1)), cap_ends=True, scale=None):
    """Sweep a closed 2D section [(u,v)] along a 3D polyline (parallel-transport frames)."""
    n = len(path)
    rows = []
    prev_side = None
    for i, p in enumerate(path):
        if closed_path:
            t = (path[(i + 1) % n] - path[i - 1]).normalized()
        else:
            a = path[max(i - 1, 0)]
            b = path[min(i + 1, n - 1)]
            t = (b - a).normalized()
        if prev_side is None:
            ref = up if abs(t.dot(up)) < 0.95 else Vector((1, 0, 0))
            side = t.cross(ref).normalized()
        else:
            side = (prev_side - t * prev_side.dot(t)).normalized()
        prev_side = side
        nrm = side.cross(t).normalized()
        s = scale[i] if scale else 1.0
        rows.append([p + side * (u * s) + nrm * (v * s) for (u, v) in reversed(section)])
    if closed_path:
        rows.append(rows[0])
    faces = quad_strip(bm, rows, True, cap_ends and not closed_path, cap_ends and not closed_path)
    return faces


def finish_mesh(ob, hard_deg=40.0, merge=1e-6):
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0.0) <= math.radians(hard_deg)
        else:
            e.smooth = False
    bm.to_mesh(me)
    bm.free()
    me.update()


def box_uv(ob, tile_by_mat, rot90_mats=()):
    """World-scale box projection per face; tile_by_mat[mat_index] = metres per UV unit
    (None leaves the face's UV at a fixed small patch)."""
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    mw = ob.matrix_world
    for p in me.polygons:
        n = p.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        tile = tile_by_mat.get(p.material_index, 1.0)
        for li in p.loop_indices:
            co = mw @ me.vertices[me.loops[li].vertex_index].co
            if ax == 2:
                u, v = co.x, co.y
            elif ax == 1:
                u, v = co.x, co.z
            else:
                u, v = co.y, co.z
            if p.material_index in rot90_mats:
                u, v = v, u
            uv[li].uv = (u / tile, v / tile) if tile else (0.5, 0.5)


def img(path):
    for im in bpy.data.images:
        if im.filepath == path:
            return im
    im = bpy.data.images.load(path)
    return im


def mat_tex(name, base, normal=None, rough=None, rough_val=0.8, normal_strength=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs[0], out.inputs[0])
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img(base)
    nt.links.new(t.outputs["Color"], bs.inputs["Base Color"])
    bs.inputs["Metallic"].default_value = 0.0
    bs.inputs["Roughness"].default_value = rough_val
    if rough:
        tr = nt.nodes.new("ShaderNodeTexImage")
        tr.image = img(rough)
        tr.image.colorspace_settings.name = "Non-Color"
        nt.links.new(tr.outputs["Color"], bs.inputs["Roughness"])
    if normal:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = img(normal)
        tn.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
    return m


def mat_flat(name, rgb, rough=0.6, metal=0.0, emit=None, emit_strength=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bs = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bs.inputs["Base Color"].default_value = (*rgb, 1.0)
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Metallic"].default_value = metal
    if emit is not None:
        bs.inputs["Emission Color"].default_value = (*emit, 1.0)
        bs.inputs["Emission Strength"].default_value = emit_strength
    m.diffuse_color = (*rgb, 1.0)
    return m


def tris_of(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    t = sum(len(p.vertices) - 2 for p in me.polygons)
    ev.to_mesh_clear()
    return t
