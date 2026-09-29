"""Build the blueprint man-at-arms from an EMPTY scene: base mesh -> armour -> rig -> MARCH ->
GARRISON, saved as the untextured model file that texture.py then textures.

  blender -b --factory-startup --python build_model.py -- OUT.blend
"""
import bpy, sys

HERE = "/Users/samuelzhang/game_design/tools/units3d/infantry_blueprint/"
OUT = sys.argv[sys.argv.index("--") + 1]

for ob in list(bpy.data.objects):          # --factory-startup's cube, camera and light
    bpy.data.objects.remove(ob, do_unlink=True)
exec(open(HERE + "base_mesh.py").read(), {"BUILD": True})
exec(open(HERE + "armour.py").read(), {"STEP": 5})
exec(open(HERE + "rig.py").read(), {})
exec(open(HERE + "march.py").read(), {})
exec(open(HERE + "garrison.py").read(), {})
for o in list(bpy.data.collections["Armour"].objects) + [bpy.data.objects["base_body"]]:
    o.hide_render = True
    o.hide_set(True)
for o in bpy.data.collections["Infantry"].objects:
    o.show_wire = False
bpy.context.scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("MODEL SAVED", OUT)
