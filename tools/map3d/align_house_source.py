"""Put a Hunyuan3D-painted house back the way its white model stands.

  blender -b --factory-startup --python tools/map3d/align_house_source.py -- PAINTED.glb WHITE.glb OUT.glb

Hunyuan3D 2.1's paint stage saves through an .obj and comes back UPSIDE DOWN
(2026-09-23: on cottage_a the painted mesh matched its own white model
exactly under diag(1, -1, -1), a half turn about X, and matched nothing
unturned). Rather than trust that to hold for every build of the node, the
turn is FOUND: each of the 48 signed axis permutations is scored by the
mean nearest-vertex distance from the painted mesh to the white one (both
centred and scaled by their bounds), the best is baked into the vertices,
and the file is refused when even the best does not match — a painted mesh
that is not its white model is a failed paint, not an orientation.
"""
import bpy
import itertools
import sys
from mathutils import Matrix, Vector, kdtree

MATCH_MAX = 0.01  # mean distance, as a share of the bounds' longest side


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o.type == "MESH"]


def points(obs):
    return [o.matrix_world @ v.co for o in obs for v in o.data.vertices]


def normalised(vs):
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    return [(v - (lo + hi) / 2) / max(hi - lo) for v in vs]


def main():
    painted, white, out = sys.argv[sys.argv.index("--") + 1:][:3]
    ref = normalised(points(load(white)))
    kd = kdtree.KDTree(len(ref))
    for i, v in enumerate(ref):
        kd.insert(v, i)
    kd.balance()
    obs = load(painted)
    sample = normalised(points(obs))[::5]
    best = None
    for perm in itertools.permutations(range(3)):
        for signs in itertools.product((1, -1), repeat=3):
            m = Matrix([[signs[r] if c == perm[r] else 0 for c in range(3)] for r in range(3)])
            d = sum(kd.find(m @ v)[2] for v in sample) / len(sample)
            if best is None or d < best[0]:
                best = (d, m)
    d, m = best
    print("align: mean distance %.5f with %s" % (d, [list(r) for r in m]))
    if d > MATCH_MAX:
        print("align: REFUSED — the painted mesh is not its white model")
        sys.exit(2)
    m4 = m.to_4x4()
    for o in obs:
        o.data.transform(m4 @ o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        if m.determinant() < 0:  # a mirror turns every face inside out
            o.data.flip_normals()
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB")


main()
