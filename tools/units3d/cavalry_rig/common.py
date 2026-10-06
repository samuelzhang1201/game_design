"""The cavalry re-rigged and re-animated the way the king was (owner 2026-10-06: 请使用 royal_rig_work
类似的方法，重新设计 cavalry 骑兵的动作 -- the existing game mesh, the five lance clips). The royal
rig's helpers are exec'd first, then this file points them at the cavalry:

    G = {}
    for f in ("royal_rig/common", "cavalry_rig/common", ...):
        G["__file__"] = ".../tools/units3d/%s.py" % f; exec(open(G["__file__"]).read(), G)

Source: the game mesh `cavalry` of assets/3D/units/cavalry/model_wip/tripo/cavalry_tripo_work.blend
(69 Tripo parts + the hand-built lance and back shield, one 2048 atlas, ~19k tris), every vertex
carrying `tripo_part` (the part id; -1 the shield, -2 the lance) -- the labels come with it.
"""
ROOT = "/Users/samuelzhang/game_design/"
CAV = ROOT + "assets/3D/units/cavalry/model_wip/"
SRC_BLEND = CAV + "tripo/cavalry_tripo_work.blend"
SRC = CAV + "rig/"
WORK = SRC + "cavalry_rig_work.blend"
SHOTS = SRC + "shots/"
SCENE = "Cavalry_Rig"
PARTS_CSV = ROOT + "tools/units3d/cavalry_tripo/tripo_parts.csv"
MESH_NAME = "cavalry"
RIG_NAME = "cavalry_rig"


def mesh():
    return bpy.data.objects[MESH_NAME]


def load():
    """The game mesh appended into its own scene, unparented, its old skin dropped, turned to the
    skill's frame: the cavalry faced +Y with its right at +X; turned half round it faces -Y with
    its left at +X. Hooves stay on z = 0."""
    sc = scene()
    old = bpy.data.objects.get(MESH_NAME)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
        dst.objects = [MESH_NAME]
    o = dst.objects[0]
    coll("Cavalry_Mesh").objects.link(o)
    for x in [p for p in bpy.data.objects if p.name.startswith("cavalry_rig") and p.type == "ARMATURE"]:
        bpy.data.objects.remove(x, do_unlink=True)
    o.parent = None
    for m in list(o.modifiers):
        o.modifiers.remove(m)
    o.vertex_groups.clear()
    o.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
    o.matrix_world = Matrix.Identity(4)
    o.data.update()
    V = co(o)
    return {"verts": len(V), "tris": tris(o), "min": [round(float(x), 3) for x in V.min(0)],
            "max": [round(float(x), 3) for x in V.max(0)], "materials": [m.name for m in o.data.materials]}
