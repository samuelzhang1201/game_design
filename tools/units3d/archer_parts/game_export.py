"""Install build of the archers' figure: the owner's parts Tripo archer (2026-11-27) on the infantry's rig
contract, exported by the infantry's exporter (tools/units3d/infantry_arp/game_export.py) with the archer's
clips and gear (README beside this file).

Source (git-ignored): assets/3D/model_wip/blender_output/archer/arc_longbow.blend (rig `rig`, body
`Infantry_body` with the face attribute `part` = the Tripo part id, gear `Bow` on cc_weapon.l with its string
on the hook bone cc_bow_string, `Arrow` on cc_arrow (scale 0 = not drawn), `Quiver` on spine_02.x; every map
`<object>_{base,mr,normal}.png` in textures/).
Headless, nothing saved:
  Blender -b -y SOURCE.blend --python tools/units3d/archer_parts/game_export.py -- ROOT [OUT.json]
Writes ROOT/assets/3D/units/archers/: archers.glb (armature `inf_rig`, one skinned mesh `archers`),
archers_archers_atlas{,_mr,_n}.jpg and archers_tunic_mask.png (the realm tint: the gambeson's faces).
"""
import importlib.util
import json
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector, kdtree

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("infantry_game_export", HERE.parent / "infantry_arp/game_export.py")
inf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inf)

FPS = 30
inf.UNIT = "archers"
inf.BODY_CLASSES = False
# source action -> game clip. The map plays MARCH, GARRISON, STANDBY and ATTACK (Map3DUnits.clip_named; DEFEND
# falls back to GARRISON); the rest ship for the battle hooks still to come.
inf.GAME = {"WALK": "MARCH", "AIM": "GARRISON", "IDLE": "STANDBY", "SHOOT": "ATTACK", "DRAW": "DRAW",
            "RUN": "SPRINT", "HIT": "HIT", "HIT_2": "HIT_2", "HIT_3": "HIT_3", "DODGE": "DODGE",
            "DODGE_L": "DODGE_L", "DODGE_R": "DODGE_R", "DEATH": "DEATH"}
inf.LOOPS = {"WALK", "AIM", "IDLE", "SHOOT", "RUN"}
inf.IN_PLACE = set()                     # the dodges step out and come back; DEATH keeps its fall
inf.REST = ("IDLE", 1)                   # standing, the bow down: the map sizes a piece from its rest mesh
# The retargeted Mixamo walk (37 frames, 36 unique): a sole travels back at the walk's speed over frames 13-31
# (left) and 27-12 (right, wrapping), but the right is lifted 40 mm mid-stance (29-34) and the left drags forward on
# the ground before it lifts (31-34), so a height test cuts the stances apart: the windows are authored from the
# back-travel (shares of the 36 unique frames).
inf.ARM_LOCK = {**inf.ARM_LOCK, "archers": {"WALK": {"stance": {".l": (12 / 36, 31 / 36), ".r": (26 / 36, 12 / 36)}}}}
inf.GEAR = {"bow": "Bow", "quiver": "Quiver", "arrow": "Arrow"}
inf.SOCKET = {"bow": "cc_weapon.l", "quiver": "spine_02.x", "arrow": "cc_arrow"}
STRING_BONE = "cc_bow_string"
# (u0, v0, du, dv): the body in the lower-left 3/4, the bow and the quiver in the right strip, the arrow on top
inf.REGION = {"body": (0.0, 0.0, 0.75, 0.75), "bow": (0.75, 0.0, 0.25, 0.5), "quiver": (0.75, 0.5, 0.25, 0.5),
              "arrow": (0.0, 0.75, 0.75, 0.25)}
inf.POLISH = {**inf.POLISH, "thumb_tip": None}   # the infantry's shield-hand thumb fold: not on a bow hand
TINT_PARTS = (0, 10, 12)                 # the Tripo parts of the gambeson: body and skirt, both sleeves
MASK_MARGIN_PX = 6

_keep0, _skeleton0, _mesh0 = inf._keep, inf._skeleton, inf._mesh


