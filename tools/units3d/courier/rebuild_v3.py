"""Rebuild courier model v3 (the static, textured model) from its sources, headless:

  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \\
      --python tools/units3d/courier/rebuild_v3.py

build_v3 (the scan horse, the seated base-mesh rider in costume, the tack, clothes and
props), texture_v3 (reduce, unwrap, paint, bake the 2048 atlas, join), the clean-up and
hard edges, the 3d-model-build-up skill's audit_game gate with max_materials=1 (skipped
with a warning when the skill is not installed), then — run as a script —
assets/units3d/ai_src/courier/courier_v3.blend and audit_v3.json (git-ignored), the atlas
PNGs in courier_v3_atlas/ beside them.

tools/units3d/courier_build.py imports `rebuild()` and carries on to the rig, the two
actions and the export.
"""
import bpy, os, sys, json, math, time, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
WORK = os.path.join(REPO, "assets", "units3d", "ai_src", "courier")    # git-ignored: sources and outputs
BLEND = os.path.join(WORK, "courier_v3.blend")
ATL = os.path.join(WORK, "courier_v3_atlas")
SKILL = os.path.expanduser("~/.claude/skills/3d-model-build-up/scripts/quadkit.py")


def clean(ob):
    """The decimated scans leave a few flaws: exact duplicates, a wire edge, edges with
    3+ faces. Then hard edges by angle (60 deg) and smooth shading."""
    import bmesh
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context="EDGES")
    extra = set()
    for e in bm.edges:
        if len(e.link_faces) > 2:
            fs = sorted(e.link_faces, key=lambda f: f.calc_area(), reverse=True)
            extra.update(fs[2:])
    bmesh.ops.delete(bm, geom=list(extra), context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_edges], context="VERTS")
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_area() < 1e-12], context="FACES")
    print("CLEAN removed faces", len(extra))
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(60):
            e.smooth = False
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(ob.data); bm.free()


def audit(ob):
    if not os.path.exists(SKILL):
        print("AUDIT skipped: no", SKILL)
        return None
    spec = importlib.util.spec_from_file_location("quadkit", SKILL)
    qk = importlib.util.module_from_spec(spec); spec.loader.exec_module(qk)
    return qk.audit_game(ob, budget_tris=20000, max_materials=1, need_uv=True)


def rebuild():
    """Build and texture the static model into the current (factory, empty) file.
    Returns (ob, objs, PJ, head, audit_result)."""
    t0 = time.time()
    os.makedirs(ATL, exist_ok=True)
    import build_v3, texture_v3, tack_v3
    objs, PJ = build_v3.build()
    print("BUILT", round(time.time() - t0, 1))
    head = tack_v3.head_frame(objs["horse_high"])
    ob, _ = texture_v3.run(objs, head, ATL, PJ)
    print("TEXTURED", round(time.time() - t0, 1))
    clean(ob)
    for n in ("horse_high", "rider_high", "rider_hands_high"):
        o = bpy.data.objects.get(n)
        if o:
            o.hide_render = True
            o.hide_set(True)
    r = audit(ob)
    if r is not None:
        co = [v.co for v in ob.data.vertices]
        rep = {"audit": r, "parts_tris": texture_v3.PART_TRIS,
               "bounds": {k: [round(min(c[i] for c in co), 3), round(max(c[i] for c in co), 3)]
                          for i, k in enumerate("xyz")}}
        json.dump(rep, open(os.path.join(WORK, "audit_v3.json"), "w"), indent=1, default=str)
        print("AUDIT", json.dumps({k: r[k] for k in ("pass", "fails", "notes", "tris", "materials")}, default=str))
    print("PARTS", texture_v3.PART_TRIS)
    return ob, objs, PJ, head, r


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rebuild()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("SAVED", BLEND)
