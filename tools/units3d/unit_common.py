"""Shared helpers for the 3D military unit pipeline (2026-09-21).

The units are Hunyuan3D sources retopologised, rigged and animated into one
glTF each, the same way tools/map3d/retopo_houses.py treats the houses —
voxel remesh, one collapse pass, bake the AI surface onto the result — with
two things the houses never needed: a skeleton and its actions (GARRISON,
MARCH, ATTACK). The pieces stand on no base (owner 2026-09-27).
"""

import bpy
import csv
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TABLE = os.path.join(ROOT, "data", "unit_models.csv")
OUT = os.path.join(ROOT, "assets", "3D", "units")
SRC = os.path.join(OUT, "model_wip")


def glb_path(out_dir, code):
    """Where a unit's .glb goes: assets/3D/units/<code>/<code>.glb for the shipped
    set (its model_wip/ beside it), flat in any trial directory."""
    if os.path.abspath(out_dir) == os.path.abspath(OUT):
        os.makedirs(os.path.join(out_dir, code), exist_ok=True)
        return os.path.join(out_dir, code, code + ".glb")
    return os.path.join(out_dir, code + ".glb")


def log(msg):
    print("units3d: " + str(msg))
    sys.stdout.flush()


def rows():
    with open(TABLE) as f:
        return list(csv.DictReader(f))


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def apply_transform(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def bounds(ob):
    """The world bounding box, measured from the VERTICES.

    Never from `ob.bound_box`: that is a cache, and in background Blender
    nothing refreshes it between an operator and the next read, so a mesh
    that has just had a rotation applied into it still reports the box it had
    before. That cost a whole build — the figures were turned to face +Y
    exactly as asked, the measurement said they had not moved, and every
    box measured off it (the spear's, the shield's) came out on the wrong
    side of the man.
    """
    import numpy as np
    from mathutils import Vector
    n = len(ob.data.vertices)
    co = np.empty(n * 3, dtype=np.float64)
    ob.data.vertices.foreach_get("co", co)
    co = co.reshape(n, 3)
    m = np.array(ob.matrix_world, dtype=np.float64)
    co = co @ m[:3, :3].T + m[:3, 3]
    return Vector(co.min(axis=0)), Vector(co.max(axis=0))


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def import_joined(path, name):
    """Import a glTF and return ONE mesh object with its transform applied.

    The importer leaves a -90 degree X rotation on the object to turn glTF's
    Y-up into Blender's Z-up; applying it here makes object-local and world
    axes agree, so a per-axis scale cannot silently swap Y and Z.
    """
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects
              if o not in before and o.type == "MESH"]
    if not meshes:
        raise RuntimeError("no mesh in " + path)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    apply_transform(ob)
    return ob


def place(ob, height_m, yaw_offset_deg):
    """Turn, scale UNIFORMLY to height_m, and seat the figure on z = 0,
    centred in x/y on its OWN FOOTPRINT rather than its bounding box.

    The footprint, not the box: a spear leaning out past the shoulder drags
    the box's centre off the man, and the figure would then stand off-centre
    on its spot. The footprint is the lowest tenth of the mesh — feet and
    hooves — which is what actually has to stand on the spot.
    """
    from mathutils import Matrix, Vector
    if yaw_offset_deg:
        # Through the MATRIX, never rotation_euler: the glTF importer leaves
        # every object in QUATERNION rotation mode, where assigning
        # rotation_euler changes nothing at all and transform_apply then
        # cheerfully reports FINISHED having baked an identity. That is a
        # silent failure with no error anywhere — the figures simply stayed
        # facing the way they were imported.
        ob.matrix_world = (Matrix.Rotation(math.radians(yaw_offset_deg), 4, "Z")
                           @ ob.matrix_world)
        apply_transform(ob)
    lo, hi = bounds(ob)
    span = (hi - lo).z
    if span <= 0.0:
        raise RuntimeError("degenerate source for " + ob.name)
    k = height_m / span
    ob.scale = (k, k, k)
    apply_transform(ob)
    lo, hi = bounds(ob)
    foot_top = lo.z + (hi.z - lo.z) * 0.10
    feet = [v.co for v in ob.data.vertices if v.co.z <= foot_top]
    if len(feet) < 16:
        feet = [v.co for v in ob.data.vertices]
    cx = (min(v.x for v in feet) + max(v.x for v in feet)) * 0.5
    cy = (min(v.y for v in feet) + max(v.y for v in feet)) * 0.5
    ob.location += Vector((-cx, -cy, -lo.z))
    apply_transform(ob)
    return bounds(ob)


def profile(ob, levels=21):
    """The mesh's x/y extent at evenly spaced heights — the measurement the
    skeleton is built from, so no joint position is ever a guess."""
    lo, hi = bounds(ob)
    h = (hi - lo).z
    out = []
    band = h / float(levels)
    for i in range(levels):
        z0 = lo.z + band * i
        z1 = z0 + band
        vs = [v.co for v in ob.data.vertices if z0 <= v.co.z < z1]
        if not vs:
            out.append((z0 / h, 0, 0.0, 0.0, 0.0, 0.0))
            continue
        out.append((z0 / h, len(vs),
                    min(v.x for v in vs), max(v.x for v in vs),
                    min(v.y for v in vs), max(v.y for v in vs)))
    return out
