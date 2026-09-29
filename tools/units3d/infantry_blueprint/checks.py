"""Clipping checks on the rigged man-at-arms (collection `Infantry`), run in the open model file:
  exec(open(".../checks.py").read(), g); g["cloak"]("MARCH", range(1, 33)); g["spear"]()
cloak(): vertices of other pieces standing BEHIND the cloak (poking out through it), per frame.
spear(): each piece's least clearance from the spear's shaft over MARCH (metres, < 0 = inside)."""
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_point_line


def cloak(action, frames, lo=0.02):
    sc = bpy.context.scene
    rig = bpy.data.objects["inf_rig"]
    rig.animation_data.action = bpy.data.actions[action]
    out = {}
    for f in frames:
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        cl = bpy.data.objects["inf_cloak"].evaluated_get(dg)
        me = cl.to_mesh()
        tree = BVHTree.FromPolygons([cl.matrix_world @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
        cl.to_mesh_clear()
        for o in bpy.data.collections["Infantry"].objects:
            if o.type != "MESH" or o.name == "inf_cloak":
                continue
            ev = o.evaluated_get(dg)
            m = ev.to_mesh()
            n = 0
            for v in m.vertices:
                p = o.matrix_world @ v.co
                if p.y < lo or p.z < 0.45 or p.z > 1.48:
                    continue
                hit = tree.ray_cast(Vector((p.x, -1.0, p.z)), Vector((0, 1, 0)))
                if hit[0] is not None and hit[0].y < p.y - 0.001:
                    n += 1
            ev.to_mesh_clear()
            if n:
                out.setdefault(o.name, []).append((f, n))
    return out


SPEAR_NEAR = ("inf_pauldron", "inf_breastplate", "inf_besagew", "inf_helmet", "inf_visor", "inf_bevor",
              "inf_gorget_1", "inf_rivets_pauldron", "inf_cloak")


def spear(action="MARCH", step=2, radius=0.0165):
    sc = bpy.context.scene
    rig = bpy.data.objects["inf_rig"]
    act = bpy.data.actions[action]
    rig.animation_data.action = act
    res = {}
    for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1, step):
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        sp = bpy.data.objects["inf_spear"].evaluated_get(dg)
        me = sp.to_mesh()
        vs = [sp.matrix_world @ v.co for v in me.vertices]
        sp.to_mesh_clear()
        c = sum(vs, Vector()) / len(vs)
        ax = max(((a - b) for a in vs[:40] for b in vs[-40:]), key=lambda d: d.length).normalized()
        for n in SPEAR_NEAR:
            o = bpy.data.objects[n].evaluated_get(dg)
            m = o.to_mesh()
            best = min(((o.matrix_world @ v.co) - intersect_point_line(o.matrix_world @ v.co, c - ax * 2, c + ax * 2)[0]).length
                       for v in m.vertices)
            o.to_mesh_clear()
            res[n] = min(res.get(n, 9), round(best - radius, 3))
    return res


SHIELD_OWN = {"inf_shield", "inf_gauntlet", "inf_vambrace_lower", "inf_vambrace_upper", "inf_rivets_vambrace_lower",
              "inf_rivets_vambrace_upper", "inf_couter", "inf_couter_wing", "inf_spear"}


def shield(action="GARRISON", frames=None):
    """(vertices within 6 mm of another piece, vertices inside one) at the worst frame: the
    shield against everything but its own arm."""
    sc = bpy.context.scene
    rig = bpy.data.objects["inf_rig"]
    act = bpy.data.actions[action]
    rig.animation_data.action = act
    frames = frames or range(int(act.frame_range[0]), int(act.frame_range[1]) + 1, 10)
    near = inside = 0
    for f in frames:
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        verts, polys = [], []
        for o in bpy.data.collections["Infantry"].objects:
            if o.type != "MESH" or o.name in SHIELD_OWN:
                continue
            ev = o.evaluated_get(dg)
            me = ev.to_mesh()
            k = len(verts)
            verts += [o.matrix_world @ v.co for v in me.vertices]
            polys += [tuple(k + i for i in p.vertices) for p in me.polygons]
            ev.to_mesh_clear()
        tree = BVHTree.FromPolygons(verts, polys)
        sh = bpy.data.objects["inf_shield"].evaluated_get(dg)
        me = sh.to_mesh()
        pts = [sh.matrix_world @ v.co for v in me.vertices]
        sh.to_mesh_clear()
        n_near = n_in = 0
        for p in pts:
            loc, nor, _, d = tree.find_nearest(p)
            if loc is None:
                continue
            n_near += d < 0.006
            n_in += d < 0.03 and (p - loc).dot(nor) < 0
        near, inside = max(near, n_near), max(inside, n_in)
    return near, inside