def _keep(src):
    keep, parents = _keep0(src)
    for n in (STRING_BONE, "cc_arrow"):
        keep.append(n)
        p = src.data.bones[n].parent
        while p and p.name not in keep:
            p = p.parent
        parents[n] = p.name if p else None
    return keep, parents


def _skeleton(src, keep, parents, rest):
    # the arrow is scaled to 0 (not drawn) in the rest pose: its rest is the source bone's own
    rest = dict(rest)
    rest["cc_arrow"] = src.matrix_world.inverted() @ src.matrix_world @ src.data.bones["cc_arrow"].matrix_local
    rig = _skeleton0(src, keep, parents, rest)
    return rig


def _mesh(src, rig):
    """The infantry's join (the bow rigid on its socket), then the string skinned as the source's hook moves it:
    each vertex w to the string bone and 1 - w to the socket, w its weight in the hook's group `DEF-string` (the
    hook is a full-strength blend by that group, so this two-bone skin is the same deformation)."""
    bow = bpy.data.objects["Bow"]
    hook = next(m for m in bow.modifiers if m.type == "HOOK")
    assert hook.subtarget == STRING_BONE and hook.strength == 1.0 and hook.falloff_radius == 0.0, hook.name
    gi = bow.vertex_groups[hook.vertex_group].index
    mw = bow.matrix_world
    string = [(mw @ v.co, g.weight) for v in bow.data.vertices for g in v.groups if g.group == gi and g.weight > 0.0]
    # The gear is joined where it hangs in the rest frame, where the arrow is scaled to 0 (not drawn): joined so,
    # it is a point. It is joined where its bone's own rest puts it (`_skeleton` binds the bone there).
    arrow = bpy.data.objects[inf.GEAR["arrow"]]
    bone = src.data.bones[arrow.parent_bone]
    hang = (arrow.parent, arrow.parent_type, arrow.parent_bone, arrow.matrix_parent_inverse.copy(), arrow.matrix_basis.copy())
    at_rest = src.matrix_world @ bone.matrix_local @ Matrix.Translation((0.0, bone.length, 0.0)) \
        @ arrow.matrix_parent_inverse @ arrow.matrix_basis
    arrow.parent = None
    arrow.matrix_world = at_rest
    bpy.context.view_layer.update()
    try:
        body, mat = _mesh0(src, rig)
    finally:
        arrow.parent, arrow.parent_type, arrow.parent_bone = hang[:3]
        arrow.matrix_parent_inverse, arrow.matrix_basis = hang[3], hang[4]
    tree = kdtree.KDTree(len(body.data.vertices))
    for v in body.data.vertices:
        tree.insert(v.co, v.index)
    tree.balance()
    sock = body.vertex_groups[inf.SOCKET["bow"]]
    g = body.vertex_groups.get(STRING_BONE) or body.vertex_groups.new(name=STRING_BONE)
    for p, w in string:
        hit = [i for _, i, _ in tree.find_range(p, 1e-6)]   # every copy of a vertex split by a UV seam
        assert hit, p
        g.add(hit, w, "REPLACE")
        if w < 1.0:
            sock.add(hit, 1.0 - w, "REPLACE")
        else:
            sock.remove(hit)
    return body, mat


HIDDEN_SCALE = 1e-3       # the arrow's scale while not drawn: under a millimetre, and still invertible
_poses0 = inf._poses


def _poses(src, keep, clip):
    """The source hides the arrow by scaling it to 0; a singular key fails the pivot solver's transform check
    (Map3DInfantryPivot `_affine`), so the hidden arrow is kept at HIDDEN_SCALE instead."""
    poses = _poses0(src, keep, clip)
    for pose in poses:
        loc, rot, sca = pose["cc_arrow"].decompose()
        if min(sca) < HIDDEN_SCALE:
            sca = Vector([max(s, HIDDEN_SCALE) for s in sca])
            pose["cc_arrow"] = Matrix.LocRotScale(loc, rot, sca)
    return poses


inf._keep, inf._skeleton, inf._mesh, inf._poses = _keep, _skeleton, _mesh, _poses
inf._blade_leg_gap = lambda src, poses: None     # no blade: the bow stays in the left fist


