"""Bring the owner's king on horseback to the units' triangle budget.

    Blender -b <tripo>/knight_rig_anim.blend --python tools/units3d/royal_install/decimate.py [-- --tris 20000]

Reads the owner's rig scene (never saves over it), collapses the skinned mesh
to ~20k triangles with a Decimate modifier applied UNDER the Armature one
(Collapse interpolates the vertex groups, so the weights and the five NLA
clips carry over untouched), then writes beside the source:

* knight_rig_anim_20k.blend — the decimated scene, for a look in Blender;
* knight_rigged_20k.glb     — its export (NLA tracks as clips), what
  install.py installs.

The owner's budget: ~15–20k tris a unit (the cavalry 19k), detail in the
baked maps, not the triangles; a full royal regiment stands nine.
"""
import sys
from pathlib import Path

import bpy

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
TARGET = int(args[args.index("--tris") + 1]) if "--tris" in args else 20000
SRC = Path(bpy.data.filepath)


def tris(me) -> int:
    return sum(len(p.vertices) - 2 for p in me.polygons)


def deform_share(ob) -> float:
    """Share of vertices no deforming bone holds (0 means all are skinned)."""
    rig = next(m.object for m in ob.modifiers if m.type == 'ARMATURE')
    deform = {b.name for b in rig.data.bones if b.use_deform}
    idx = {g.index for g in ob.vertex_groups if g.name in deform}
    bare = sum(1 for v in ob.data.vertices
               if not any(g.group in idx and g.weight > 1e-4 for g in v.groups))
    return bare / max(len(ob.data.vertices), 1)


def main() -> None:
    ob = next(o for o in bpy.data.objects
              if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers))
    before = tris(ob.data)
    bare_before = deform_share(ob)
    dec = ob.modifiers.new("budget", 'DECIMATE')
    dec.decimate_type = 'COLLAPSE'
    dec.ratio = TARGET / before
    dec.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_move_to_index(modifier=dec.name, index=0)
    bpy.ops.object.modifier_apply(modifier=dec.name)
    after = tris(ob.data)
    bare_after = deform_share(ob)
    print("DECIMATE %s: %d -> %d tris, %d verts; unskinned %.4f -> %.4f"
          % (ob.name, before, after, len(ob.data.vertices), bare_before, bare_after))
    assert bare_after <= bare_before + 1e-3, "decimation left vertices no bone holds"
    blend = SRC.with_name(SRC.stem + "_20k.blend")
    glb = SRC.with_name("knight_rigged_20k.glb")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend), copy=True)
    bpy.ops.export_scene.gltf(filepath=str(glb), export_format='GLB',
                              export_animation_mode='NLA_TRACKS', export_skins=True,
                              export_yup=True, export_apply=False)
    print("WROTE", blend.name, glb.name)


main()
