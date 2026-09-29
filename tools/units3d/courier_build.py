"""The courier rider (spec 2026-09-28-courier-art §2; the owner's design C4, zimage_C4_s2)
from the owner's Tripo 3D models, headless, in ONE command:

  blender -b --factory-startup --python tools/units3d/courier_build.py -- courier

What it builds, from what:
  1. the model (tools/units3d/courier/tripo.py, tripo_parts.csv): the owner's Tripo 3D
     courier, git-ignored in assets/units3d/ai_src/courier/tripo/courier/ - its 43 parts
     fitted onto its textured twin, turned to face +Y, the horse 2.45 m nose to tail on
     z = 0, hidden faces dropped, each part reduced to its budget (<= 20,000 tris in all),
     unwrapped into ONE 2048 atlas and baked from the textured mesh (colour, tangent
     normal, metal-roughness) on one material;
  2. the rig: the cavalry's horse bone NAMES placed on this horse, make_units' mounted
     rider names on the rider's parts, the staff (and its two-bone pennon) on the off
     hand, the case on the saddle; weighted part by part (verified: unweighted share
     < 1%);
  3. two actions (tools/units3d/courier/rig.py): GALLOP (a 24-frame loop at 24 fps, a
     four-beat transverse gallop) and IDLE (a 72-frame loop), keyed FK and baked through
     IK so the rider's feet stay in the irons; `stride_m`, the model metres one GALLOP
     loop covers, is measured off the near hind hoof and printed;
  4. the export: assets/units3d/courier.glb (the atlas embedded as JPEG; Godot extracts
     assets/units3d/courier_courier_atlas*.jpg beside it) and the "courier" entry of
     assets/units3d/units3d.json.

The rigged build is also saved to assets/units3d/ai_src/courier/courier_rigged_tripo.blend
for shots.
"""
import bpy, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
COURIER = os.path.join(HERE, "courier")
REPO = os.path.dirname(os.path.dirname(HERE))
if COURIER not in sys.path:
    sys.path.insert(0, COURIER)

TRIS_MAX = 20000           # the game budget for the whole piece
ATLAS_PX = 2048            # the one atlas
GALLOP_FRAMES = 24         # one gallop stride, a loop
IDLE_FRAMES = 72           # the standing loop
FPS = 24                   # the clips' frame rate
OUT = os.path.join(REPO, "assets", "units3d")
WORK = os.path.join(OUT, "ai_src", "courier")      # git-ignored: the owner's sources and the saved build
SOURCE_NOTE = "Tripo 3D (owner), from zimage_C4_s2, tools/units3d/courier_build.py"


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["courier"]
    code = argv[0] if argv else "courier"
    if code != "courier":
        raise SystemExit("courier_build.py builds the courier only (got %r)" % code)
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import rig, texture, tripo
    assert rig.GALLOP_FRAMES == GALLOP_FRAMES and rig.IDLE_FRAMES == IDLE_FRAMES and rig.FPS == FPS
    assert texture.ATLAS == ATLAS_PX
    mu, mc = rig.mu, rig.mc
    ob, arm, how, info = tripo.build()
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
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start, sc.frame_end = 0, IDLE_FRAMES

    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > TRIS_MAX:
        raise SystemExit("%d tris is over the %d budget" % (tris, TRIS_MAX))
    mats = len([m for m in ob.data.materials if m])
    if mats != 1:
        raise SystemExit("%d materials: the courier wears ONE" % mats)
    path = os.path.join(OUT, code + ".glb")
    mc.export_glb([arm, ob], path)
    mpath = os.path.join(OUT, "units3d.json")
    manifest = json.load(open(mpath))
    manifest[code] = {
        "label": "Courier", "kind": "mounted",
        "height_m": round(max(v.co.z for v in ob.data.vertices), 3),
        "source": SOURCE_NOTE,
        "tris": tris, "bones": len(arm.data.bones), "weights": how,
        "actions": {a.name[len(code) + 1:]: [int(a.frame_range[0]), int(a.frame_range[1])] for a in acts},
        "stride_m": round(stride, 3), "fps": FPS,
    }
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")
    print("EXPORTED %s  %d tris, %d bones, clips %s" % (path, tris, len(arm.data.bones),
                                                         sorted(manifest[code]["actions"])))
    blend = os.path.join(WORK, "courier_rigged_tripo.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print("SAVED", blend, round(time.time() - t0, 1), "s")


if __name__ == "__main__":
    main()
