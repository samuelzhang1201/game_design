import os
import bpy, math, sys, mathutils
a = sys.argv[sys.argv.index("--")+1:]
OUT, VIEWS = a[0], a[1:]
sc = bpy.context.scene
for n in ("BP_front", "BP_side", "BP_back", "Camera", "Light"):
    o = bpy.data.objects.get(n)
    if o: o.hide_render = True
for e in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try: sc.render.engine = e; break
    except TypeError: pass
sc.render.resolution_x, sc.render.resolution_y = 700, 900
w = bpy.data.worlds.new("w"); w.use_nodes = True; sc.world = w
bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND"); bg.inputs["Strength"].default_value = 0.9
_tc = w.node_tree.nodes.new("ShaderNodeTexCoord"); _sp = w.node_tree.nodes.new("ShaderNodeSeparateXYZ"); _cr = w.node_tree.nodes.new("ShaderNodeValToRGB")
w.node_tree.links.new(_tc.outputs["Generated"], _sp.inputs[0]); w.node_tree.links.new(_sp.outputs["Z"], _cr.inputs[0])
_cr.color_ramp.elements[0].position = 0.40; _cr.color_ramp.elements[0].color = (0.10, 0.09, 0.08, 1)
_cr.color_ramp.elements[1].position = 0.75; _cr.color_ramp.elements[1].color = (0.85, 0.90, 1.0, 1)
_e = _cr.color_ramp.elements.new(0.52); _e.color = (0.55, 0.55, 0.56, 1)
w.node_tree.links.new(_cr.outputs["Color"], bg.inputs["Color"])
sc.render.film_transparent = False
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun); sun.data.energy = 4.5
fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN")); sc.collection.objects.link(fill); fill.data.energy = 1.2; fill.rotation_euler = (math.radians(70), 0, math.radians(150))
sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"
FR = int(os.environ.get('FR', '1'))
sc.frame_set(FR)
for v in VIEWS:
    tag, t, s_, yaw, pit = v.split(":")
    tv = mathutils.Vector([float(x) for x in t.split(",")])
    cam.data.ortho_scale = float(s_)
    ya, pa = math.radians(float(yaw)), math.radians(float(pit))
    # yaw 0 = the front (the character faces -Y), 90 = his left side (+X)
    cam.location = tv + mathutils.Vector((math.sin(ya) * math.cos(pa), -math.cos(ya) * math.cos(pa), math.sin(pa))) * 5
    cam.rotation_euler = (tv - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = "%s_%s.png" % (OUT, tag); bpy.ops.render.render(write_still=True)
