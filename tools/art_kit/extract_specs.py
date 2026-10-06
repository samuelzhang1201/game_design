"""Write the cc_art_check add-on's specs.json from what the game ships today.

    python3 tools/art_kit/extract_specs.py          # needs the bpy module (pip install bpy)
    blender -b --factory-startup --python tools/art_kit/extract_specs.py

The artist's Blender add-on (tools/art_kit/blender/cc_art_check/) checks a
model against the game's contract without reading the repository, so every
number it needs is copied here from the repository's own sources:

* houses — data/map3d_houses.csv (type, role, footprint, roof kind) and the
  triangle budget of each house group (the shipped meshes plus a margin,
  the numbers of the art handbook's spec table);
* units  — each shipped assets/3D/units/<code>/<code>.glb: its skeleton (bone
  names, rest head / tail / roll / parent, so the add-on can lay the same
  skeleton out as a template), its clips, its triangles and its rest height;
* names  — the node and image names of each shipped .glb (glb_names.py), which
  the game's model scene depends on: the add-on's export writes them and
  checks the file it wrote, so a new delivery overwrites the .glb as it is
  (owner 2026-10-04).

Rerun it after a house row or a unit's skeleton changes, then
tools/art_kit/build_kit.py to rebuild the zip.
"""
import csv
import json
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_names  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BUILDINGS = os.path.join(ROOT, "assets", "3D", "buildings")
OUT = os.path.join(ROOT, "tools", "art_kit", "blender", "cc_art_check", "specs.json")

# Triangle ceilings per house type: the Tripo budgets of
# tools/map3d/tripo_houses/tripo_houses.py JOBS plus the footing the export
# adds (the shipped meshes land 4-8% over the budget), rounded up.
HOUSE_BUDGET = {
    "cottage_a": 1300, "cottage_b": 1300, "cottage_c": 1300, "longhouse": 1300,
    "workshop": 1300, "barn": 1300, "byre": 1300,
    "townhouse_a": 2200, "townhouse_b": 2200, "townhouse_c": 2200,
    "chapel": 3300, "church": 5000, "church_b": 5000, "church_tower": 6000,
    "palace": 61000, "palace_b": 61000, "palace_c": 61000,
}
HOUSE_ATLAS = {"church": 2048, "church_b": 2048, "church_tower": 2048,
               "palace": 2048, "palace_b": 2048, "palace_c": 2048}
HD = {"palace", "palace_b", "palace_c"}   # three materials and a normal map
FOOTING_M = 18.0     # tools/map3d/blender_houses/kit.py FOOT_M
HOLE_MAX_M = 1.0     # tests/map3d/test_map3d_houses_meshes.gd HOLE_MAX_M

# Units: which clips each needs, its ceiling, what its walk bones are called.
UNITS = {
    "infantry": {"label": "步兵", "clips": ["MARCH", "STANDBY", "GARRISON"], "optional": ["ATTACK"],
                 "loops": ["MARCH", "STANDBY", "GARRISON"], "weapon": "spear", "tris": 20000},
    "cavalry": {"label": "骑兵", "clips": ["MARCH", "STANDBY", "GARRISON", "ATTACK"], "optional": ["DEFEND"],
                "loops": ["MARCH", "STANDBY", "GARRISON"], "weapon": "lance", "tris": 20000},
    "courier": {"label": "信使", "clips": ["GALLOP", "IDLE"], "optional": [],
                "loops": ["GALLOP", "IDLE"], "weapon": "", "tris": 20000},
}


def houses():
    out = {}
    with open(os.path.join(ROOT, "data", "map3d_houses.csv"), newline="") as f:
        for r in csv.DictReader(f):
            t = r["type"]
            roof = "hh_slate_" if "slate" in r["roof"] or t in HD else "hh_roof_"
            mats = (["hh_slate_" + t, "hh_stone_" + t, "hh_stone_" + t + "_foot"] if t in HD
                    else [roof + t, "hh_wall_" + t])
            out[t] = {"role": r["role"], "footprint_m": float(r["footprint_m"]),
                      "width_m": float(r["width_m"]), "depth_m": float(r["depth_m"]),
                      "height_m": float(r["height_m"]), "notes": r["notes"],
                      "tris": HOUSE_BUDGET.get(t, 2200), "atlas_px": HOUSE_ATLAS.get(t, 1024),
                      "materials": mats, "hd": t in HD}
            out[t].update(house_names(t))
    return out


def house_names(t):
    """The mesh node and image names of the shipped house; a type with no
    model yet gets the names every house has (<type>_export, <type>_atlas)."""
    path = os.path.join(BUILDINGS, t, t + ".glb")
    if not os.path.exists(path):
        return {"object": t + "_export", "images": [t + "_atlas"]}
    n = glb_names.read(path)
    return {"object": n["meshes"][0], "images": n["images"]}


def unit_names(code):
    """The rig and mesh node names of the shipped regiment, and its three
    images by role (<x>_n the normal map, <x>_mr metallic / roughness)."""
    n = glb_names.read(os.path.join(ROOT, "assets", "3D", "units", code, code + ".glb"))
    imgs = n["images"]
    role = lambda suffix: next((i for i in imgs if i.endswith(suffix)), "")
    base = next((i for i in imgs if not i.endswith(("_n", "_mr"))), "")
    return {"rig": n["roots"][0], "mesh": n["meshes"][0],
            "images": {"base": base, "normal": role("_n"), "mr": role("_mr")}}


def unit(code, spec):
    path = os.path.join(ROOT, "assets", "3D", "units", code, code + ".glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    mw = arm.matrix_world
    bones = []
    for b in arm.data.edit_bones:
        h, t = mw @ b.head, mw @ b.tail
        bones.append({"name": b.name, "parent": b.parent.name if b.parent else "",
                      "head": [round(v, 4) for v in h], "tail": [round(v, 4) for v in t],
                      "roll": round(b.roll, 4)})
    bpy.ops.object.mode_set(mode="OBJECT")
    zs, tris = [], 0
    for o in meshes:
        dg = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
        me = dg.to_mesh()
        zs += [(o.matrix_world @ v.co).z for v in me.vertices]
        tris += sum(len(p.vertices) - 2 for p in me.polygons)
        dg.to_mesh_clear()
    clips = sorted(a.name for a in bpy.data.actions)
    return dict(spec, bones=bones, shipped_clips=clips, shipped_tris=tris,
                shipped_height_m=round(max(zs) - min(zs), 3), **unit_names(code))


def main():
    specs = {"version": 1, "footing_m": FOOTING_M, "hole_max_m": HOLE_MAX_M,
             "fps": 30, "metallic_max": 0.25, "roughness_min": 0.55, "unit_atlas_px": 2048,
             "houses": houses(), "units": {}}
    for code, spec in UNITS.items():
        specs["units"][code] = unit(code, spec)
        u = specs["units"][code]
        print("%-9s %2d bones, clips %s, %d tris, %.2f m tall" % (
            code, len(u["bones"]), u["shipped_clips"], u["shipped_tris"], u["shipped_height_m"]))
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(specs, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("wrote", os.path.relpath(OUT, ROOT), "-", len(specs["houses"]), "house types")


main()