def _raster(tris, size):
    out = np.zeros((size, size), bool)
    for t in tris:
        x0, y0 = np.floor(t.min(0)).astype(int)
        x1, y1 = np.ceil(t.max(0)).astype(int)
        x0, y0, x1, y1 = max(x0 - 1, 0), max(y0 - 1, 0), min(x1 + 1, size - 1), min(y1 + 1, size - 1)
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        e = [(t[j][0] - t[i][0]) * (gy - t[i][1]) - (t[j][1] - t[i][1]) * (gx - t[i][0]) for i, j in ((0, 1), (1, 2), (2, 0))]
        tol = 0.75 * max(float(np.abs(t[1] - t[0]).max()), float(np.abs(t[2] - t[1]).max()), 1.0)
        inside = ((e[0] >= -tol) & (e[1] >= -tol) & (e[2] >= -tol)) | ((e[0] <= tol) & (e[1] <= tol) & (e[2] <= tol))
        out[y0:y1 + 1, x0:x1 + 1] |= inside
    return out


def _grow(a):
    out = a.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            out |= np.roll(a, (dy, dx), (0, 1))
    return out


def tunic_mask():
    """The realm tint's mask (rows bottom-up, 0..1): the gambeson's faces where the body sits in the atlas, grown by
    the bake's margin without entering another part's island, softened outward only (the militia's rule)."""
    me = bpy.data.objects[inf.BODY].data
    fp = np.zeros(len(me.polygons), np.int32)
    me.attributes["part"].data.foreach_get("value", fp)
    uv = np.zeros(len(me.loops) * 2)
    me.uv_layers.active.data.foreach_get("uv", uv)
    u0, v0, du, dv = inf.REGION["body"]
    uv = (np.array([u0, v0]) + uv.reshape(-1, 2) * np.array([du, dv])) * inf.ATLAS
    me.calc_loop_triangles()
    cloth, other = [], []
    for t in me.loop_triangles:
        (cloth if int(fp[t.polygon_index]) in TINT_PARTS else other).append(uv[list(t.loops)])
    m, o = _raster(np.array(cloth), inf.ATLAS), _raster(np.array(other), inf.ATLAS)
    o &= ~m
    faces = o.copy()
    for _ in range(MASK_MARGIN_PX):
        m, o = m | (_grow(m) & ~o), o | (_grow(o) & ~m)
    soft = np.maximum(inf.tunic_mask.box(m.astype(np.float32), 2), m.astype(np.float32))
    soft = np.where(faces, 0.0, soft).astype(np.float32)
    # grown and softened, the mask must not cross into the gear's strips (the bow would take the realm's colour)
    inside = np.zeros_like(soft)
    y0, x0 = int(v0 * inf.ATLAS), int(u0 * inf.ATLAS)
    inside[y0:y0 + int(dv * inf.ATLAS), x0:x0 + int(du * inf.ATLAS)] = 1.0
    return soft * inside


def _tunic_luminance(albedo_jpg, mask):
    im = bpy.data.images.load(str(albedo_jpg), check_existing=False)
    px = np.array(im.pixels[:], dtype=np.float32).reshape(im.size[1], im.size[0], 4)[..., :3]
    bpy.data.images.remove(im)
    lin = np.where(px <= 0.04045, px / 12.92, ((px + 0.055) / 1.055) ** 2.4)
    return round(float((lin @ np.array([0.2126, 0.7152, 0.0722]))[mask > 0.5].mean()), 3)


def install(root):
    scn = bpy.context.scene
    scn.render.fps, scn.render.fps_base = FPS, 1.0
    mask = tunic_mask()
    info = inf.install(root)
    out = Path(root) / "assets/3D/units" / inf.UNIT
    (out / (inf.UNIT + "_tunic_mask.png")).write_bytes(inf.tunic_mask.png_gray(mask))
    info["tunic_mask"] = {"coverage": round(float((mask > 0.5).mean()), 4),
                          "tunic_luminance": _tunic_luminance(info["files"]["albedo"], mask)}
    return info


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    result = install(argv[0])
    text = json.dumps(result, indent=1, default=str)
    if len(argv) > 1:
        Path(argv[1]).write_text(text)
    print("ARCHERS_EXPORT", text)
