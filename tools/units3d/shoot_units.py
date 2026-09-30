"""Photograph the BUILT units — the .glb on disk, not the scene that made it,
so a shot is also proof the export round-trips its skeleton and its actions.

  blender -b --factory-startup --python tools/units3d/shoot_units.py -- OUTDIR [CODE ...]

Writes one contact sheet per unit (rest, two garrison beats, three attack
beats, from two angles) and an mp4 of each action.
"""

import bpy, json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unit_common import OUT, rows, clear, log

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["/tmp"]
OUTDIR = argv[0]
WANTED = set(argv[1:])
W, H = 480, 620


def set_engine(scene):
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            return
        except TypeError:
            continue


def stage(height):
    scene = bpy.context.scene
    set_engine(scene)
    scene.render.resolution_x, scene.render.resolution_y = W, H
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Filmic" if "Filmic" in [
        v.name for v in scene.view_settings.bl_rna.properties["view_transform"].enum_items
    ] else scene.view_settings.view_transform

    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.20, 0.21, 0.23, 1.0)
    bg.inputs["Strength"].default_value = 1.1
    scene.world = world

    key = bpy.data.lights.new("key", "SUN")
    key.energy = 4.5
    key.angle = math.radians(6)
    ko = bpy.data.objects.new("key", key)
    scene.collection.objects.link(ko)
    ko.rotation_euler = (math.radians(52), 0.0, math.radians(35))

    fill = bpy.data.lights.new("fill", "AREA")
    fill.energy = 220.0
    fill.size = 6.0
    fo = bpy.data.objects.new("fill", fill)
    scene.collection.objects.link(fo)
    fo.location = (-4.0, -4.0, height * 1.2)
    fo.rotation_euler = (math.radians(65), 0.0, math.radians(-45))

    # A floor for the figure to stand on and cast onto.
    bpy.ops.mesh.primitive_plane_add(size=40.0)
    floor = bpy.context.active_object
    m = bpy.data.materials.new("floor")
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (0.26, 0.25, 0.22, 1.0)
    b.inputs["Roughness"].default_value = 0.95
    floor.data.materials.append(m)

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 55.0
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def aim(cam, yaw_deg, height, span):
    """Put the camera on a yaw around the unit, framing its whole height.

    Yaw 0 is dead FRONT, which for these units is the +Y side: they are
    authored facing +Y, because that is the axis the glTF exporter turns
    into glTF's own forward. A camera parked on -Y photographs their backs,
    which is what the first pass of this sheet did.
    """
    # Frame the WHOLE unit: the distance comes from the lens and the unit's
    # own height, not a guessed multiplier — at 85 mm the spear and the lance
    # were cut off at the top of every shot.
    fov = 2.0 * math.atan(18.0 / cam.data.lens)
    reach = max(height, span * 1.6) * 1.18
    d = (reach * 0.5) / math.tan(fov * 0.5)
    a = math.radians(yaw_deg)
    cz = height * 0.55
    cam.location = (math.sin(a) * d, math.cos(a) * d, cz)
    drop = math.atan2(cz - height * 0.48, d)
    cam.rotation_euler = (math.radians(90.0) - drop, 0.0,
                          math.radians(180.0 - yaw_deg))


def find_actions(arm):
    out = {}
    for tr in (arm.animation_data.nla_tracks if arm.animation_data else []):
        for st in tr.strips:
            if st.action:
                out[st.action.name.split("|")[-1].upper()] = st.action
    for act in bpy.data.actions:
        out.setdefault(act.name.split("|")[-1].upper(), act)
    return out


def bind(arm, act):
    ad = arm.animation_data or arm.animation_data_create()
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    ad.action = act
    if hasattr(ad, "action_slot") and getattr(act, "slots", None):
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass


