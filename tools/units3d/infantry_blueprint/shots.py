import bpy, math, sys, mathutils
a = sys.argv[sys.argv.index("--")+1:]
OUT, VIEWS = a[0], a[1:]
sc = bpy.context.scene
for n in ("BP_front", "BP_side", "BP_back", "Camera", "Light"):
    o = bpy.data.objects.get(n)
    if o: o.hide_render = True
for o in bpy.data.objects:
    if o.type == "MESH":
        for m in o.data.materials:
            if m and m.name == "arm_steel":
                m.use_nodes = True
                b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
                b.inputs["Base Color"].default_value = (0.55, 0.56, 0.58, 1); b.inputs["Metallic"].default_value = 0.85; b.inputs["Roughness"].default_value = 0.38
            elif m and m.name != "base_clay":
                m.use_nodes = True
                b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
                b.inputs["Base Color"].default_value = m.diffuse_color
for e in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try: sc.render.engine = e; break
    except TypeError: pass
sc.render.resolution_x, sc.render.resolution_y = 700, 900
w = bpy.data.worlds.new("w"); w.use_nodes = True; sc.world = w
bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND"); bg.inputs["Color"].default_value = (0.42, 0.44, 0.48, 1); bg.inputs["Strength"].default_value = 0.55
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun); sun.data.energy = 4.5
fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN")); sc.collection.objects.link(fill); fill.data.energy = 1.2; fill.rotation_euler = (math.radians(70), 0, math.radians(150))
sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"
for v in VIEWS:
    tag, t, s_, yaw, pit = v.split(":")
    tv = mathutils.Vector([float(x) for x in t.split(",")])
    cam.data.ortho_scale = float(s_)
    ya, pa = math.radians(float(yaw)), math.radians(float(pit))
    # yaw 0 = the front (the character faces -Y), 90 = his left side (+X)
    cam.location = tv + mathutils.Vector((math.sin(ya) * math.cos(pa), -math.cos(ya) * math.cos(pa), math.sin(pa))) * 5
    cam.rotation_euler = (tv - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = "%s_%s.png" % (OUT, tag); bpy.ops.render.render(write_still=True)
