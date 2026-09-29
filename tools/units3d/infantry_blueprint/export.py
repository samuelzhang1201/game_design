"""EXPORT the textured blueprint man-at-arms to the game (owner 2026-09-29: 生成美观的步兵模型并应用到游戏中).

  blender -b infantry_blueprint_textured.blend --python export.py -- OUT_DIR [--manifest]

The figure was built facing -Y; the game's contract (tools/units3d/README.md) is +Y, so the
mesh and the armature are turned 180 degrees about Z in their DATA (an action's keys are in
each bone's own frame, so they turn with it). GARRISON and MARCH go down onto muted NLA
tracks, one glTF animation each (model_cavalry.export_glb). Prints the MARCH loop's stride —
the ground a planted foot covers in one loop — for data/army_art.csv's stride_m, and with
--manifest writes assets/units3d/units3d.json's entry.
"""
import bpy, json, math, os, sys
from mathutils import Matrix, Vector

sys.path.insert(0, "/Users/samuelzhang/game_design/tools/units3d")
import model_cavalry as mc
import make_units as mu

args = sys.argv[sys.argv.index("--") + 1:]
OUT = args[0]
NAME = "infantry"

rig = bpy.data.objects["inf_rig"]
ob = bpy.data.objects[NAME]


def stride(action):
    """Metres of ground one loop of `action` carries the figure: the speed a planted foot
    slides back (the loop is walked in place), times the loop's length."""
    rig.animation_data.action = action
    f0, f1 = int(action.frame_range[0]), int(action.frame_range[1])
    sc = bpy.context.scene
    speeds = []
    for sd in ("L", "R"):
        pts = []
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            pts.append((rig.matrix_world @ rig.pose.bones["foot." + sd].head).copy())
        low = min(p.z for p in pts)
        for a, b in zip(pts, pts[1:]):
            if a.z < low + 0.006 and b.z < low + 0.006:
                speeds.append(abs(b.y - a.y))
    speeds.sort()
    v = speeds[len(speeds) // 2] if speeds else 0.0
    return v * (f1 - f0)


def spear_upright(acts):
    """At rest the spear lay straight out before the fist (the blueprint's A-pose), and the game
    measures a piece's half width off its REST mesh (Map3DUnits.model_size): the man read 1.8 m
    wide. The spear bone and its vertices are turned upright about the bone's head, and every
    key of the spear bone re-baked so each frame's spear stands exactly where it stood."""
    import bmesh
    from mathutils import Quaternion
    sc = bpy.context.scene
    pb = rig.pose.bones["spear"]
    keep = {}
    for act in acts:
        rig.animation_data.action = act
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            keep[(act.name, f)] = pb.matrix.copy()
    rig.animation_data.action = None
    sc.frame_set(1)
    g = ob.vertex_groups["spear"].index
    idx = [v.index for v in ob.data.vertices if any(e.group == g and e.weight > 0.5 for e in v.groups)]
    head = rig.data.bones["spear"].head_local.copy()
    far = max((ob.data.vertices[i].co for i in idx), key=lambda c: (c - head).length)
    axis = (far - head).normalized()
    q = axis.rotation_difference(Vector((0, 0, 1)) if axis.z >= 0 else Vector((0, 0, -1)))
    turn = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head)
    bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
    bmesh.ops.transform(bm, matrix=turn, verts=[bm.verts[i] for i in idx])
    bm.to_mesh(ob.data); bm.free(); ob.data.update()
    mc.activate(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones["spear"]
    eb.matrix = turn @ eb.matrix
    bpy.ops.object.mode_set(mode="OBJECT")
    for act in acts:
        rig.animation_data.action = act
        bags = [act] if hasattr(act, "fcurves") else \
            [cb for layer in act.layers for strip in layer.strips for cb in strip.channelbags]   # Blender 5: layered actions
        for bag in bags:
            for fc in [fc for fc in bag.fcurves if 'pose.bones["spear"]' in fc.data_path]:
                bag.fcurves.remove(fc)
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            pb.matrix = keep[(act.name, f)]
            bpy.context.view_layer.update()
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
    rig.animation_data.action = None
    sc.frame_set(1)
    print("spear upright: %d vertices turned %.0f deg" % (len(idx), math.degrees(q.angle)))


def main():
    acts = [bpy.data.actions[n] for n in ("GARRISON", "MARCH")]
    step = stride(bpy.data.actions["MARCH"])
    spear_upright(acts)
    rig.animation_data.action = None
    bpy.context.scene.frame_set(1)
    turn = Matrix.Rotation(math.pi, 4, "Z")
    rig.data.transform(turn)
    ob.data.transform(turn)
    ob.data.update()
    mc.activate(ob)
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    mu.stash(rig, acts)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, NAME + ".glb")
    mc.export_glb([rig, ob], path)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    zs = sorted(v.co.z for v in ob.data.vertices)
    body = [v.co.z for v in ob.data.vertices if v.co.z < 1.95]        # the figure, not the spear above it
    h = round(max(body), 3)
    print("EXPORTED %s: %d tris, %d bones, figure %.3f m, MARCH stride %.3f m" % (path, tris, len(rig.data.bones), h, step))
    if "--manifest" in args:
        mpath = os.path.join(OUT, "units3d.json")
        manifest = json.load(open(mpath))
        manifest[NAME] = {
            "label": "Man-at-arms", "kind": "humanoid", "height_m": h,
            "source": "hand-built from the owner's blueprint (assets/flux/out/infantry_kit/blueprint), textured with the "
                      "owner's material swatches (infantry_kit/D), tools/units3d/infantry_blueprint/",
            "tris": tris, "bones": len(rig.data.bones), "weights": "rigid plates + distance",
            "actions": {a.name: [int(a.frame_range[0]), int(a.frame_range[1])] for a in acts},
            "fps": bpy.context.scene.render.fps, "stride_m": round(step, 3),
        }
        with open(mpath, "w") as f:
            json.dump(manifest, f, indent=1, sort_keys=True)
            f.write("\n")


main()
