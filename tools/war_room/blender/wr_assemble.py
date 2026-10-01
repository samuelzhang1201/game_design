# WR: this folder in the checkout the owner's Blender reads (set it before exec; see README.md)
WR = globals().get("WR", "/Users/samuelzhang/game_design/tools/war_room/blender")
exec(open(WR + "/wr_lib.py").read())
sc = bpy.data.scenes["WarRoomArt"]
C = coll("WR_assembly")
for o in list(C.objects):
    bpy.data.objects.remove(o, do_unlink=True)

def inst(src, name, loc, rot_z=0.0):
    o = bpy.data.objects.new(name, src.data)
    o.location = loc
    o.rotation_euler = (0, 0, rot_z)
    C.objects.link(o)
    return o

cs = bpy.data.objects["candlestick"]
for i, (gx, gz) in enumerate(((-0.8, -0.6), (0.8, -0.6), (-0.8, 0.6), (0.8, 0.6))):
    inst(cs, "A_candle%d" % i, G(gx, -0.045, gz), rot_z=0.3 * i)
pn = bpy.data.objects["pennant"]
for i, (gx, gz) in enumerate(((-0.2, 0.1), (0.15, -0.12), (0.32, 0.22))):
    inst(pn, "A_pennant%d" % i, G(gx, 0.0, gz), rot_z=0.7 * i)
rk = bpy.data.objects["rake"]
inst(rk, "A_rake", G(0.25, 0.0, -0.05), rot_z=0.35)

# stand-ins: the sheet and the index chart (the game draws its own)
def plane(name, w, d, loc, rgb, tilt=0.0):
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in ((-w / 2, -d / 2, 0), (w / 2, -d / 2, 0), (w / 2, d / 2, 0), (-w / 2, d / 2, 0))]
    bm.faces.new(vs)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.append(mat_flat("A_" + name, rgb, rough=0.9))
    o = bpy.data.objects.new(name, me); o.location = loc; o.rotation_euler = (tilt, 0, 0)
    C.objects.link(o)
plane("A_sheet", 1.4, 1.01, G(0, -0.002, 0), (0.62, 0.52, 0.36))
plane("A_chart", 0.8, 0.29, G(0, 0.018, -0.725), (0.70, 0.62, 0.46), tilt=math.radians(5))

# lights: candle glow near each corner pair, a cool window light, faint ambient
for n in [o.name for o in C.objects if o.type == 'LIGHT']:
    pass
def light(name, kind, loc, energy, rgb, rot=None, size=0.05):
    ld = bpy.data.lights.get(name) or bpy.data.lights.new(name, kind)
    ld.energy = energy; ld.color = rgb
    try:
        ld.shadow_soft_size = size
    except Exception:
        pass
    o = bpy.data.objects.new(name, ld); o.location = loc
    if rot:
        o.rotation_euler = rot
    C.objects.link(o)
for i, (gx, gz) in enumerate(((-0.8, -0.6), (0.8, -0.6), (-0.8, 0.6), (0.8, 0.6))):
    light("A_candleL%d" % i, 'POINT', G(gx, 0.36, gz), 9.0, (1.0, 0.68, 0.38))
light("A_sconceL0", 'POINT', G(-1.25, 1.05, -1.9), 6.0, (1.0, 0.66, 0.36))
light("A_sconceL1", 'POINT', G(1.25, 1.05, -1.9), 6.0, (1.0, 0.66, 0.36))
light("A_window", 'SUN', G(0, 2, 0), 1.2, (0.75, 0.83, 1.0), rot=(math.radians(50), 0, math.radians(180)))

# the game camera: (0, 1.26, 0.99) looking at the table centre, fov 40 (vertical)
cd = bpy.data.cameras.get("A_gamecam") or bpy.data.cameras.new("A_gamecam")
cd.sensor_fit = 'VERTICAL'; cd.angle = math.radians(40); cd.clip_start = 0.01
cam = bpy.data.objects.new("A_gamecam", cd)
C.objects.link(cam)
cam.location = G(0, 1.26, 0.99)
d = (Vector((0, 0, 0)) - cam.location).normalized()
cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
sc.camera = cam
sc.render.resolution_x, sc.render.resolution_y = 1600, 900
if sc.world is None:
    w = bpy.data.worlds.new("A_world"); sc.world = w
sc.world.use_nodes = True
bg = next(n for n in sc.world.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs[0].default_value = (0.02, 0.016, 0.012, 1); bg.inputs[1].default_value = 1.0
print("assembled", [o.name for o in C.objects])
