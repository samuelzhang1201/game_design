"""The courier rider (spec 2026-09-28-courier-art §2; the owner's design C4, zimage_C4_s2)
from its sources, headless, in ONE command:

  blender -b --factory-startup --python tools/units3d/courier_build.py -- courier

What it builds, from what:
  1. the static model, courier v3 (tools/units3d/courier/rebuild_v3.py): the cavalry's
     CC0 Hunt Museum horse scan at 2.45 m, the CC0 Blender Human Base Meshes rider seated
     and dressed as the herald, the tack, clothes and props laid on them by ray casts,
     reduced to the game budget and baked into ONE 2048 atlas (colour with a light AO,
     tangent normals, metal-roughness) on one material; audited (<= 20,000 tris);
  2. the rig (tools/units3d/courier/rig.py): cavalry_scan's horse skeleton on the same
     scan plus make_units' mounted rider bones on the rider's own joints, a pole and a
     two-bone pennon on the saddle, the dispatch case on the saddle; skinned part by part
     (bone heat for horse and rider, verified: unweighted share < 1%);
  3. two actions: GALLOP (a 24-frame loop at 24 fps, a four-beat transverse gallop) and
     IDLE (a 72-frame loop), keyed FK and baked through IK so the rider's feet stay in
     the irons and his left fist on the staff; `stride_m`, the model metres one GALLOP
     loop covers, is measured off the near hind hoof and printed;
  4. the export: assets/units3d/courier.glb (the atlas embedded as JPEG; Godot extracts
     assets/units3d/courier_courier_atlas*.jpg beside it) and the "courier" entry of
     assets/units3d/units3d.json.

Sources (git-ignored, read where they are): assets/units3d/ai_src/courier/human_base_meshes/
(the bundle), the cavalry's scans (cavalry_scan.SRC), assets/flux/out/courier_tiles/
(the Z-Image material tiles). The rigged build is also saved to
assets/units3d/ai_src/courier/courier_rigged.blend for shots.
"""
import bpy, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
COURIER = os.path.join(HERE, "courier")
REPO = os.path.dirname(os.path.dirname(HERE))
if COURIER not in sys.path:
    sys.path.insert(0, COURIER)

MOUNT_TRIS = 5600          # the horse's share (texture_v3.BUDGET["horse"]), its scan detail baked as normals
RIDER_TRIS = 14000         # rider, head, fists, boots and every piece of tack, clothing and props together
                           # (texture_v3.BUDGET and the pieces' own sizes; the build stops over the sum)
ATLAS_PX = 2048            # the one atlas
GALLOP_FRAMES = 24         # one gallop stride, a loop
IDLE_FRAMES = 72           # the standing loop
FPS = 24                   # the clips' frame rate
OUT = os.path.join(REPO, "assets", "units3d")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["courier"]
    code = argv[0] if argv else "courier"
    if code != "courier":
        raise SystemExit("courier_build.py builds the courier only (got %r)" % code)
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import rebuild_v3, texture_v3, props_v3, rig
    assert rig.GALLOP_FRAMES == GALLOP_FRAMES and rig.IDLE_FRAMES == IDLE_FRAMES and rig.FPS == FPS
    assert texture_v3.ATLAS == ATLAS_PX and texture_v3.BUDGET["horse"] == MOUNT_TRIS
    ob, objs, PJ, head, audit = rebuild_v3.rebuild()
    if audit is not None and not audit["pass"]:
        raise SystemExit("audit failed: %s" % audit["fails"])
    mu, mc, cs = rig.mu, rig.mc, rig.cs

    surf = cs.Surface(objs["horse_high"])
    pole = props_v3.pole_axis()
    spec = rig.rig_spec(surf, PJ, pole, props_v3.CASE_C)
    arm = mu.build_armature(code, spec)
    parts = rig.split_parts(ob, texture_v3.PART_ORDER)
    how = rig.weigh(parts, arm, pole, props_v3.CASE_C, head)
    first = parts["horse"]
    rig.activate(first)
    for p in parts.values():
        p.select_set(True)
    bpy.context.view_layer.objects.active = first
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = ob.data.name = code
    ob.data.attributes.remove(ob.data.attributes["part_id"])
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    bare = mu.unweighted_share(ob, arm)
    print("WEIGHTS unweighted share %.3f%%  horse %s  rider %s" % (bare * 100, how["horse"], how["rider"]))
    if bare >= 0.01:
        raise SystemExit("%.2f%% of the courier is unweighted" % (bare * 100))
    mod = ob.modifiers.new("rig", "ARMATURE")
    mod.object = arm
    ob.parent = arm

    acts = rig.actions(arm)
    stride, sweep, frac = rig.stride_m(arm, acts[0])
    print("STRIDE_M %.3f  (hind hoof sweep %.3f m over %.3f of the loop)" % (stride, sweep, frac))
    rig.drop_helpers(arm, acts)
    mu.stash(arm, acts)
    for track in arm.animation_data.nla_tracks:
        track.name = track.name[len(code) + 1:]
        for s in track.strips:
            s.name = track.name
    for n in ("horse_high", "rider_high", "rider_hands_high"):
        o = bpy.data.objects.get(n)
        if o:
            bpy.data.objects.remove(o, do_unlink=True)
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 0, IDLE_FRAMES

    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > MOUNT_TRIS + RIDER_TRIS:
        raise SystemExit("%d tris is over the %d budget" % (tris, MOUNT_TRIS + RIDER_TRIS))
    path = os.path.join(OUT, code + ".glb")
    mc.export_glb([arm, ob], path)
    mpath = os.path.join(OUT, "units3d.json")
    manifest = json.load(open(mpath))
    manifest[code] = {
        "label": "Courier", "kind": "mounted",
        "height_m": round(max(v.co.z for v in ob.data.vertices), 3),
        "source": "CC0 Hunt Museum horse scan + CC0 Blender Human Base Meshes rider, the owner's design C4 "
                  "(zimage_C4_s2), tools/units3d/courier_build.py",
        "tris": tris, "bones": len(arm.data.bones), "weights": how,
        "actions": {a.name[len(code) + 1:]: [int(a.frame_range[0]), int(a.frame_range[1])] for a in acts},
        "stride_m": round(stride, 3), "fps": FPS,
    }
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")
    print("EXPORTED %s  %d tris, %d bones, clips %s" % (path, tris, len(arm.data.bones),
                                                         sorted(manifest[code]["actions"])))
    blend = os.path.join(rebuild_v3.WORK, "courier_rigged.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("SAVED", blend, round(time.time() - t0, 1), "s")


if __name__ == "__main__":
    main()
