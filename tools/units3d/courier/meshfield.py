"""A mesh as an sdfkit field (courier model v3): signed distance by the nearest point and
its face normal (a BVH), plus an exact ray exit, so v1's cage and sheet tools run on the
scan horse and the posed base-mesh rider."""
import numpy as np
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree


class MeshField:
    def __init__(self, ob=None, bm=None, verts=None, exact=False):
        self.exact = exact            # closed mesh: rays may use the BVH's own exit
        if bm is None:
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bm.transform(ob.matrix_world)
            own = True
        else:
            own = False
        if verts is not None:          # keep only these verts' faces (a torso out of a body)
            keep = set(verts)
            bm.verts.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.index not in keep], context="VERTS")
        self.tree = BVHTree.FromBMesh(bm)
        if own:
            bm.free()

    def __call__(self, P):
        P = np.atleast_2d(P)
        out = np.empty(len(P))
        fn = self.tree.find_nearest
        for i, p in enumerate(P):
            loc, nor, _, d = fn(Vector(p))
            if loc is None:
                out[i] = 1.0
                continue
            out[i] = d if (Vector(p) - loc).dot(nor) >= 0 else -d
        return out

    def ray(self, o, d, tmax=10.0):
        loc, nor, _, dist = self.tree.ray_cast(Vector(o), Vector(d).normalized(), tmax)
        return (np.array(loc), np.array(nor), dist) if loc is not None else (None, None, None)

    def exit_ray(self, O, D, tmax, grow=0.0):
        """Distance along each ray (from inside) to where it leaves the surface grown by
        `grow` (the grown surface's exit taken along the ray: grow / |cos|, capped)."""
        out = np.empty(len(O))
        hit = np.zeros(len(O), bool)
        rc = self.tree.ray_cast
        for i, (o, d) in enumerate(zip(O, D)):
            dv = Vector(d).normalized()
            loc, nor, _, dist = rc(Vector(o), dv, tmax)
            if loc is None:
                out[i] = tmax
                continue
            c = abs(dv.dot(nor))
            out[i] = min(tmax, dist + grow / max(c, 0.35))
            hit[i] = True
        return out, hit