def tile(paths, cols, path):
    """Lay the shots out in a grid — one sheet reads far faster than six files."""
    import numpy as np
    imgs = [bpy.data.images.load(p) for p in paths]
    rows_n = (len(imgs) + cols - 1) // cols
    sheet = np.zeros((H * rows_n, W * cols, 4), dtype=np.float32)
    sheet[:, :, 3] = 1.0
    for i, im in enumerate(imgs):
        a = np.array(im.pixels[:], dtype=np.float32).reshape(H, W, 4)
        r, c = rows_n - 1 - i // cols, i % cols
        sheet[r * H:(r + 1) * H, c * W:(c + 1) * W] = a
    out = bpy.data.images.new("sheet", W * cols, H * rows_n, alpha=False)
    out.pixels[:] = sheet.reshape(-1)
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()


def main():
    with open(os.path.join(OUT, "units3d.json")) as f:
        manifest = json.load(f)
    for row in rows():
        code = row["code"]
        if WANTED and code not in WANTED:
            continue
        glb = os.path.join(OUT, code, code + ".glb")
        if not os.path.exists(glb) or code not in manifest:
            continue
        info = manifest[code]
        clear()
        bpy.context.scene.render.fps = info["fps"]
        bpy.ops.import_scene.gltf(filepath=glb)
        arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
        if not arms:
            raise RuntimeError("no armature came back out of " + glb)
        arm = arms[0]
        acts = find_actions(arm)
        log("%s actions in the file: %s" % (code, sorted(acts)))

        height = info["height_m"]
        span = height * (0.9 if info["kind"] == "mounted" else 0.4)
        cam = stage(height)

        shots = []
        # A mounted unit's attack is a REAR — a pitch about the horse's own
        # width axis, which a front-on camera foreshortens to almost nothing.
        # It is shot from the side, where it is the whole of the pose.
        side = 90 if info["kind"] == "mounted" else 35
        plan = [("GARRISON", 1, 35), ("GARRISON", 61, 35), ("GARRISON", 61, -55)]
        a0, a1 = info["actions"]["ATTACK"]
        plan += [("ATTACK", a0 + int((a1 - a0) * 0.18), side),
                 ("ATTACK", a0 + int((a1 - a0) * 0.45), side),
                 ("ATTACK", a0 + int((a1 - a0) * 0.65), side)]
        for i, (act_name, frame, yaw) in enumerate(plan):
            act = acts.get(act_name)
            if act is None:
                raise RuntimeError("%s lost its %s action" % (code, act_name))
            bind(arm, act)
            bpy.context.scene.frame_set(frame)
            aim(cam, yaw, height, span)
            p = os.path.join(OUTDIR, "%s_shot%d.png" % (code, i))
            bpy.context.scene.render.filepath = p
            bpy.ops.render.render(write_still=True)
            shots.append(p)
        tile(shots, 3, os.path.join(OUTDIR, "%s_sheet.png" % code))
        log("%s sheet written" % code)

        # and the motion itself, as a strip of frames. This Blender is built
        # without FFMPEG, so the frames are written out and stitched into one
        # long PNG rather than an mp4.
        for act_name in ("GARRISON", "ATTACK", "MARCH"):
            bind(arm, acts[act_name])
            f0, f1 = info["actions"][act_name]
            aim(cam, side if act_name in ("ATTACK", "MARCH") else 35, height, span)
            frames = []
            step = max(1, (f1 - f0) // (int(os.environ.get("UNIT_STRIP", "7"))))
            if os.environ.get("UNIT_RANGE"):
                parts = os.environ["UNIT_RANGE"].split(":")
                f0, f1 = int(parts[0]), int(parts[1])
                step = int(parts[2]) if len(parts) > 2 else 1
            for fr in range(f0, f1 + 1, step):
                bpy.context.scene.frame_set(fr)
                p = os.path.join(OUTDIR, "%s_%s_f%03d.png" % (code, act_name.lower(), fr))
                bpy.context.scene.render.filepath = p
                bpy.ops.render.render(write_still=True)
                frames.append(p)
            tile(frames, len(frames) if len(frames) <= 8 else 4,
                 os.path.join(OUTDIR, "%s_%s_strip.png" % (code, act_name.lower())))
            log("%s %s strip written (%d frames)" % (code, act_name, len(frames)))


main()
