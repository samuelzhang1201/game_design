"""The courier's rider body from Blender's CC0 Human Base Meshes bundle (courier model v3):
the realistic male body, turned to face +Y and scaled to 1.75 m."""
import bpy, bmesh, math, sys
from mathutils import Vector, Matrix
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
BUNDLE = (ROOT + "/assets/units3d/ai_src/courier/"
          "human_base_meshes/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend")
HEIGHT = 1.75


def load_body():
    with bpy.data.libraries.load(BUNDLE) as (src, dst):
        dst.objects = ["GEO-body_male_realistic", "GEO-body_male_realistic.eye.L", "GEO-body_male_realistic.eye.R"]
    body, eyes = dst.objects[0], dst.objects[1:]
    for o in dst.objects:
        bpy.context.scene.collection.objects.link(o)
    # the eyes into the body (one mesh), world transforms applied
    bpy.context.view_layer.update()
    bm = bmesh.new()
    for o in [body] + eyes:
        t = bmesh.new()
        t.from_mesh(o.data)
        t.transform(o.matrix_world)
        me = bpy.data.meshes.new("tmp")
        t.to_mesh(me)
        t.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    zmin = min(v.co.z for v in bm.verts)
    cx = sum(v.co.x for v in bm.verts) / len(bm.verts)
    cy = sum(v.co.y for v in bm.verts) / len(bm.verts)
    h = max(v.co.z for v in bm.verts) - zmin
    bm.transform(Matrix.Scale(HEIGHT / h, 4) @ Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Translation((-cx, -cy, -zmin)))
    me = bpy.data.meshes.new("rider_high")
    bm.to_mesh(me)
    bm.free()
    for o in [body] + eyes:
        bpy.data.objects.remove(o, do_unlink=True)
    ob = bpy.data.objects.new("rider_high", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


if __name__ == "__main__":
    ob = load_body()
    co = [v.co for v in ob.data.vertices]
    for z in (0.05, 0.1, 0.3, 0.5, 0.7, 0.85, 0.9, 0.95, 1.0, 1.1, 1.2, 1.3, 1.4, 1.45, 1.5, 1.55, 1.6, 1.7):
        sl = [c for c in co if abs(c.z - z) < 0.01]
        R = [c for c in sl if c.x > 0.0]
        xs = sorted(round(c.x, 3) for c in R)
        # clusters along x on the +X side
        cl, cur = [], [xs[0]] if xs else []
        for a, b in zip(xs, xs[1:]):
            if b - a > 0.03:
                cl.append((cur[0], cur[-1])); cur = [b]
            else:
                cur.append(b)
        if cur: cl.append((cur[0], cur[-1]))
        ys = [round(c.y, 3) for c in sl]
        print("Z %.2f  x-clusters %s  y %s..%s" % (z, cl, min(ys) if ys else None, max(ys) if ys else None))
    tip = max(co, key=lambda c: c.x)
    print("TIP", tuple(round(v, 3) for v in tip), "NOSE", tuple(round(v, 3) for v in max(co, key=lambda c: c.y if c.z > 1.5 else -9)))


def load_body_mr(level=2):
    """v3: the body WITH its Multires sculpt (the face, the fingers, the muscles), the base
    cage turned and scaled like load_body; the eyes as their own objects."""
    with bpy.data.libraries.load(BUNDLE) as (src, dst):
        dst.objects = ["GEO-body_male_realistic", "GEO-body_male_realistic.eye.L", "GEO-body_male_realistic.eye.R"]
    body, eyes = dst.objects[0], list(dst.objects[1:])
    for o in dst.objects:
        bpy.context.scene.collection.objects.link(o)
    bpy.context.view_layer.update()
    me = body.data.copy()
    body.data = me
    mw = body.matrix_world.copy()
    me.transform(mw)
    co = [v.co for v in me.vertices]
    zmin = min(c.z for c in co)
    cx = sum(c.x for c in co) / len(co)
    cy = sum(c.y for c in co) / len(co)
    h = max(c.z for c in co) - zmin
    M = Matrix.Scale(HEIGHT / h, 4) @ Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Translation((-cx, -cy, -zmin))
    me.transform(M)
    body.parent = None
    body.matrix_world = Matrix.Identity(4)
    eye_objs = []
    for e in eyes:
        em = e.data.copy()
        em.transform(e.matrix_world)
        em.transform(M)
        ne = bpy.data.objects.new(e.name + "_v3", em)
        bpy.context.scene.collection.objects.link(ne)
        eye_objs.append(ne)
        bpy.data.objects.remove(e, do_unlink=True)
    mr = body.modifiers[0]
    mr.levels = level
    mr.render_levels = level
    body.name = "rider_high"
    return body, eye_objs
