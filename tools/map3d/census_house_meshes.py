"""Report what is actually wrong with the built house meshes.

  blender -b --factory-startup --python tools/map3d/census_house_meshes.py

Read-only. For each `assets/map3d_houses/*.glb` it prints the triangle count,
the number of holes and the widest one in metres, and the winding conflicts —
all over Blender's real topology — the mesh WELDED BY DISTANCE first, which
is the step that makes such a census mean anything: glTF stores a vertex per
face corner at every UV seam, so a freshly imported house has almost no
shared edges and an unwelded census cheerfully reports "nothing wrong" about
anything (it did, until this was caught on 2026-09-22). Welding also gives
the reading `tests/map3d/test_map3d_houses_meshes.gd` approximates by keying
edges on ROUNDED POSITION. Run this whenever that test reports something
surprising, and trust this over a hand-rolled census.

**Do NOT "fix" a mesh with `bmesh.ops.recalc_face_normals`.** These meshes are
open SHELLS, and Blender's recalc decides inside from outside by volume: on a
shell it flips whole patches the wrong way. Tried on church, whose position
census showed one phantom conflict — it came back with 19,254 real ones, and
the mesh had to be restored from a copy. A genuinely flipped face is fixed at
the source (regenerate, or re-run retopo_houses.py --only <type>), never by a
blanket recalc on the built file.
"""
import bpy
import bmesh
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "map3d_houses")


def census(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    # glTF stores a vertex per FACE CORNER wherever a UV or normal seam runs,
    # so a freshly imported mesh has almost no shared edges at all and every
    # census over it reads "no neighbours, therefore nothing wrong". Weld by
    # distance first: only then does bmesh see the surface the renderer sees.
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
    bm.verts.ensure_lookup_table()
    bad = 0
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        i, j = e.verts[0].index, e.verts[1].index

        def forward(face):
            loop = [v.index for v in face.verts]
            k = loop.index(i)
            return loop[(k + 1) % len(loop)] == j
        if forward(e.link_faces[0]) == forward(e.link_faces[1]):
            bad += 1
    # the holes an open shell has, and the widest of them: boundary edges
    # walked into the loops they form, each loop measured by its own box
    border = [e for e in bm.edges if len(e.link_faces) == 1]
    seen, widest, holes = set(), 0.0, 0
    adj = {}
    for e in border:
        for a, b in ((e.verts[0], e.verts[1]), (e.verts[1], e.verts[0])):
            adj.setdefault(a.index, []).append(b.index)
    for start in adj:
        if start in seen:
            continue
        holes += 1
        stack, lo, hi = [start], None, None
        seen.add(start)
        while stack:
            at = stack.pop()
            co = bm.verts[at].co
            lo = co.copy() if lo is None else [min(lo[k], co[k]) for k in range(3)]
            hi = co.copy() if hi is None else [max(hi[k], co[k]) for k in range(3)]
            for nxt in adj[at]:
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        widest = max(widest, sum((hi[k] - lo[k]) ** 2 for k in range(3)) ** 0.5)
    tris = len(bm.faces)
    bm.free()
    return tris, holes, widest, bad


def main():
    print("%-14s %8s %7s %11s %9s" % ("type", "tris", "holes", "widest_m", "flipped"))
    for name in sorted(os.listdir(OUT)):
        if not name.endswith(".glb"):
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, name))
        ob = next(o for o in bpy.data.objects if o.type == "MESH")
        tris, holes, widest, bad = census(ob)
        print("%-14s %8d %7d %11.2f %9d" % (name[:-4], tris, holes, widest, bad))
        sys.stdout.flush()


if __name__ == "__main__":
    main()
