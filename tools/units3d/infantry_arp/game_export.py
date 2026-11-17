"""Install build: the ARP short-sword + round-shield soldier as THE infantry piece
(docs/superpowers/specs/2026-11-16-infantry-arp-shortsword-design.md; the knight before it:
2026-10-19-infantry-arp-knight-design.md).

Source (git-ignored): assets/3D/model_wip/blender_output/infantry/infantry_shortsword_shield.blend
(rig `rig`, body `Infantry_body`, gear `Weapon` / `Shield` bone-parented to cc_weapon.r / .l).
Headless, nothing saved:
  Blender -b -y SOURCE.blend --python tools/units3d/infantry_arp/game_export.py -- ROOT [OUT.json]
or exec() in a Blender with the file open, then install(ROOT). Works on copies.
For a complete pivot build, pass the solved sample JSON and its reference seconds (4.0) as
install(ROOT, pivot_samples=PATH, pivot_seconds=SECONDS). The samples come from the coupled author
mapping: pivot_native.gd captures MARCH, pivot_mapping.py builds the cases, pivot_solve.gd solves
them (the committed solve is in tests/fixtures/infantry_pivot_mapping.json; test_pivot_mapping.py
re-bakes it onto the installed GLB byte for byte, so no Blender is needed for a pivot-only change).
The pivot bake never changes the original five clips or binds.

What the map needs of the infantry GLB (a plain export of the rig does not give it):
- the node names infantry.tscn overrides: armature `inf_rig`, one skinned mesh `infantry`;
- ONE material on a 2048 atlas whose files keep the infantry's names
  (`infantry_infantry_atlas{,_mr,_n}.jpg`): the body in the lower-left 3/4, the sword and the shield
  in the right-hand strip; the gear merged into the mesh, wholly on its socket bone;
- rest = the guard stance (GARRISON's first frame): the map sizes a piece from its rest mesh;
- the looping clips closed (last frame = first), ATTACK_VAR1's and ATTACK_2's lunges taken out (in place);
- the measured `stride_m` and `steps` of the MARCH for army_art.csv (returned).
"""
import json
import math
import os
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

# Shipped clips (owner 2026-11-16). The other batch-2 clips (BLOCK*, HIT*, DEATH*, TURN_*, RUN*,
# ADVANCE*, GARRISON_2, DEFEND_2/3) wait for their runtime hooks; helper actions never ship.
GAME = {"WALK": "MARCH", "IDLE": "GARRISON", "STANDBY": "STANDBY", "DEFEND": "DEFEND",
        "ATTACK": "ATTACK", "SLASH": "SLASH", "ATTACK_VAR1": "ATTACK_VAR1", "ATTACK_2": "ATTACK_2",
        "SLASH_2": "SLASH_2", "SLASH_3": "SLASH_3"}
LOOPS = {"WALK", "IDLE", "STANDBY", "DEFEND"}
IN_PLACE = {"ATTACK_VAR1", "ATTACK_2"}   # Mixamo lunges: 1.82 m forward / 2.17 m forward-left
# Foot locking (owner 2026-11-16: re-author MARCH's ground contacts, as the archers' and cavalry's
# were): in the retargeted in-place walk a planted sole does not travel back at one speed (the
# right toe slid 48 mm through its push-off), which the locomotion certifier fails. Each frame the
# deepest sole vertices of a foot in stance are made to travel straight back at the walk's own
# median planted speed; the foot is moved by the accumulated difference (its orientation kept), the
# thigh and shin follow by two-bone IK in their own bend plane, and the offset eases back to zero
# through the swing. A foot in the first half of its swing is also lifted until its lowest point clears `clear_m` (the
# retargeted walk drags the right toe forward through its push-off and skims the ground in early
# swing), the lift eased over neighbouring frames. The upper body, arms and gear are untouched.
LOCK = {"WALK": {"legs": [(s, "thigh_twist" + s, "thigh_stretch" + s, "leg_stretch" + s, "leg_twist" + s,
                           "foot" + s, "toes_01" + s) for s in (".l", ".r")],
                 "stance_m": 0.004, "deep_m": 0.002, "clear_m": 0.005, "ease_frames": 3, "min_knee_deg": 2.0}}
BODY = "Infantry_body"
GEAR = {"sword": "Weapon", "shield": "Shield"}
REST = ("IDLE", 1)                       # the guard stance, GARRISON's first frame
RENAME = {"head.x": "head"}
ATLAS = 2048
# (u0, v0, du, dv) of each part in the atlas, v up as in Blender's UVs and image rows
REGION = {"body": (0.0, 0.0, 0.75, 0.75), "sword": (0.75, 0.0, 0.25, 0.5),
          "shield": (0.75, 0.5, 0.25, 0.5)}
SOCKET = {"sword": "cc_weapon.r", "shield": "cc_weapon.l"}
SEAM_FRAMES = 6                          # a loop's last frames that absorb its seam residual
# The game atlas's metallic (B) as a share of the authored map: on the map's light a near-pure metal
# mirrors the dark ground and woods round it and reads black; x0.45 keeps the steel lit grey with
# its sheen (bracketed x0.3 / x0.45 / x0.6 in real-window shots, 2026-10-19; the old knight sat at 0.27).
GAME_METAL = 0.45
# The shield's wood in the game atlas: planks and rim drawn to `shield_contrast` of their spread
# about the mean colour (one ochre plank stood out), then `shield_tone` (saturation share, value share; POLISH). The Tripo wood is new, bright
# orange (the archers' tabard and roof tiles' hue); (0.55, 0.8) weathered it for the knight's carry,
# but held up at rest it read as black discs on the map and (0.9, 1.2) as chalky discs brighter
# than the banner (critics 2026-11-17); (1.25, 0.95) after the spread is the knight's warm mid-brown.
# Owner 2026-11-17 polish (critic of the first install). Each knob is overridable for a bracketed
# review through the INFANTRY_POLISH environment variable (a JSON object of the keys below).
# - Rest: STANDBY's relaxed body keeps the guard's shield arm (GARRISON's left arm, shoulder to the
#   shield socket, same phase), pinned at its own shoulder and turned `rest_arm_turn` of the way from
#   the guard's twisted chest to the figure's facing; the wrist then tilts the shield's face at least
#   `rest_shield_up_deg` above level, so a regiment at rest shows a ring of lit, raised shields from
#   the map's height instead of shields hanging edge-on.
# - Shield hand: the retargeted grip laid the thumb along the handle, past the index (a raised
#   thumb in every clip, plainest in the strikes); each frame the thumb chain turns about its base
#   until its tip rests at `thumb_tip` in the hand's frame (over the curled index's middle joint).
# - MARCH: the sword leans out of the body's mid-plane by at least `blade_min_deg` (a smooth floor
#   `blade_soft_deg` wide, the wrist turning): the hanging blade passed close to the knee. (A floor
#   on its forward pitch laid it along the front shin; one measured in the side-to-vertical plane
#   tipped it onto the front shoe when it pointed forward.)
# - Mail (class 2 of the authored `textures/body_class.npy`) at play zoom read as dark speckle: in it
#   the colour keeps `mail_albedo` of its ring contrast against a `mail_blur_px` box blur, the normal
#   `mail_normal` of its relief, the roughness `mail_rough` of its variation plus `mail_rough_add`.
POLISH = {"rest_arm": True, "rest_arm_turn": 0.8, "rest_shield_up_deg": 30.0,
          "shield_tone": (1.25, 0.95), "shield_contrast": 0.55, "thumb_tip": (0.042, 0.09, -0.045),
          "blade_min_deg": 30.0, "blade_soft_deg": 8.0,
          "mail_blur_px": 3, "mail_albedo": 0.25, "mail_normal": 0.12, "mail_rough": 0.3,
          "mail_rough_add": 0.3}
THUMB = ("thumb1.l", "c_thumb2.l", "c_thumb3.l")


def _set_action(rig, name):
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    rig.animation_data.action_slot = act.slots[0]
    return act


def _keep(src):
    keep = [b.name for b in src.data.bones if b.use_deform] + ["cc_weapon.l", "cc_weapon.r"]
    parents = {}
    for n in keep:
        p = src.data.bones[n].parent
        while p and p.name not in keep:
            p = p.parent
        parents[n] = p.name if p else None
    return keep, parents


def _skeleton(src, keep, parents, rest):
    data = bpy.data.armatures.new("inf_rig")
    rig = bpy.data.objects.new("inf_rig", data)
    bpy.context.scene.collection.objects.link(rig)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for n in keep:
        b = data.edit_bones.new(RENAME.get(n, n))
        b.length = max(src.data.bones[n].length, 0.02)
        b.matrix = rest[n]
        b.use_deform = not n.startswith("cc_weapon")
    for n, p in parents.items():
        if p:
            data.edit_bones[RENAME.get(n, n)].parent = data.edit_bones[RENAME.get(p, p)]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def _region_uv(obj, part):
    u0, v0, du, dv = REGION[part]
    uv = obj.data.uv_layers.active.data
    co = np.zeros(len(uv) * 2)
    uv.foreach_get("uv", co)
    co = co.reshape(-1, 2)
    assert co.min() > -1e-3 and co.max() < 1 + 1e-3, (part, co.min(), co.max())
    co = np.c_[u0 + np.clip(co[:, 0], 0, 1) * du, v0 + np.clip(co[:, 1], 0, 1) * dv]
    uv.foreach_set("uv", co.ravel())
    obj.data.uv_layers.active.name = "UVMap"


def _mesh(src, rig):
    """The body posed into the rest pose (its armature applied), the gear set where it hangs."""
    vl = bpy.context.view_layer
    body0 = bpy.data.objects[BODY]
    body = body0.copy(); body.data = body0.data.copy()
    bpy.context.scene.collection.objects.link(body)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    body.select_set(True); vl.objects.active = body
    mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    bpy.ops.object.modifier_apply(modifier=mod.name)
    body.parent = None
    body.matrix_world = Matrix.Identity(4)
    _region_uv(body, "body")
    parts = [body]
    for part, name in GEAR.items():
        g0 = bpy.data.objects[name]
        g = g0.copy(); g.data = g0.data.copy()
        bpy.context.scene.collection.objects.link(g)
        mw = g0.matrix_world.copy()
        g.parent = None
        g.data.transform(mw)
        g.matrix_world = Matrix.Identity(4)
        g.vertex_groups.clear()
        g.vertex_groups.new(name=SOCKET[part]).add(range(len(g.data.vertices)), 1.0, "REPLACE")
        _region_uv(g, part)
        parts.append(g)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in parts:
        o.select_set(True)
    vl.objects.active = body
    bpy.ops.object.join()
    body.name = "infantry"; body.data.name = "infantry"
    for old, new in RENAME.items():
        if old in body.vertex_groups:
            body.vertex_groups[old].name = new
    mat = bpy.data.materials.new("infantry_atlas_mat")
    body.data.materials.clear()
    body.data.materials.append(mat)
    for p in body.data.polygons:
        p.material_index = 0
    body.modifiers.clear()
    m = body.modifiers.new("Skin", "ARMATURE"); m.object = rig
    body.parent = rig
    body.matrix_parent_inverse.identity()
    return body, mat


def _pixels(img, w, h):
    c = img.copy(); c.scale(w, h)
    a = np.array(c.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(c)
    return a


def _box(a, r):
    """Box blur of radius r px over the first two axes (edges clamped)."""
    for axis in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis)
        hi = np.take(c, range(2 * r + 1, c.shape[axis]), axis=axis)
        lo = np.take(c, range(0, c.shape[axis] - 2 * r - 1), axis=axis)
        a = (hi - lo) / (2 * r + 1)
    return a


def _mail_mask(w, h):
    """The authored chain-mail class (2) of the body's maps, resampled to w x h, rows bottom-up as
    Blender's pixels, edges softened."""
    cls = np.load(Path(bpy.data.filepath).parent / "textures/body_class.npy")[::-1]
    ys = (np.arange(h) * cls.shape[0]) // h
    xs = (np.arange(w) * cls.shape[1]) // w
    return _box((cls[ys][:, xs] == 2).astype(np.float32), 2)[..., None]


def _calm_mail(kind, px, mask, cfg):
    """Mail at play zoom: less ring contrast, flatter relief, steadier roughness (POLISH)."""
    r = int(cfg["mail_blur_px"])
    if kind == "albedo":
        c = px[..., :3]; b = _box(c, r)
        px[..., :3] = c + mask * ((b + (c - b) * cfg["mail_albedo"]) - c)
    elif kind == "n":
        xy = 0.5 + (px[..., :2] - 0.5) * cfg["mail_normal"]
        v = np.concatenate([xy * 2 - 1, (px[..., 2:3] * 2 - 1)], -1)
        v[..., 2:3] = np.sqrt(np.clip(1 - (v[..., :2] ** 2).sum(-1, keepdims=True), 0, 1))
        px[..., :3] = px[..., :3] + mask * ((v + 1) / 2 - px[..., :3])
    elif kind == "mr":
        g = px[..., 1:2]; b = _box(g, r)
        calm = np.clip(b + (g - b) * cfg["mail_rough"] + cfg["mail_rough_add"], 0, 1)
        px[..., 1:2] = g + mask * (calm - g)
    return px


def _atlases(mat, out_dir):
    """Colour, metal-rough (G roughness, B metallic) and normal atlases, written as the infantry's
    files and wired into the one material (the GLB embeds them; the scene's override uses the files)."""
    def src(name, suffix):
        # every source map is <part>_{base,mr,normal}.png (body: the authored body_*.png, README)
        m = bpy.data.objects[name].data.materials[0]
        found = [n.image for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image
                 and Path(n.image.filepath).stem.endswith("_" + suffix)]
        assert len(found) == 1, (name, suffix, found)
        return found[0]
    parts = {"body": BODY, **GEAR}
    sources = {kind: {part: src(obj, suffix) for part, obj in parts.items()}
               for kind, suffix in (("albedo", "base"), ("mr", "mr"), ("n", "normal"))}
    files = {}
    cfg, mask = _polish_cfg(), None
    for kind, parts in sources.items():
        atlas = np.zeros((ATLAS, ATLAS, 4), np.float32)
        atlas[..., 3] = 1
        if kind == "n":
            atlas[..., :3] = (0.5, 0.5, 1.0)
        for part, img in parts.items():
            u0, v0, du, dv = REGION[part]
            w, h = int(du * ATLAS), int(dv * ATLAS)
            x, y = int(u0 * ATLAS), int(v0 * ATLAS)
            if img is not None:
                atlas[y:y + h, x:x + w] = _pixels(img, w, h)
            if part == "body":
                if mask is None:
                    mask = _mail_mask(w, h)
                atlas[y:y + h, x:x + w] = _calm_mail(kind, atlas[y:y + h, x:x + w], mask, cfg)
            if kind == "albedo" and part == "shield":
                r = atlas[y:y + h, x:x + w, :3]
                lum = r.mean(2, keepdims=True)
                tone = cfg["shield_tone"]
                m = r.reshape(-1, 3).mean(0)          # planks and rim drawn closer in colour first
                r = m + (r - m) * cfg["shield_contrast"]
                lum = r.mean(2, keepdims=True)
                atlas[y:y + h, x:x + w, :3] = (lum + (r - lum) * tone[0]) * tone[1]
        if kind == "mr":
            atlas[..., 2] *= GAME_METAL
        # the image is named as the old GLB named it; Godot extracts it beside the .glb as
        # "<glb>_<image>" = the infantry_infantry_atlas*.jpg the scene's material reads (and never
        # overwrites them: this build writes those files itself)
        name = "infantry_atlas" + ("" if kind == "albedo" else "_" + kind)
        im = bpy.data.images.new(name, ATLAS, ATLAS, alpha=False)
        if kind != "albedo":
            im.colorspace_settings.name = "Non-Color"
        im.pixels.foreach_set(atlas.ravel())
        path = str(Path(out_dir) / ("infantry_" + name + ".jpg"))
        im.filepath_raw = path
        im.file_format = "JPEG"
        bpy.context.scene.render.image_settings.quality = 92
        im.save(filepath=path, quality=92)
        im.pack()                                # the exporter names an image by its FILE: give it
        im.filepath_raw = name + ".jpg"          # the old GLB's name, read from the packed copy
        files[kind] = im
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = files["albedo"]
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = files["mr"]
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(t.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = files["n"]
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(t.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return {k: str(Path(out_dir) / ("infantry_" + v.name + ".jpg")) for k, v in files.items()}


LOCKED = {}


def _foot_points(src, foot, toe):
    """Each vertex skinned mostly to the foot or toe bone, in that bone's rest frame (rigid)."""
    body = bpy.data.objects[BODY]
    groups = {g.index: g.name for g in body.vertex_groups}
    out = []
    for v in body.data.vertices:
        if not v.groups:
            continue
        g = max(v.groups, key=lambda e: e.weight)
        name = groups.get(g.group)
        if name in (foot, toe):
            out.append((name, src.data.bones[name].matrix_local.inverted() @ v.co))
    return out


def _turn(a, b):
    """The shortest rotation taking direction a to direction b, as a 4x4 matrix."""
    return a.normalized().rotation_difference(b.normalized()).to_matrix().to_4x4()


def _lock_feet(src, clip, poses):
    cfg = LOCK.get(clip)
    if not cfg:
        return {}
    n = len(poses) - 1                    # unique frames (the last is the first again)
    report = {}
    legs = []
    for side, hip, hip2, knee, knee2, foot, toe in cfg["legs"]:
        pts = _foot_points(src, foot, toe)
        world = [np.array([list(poses[f][b] @ c) for b, c in pts]) for f in range(n)]
        low = min(w[:, 2].min() for w in world)
        legs.append((side, hip, hip2, knee, knee2, foot, toe, world, low))
    # the walk's own planted speed: median back-travel of the deepest vertices of a planted foot
    speeds = []
    for *_, world, low in legs:
        for f in range(n):
            a, b = world[f], world[(f + 1) % n]
            if a[:, 2].min() <= low + cfg["stance_m"] and b[:, 2].min() <= low + cfg["stance_m"]:
                deep = a[:, 2] <= a[:, 2].min() + cfg["deep_m"]
                speeds.append(float(np.median(b[deep, 1] - a[deep, 1])))
    v = float(np.median(speeds))
    for side, hip, hip2, knee, knee2, foot, toe, world, low in legs:
        # in stance: near the ground and travelling back at least half the walk speed (the right toe
        # drags forward through its push-off, and the early swing skims the ground)
        def back(f):
            a, b = world[f], world[(f + 1) % n]
            deep = a[:, 2] <= a[:, 2].min() + cfg["deep_m"]
            return float(np.mean(b[deep, 1] - a[deep, 1])) > 0.5 * v
        stance = [world[f][:, 2].min() <= low + cfg["stance_m"] and back(f) and back((f - 1) % n)
                  for f in range(n)]
        # offset[f]: what the foot must move by at frame f (x, y), integrated through each stance
        off = [Vector((0.0, 0.0, 0.0)) for _ in range(n)]
        start = next(f for f in range(n) if stance[f] and not stance[f - 1])
        acc = Vector((0.0, 0.0, 0.0))
        for k in range(1, n + 1):
            f, prev = (start + k) % n, (start + k - 1) % n
            if stance[f] and stance[prev]:
                a, b = world[prev], world[f]
                deep = a[:, 2] <= a[:, 2].min() + cfg["deep_m"]
                d = b[deep].mean(axis=0) - a[deep].mean(axis=0)
                acc = acc + Vector((-d[0], v - d[1], 0.0))
            elif not stance[f]:
                acc = Vector((0.0, 0.0, 0.0))
            off[f] = acc.copy() if stance[f] else None
        # ease each stance's final offset back to zero through the swing that follows
        f = start
        for _ in range(n):
            if off[f] is None:
                a = (f - 1) % n
                while off[a] is None:
                    a = (a - 1) % n
                z = f
                while off[z % n] is None:
                    z += 1
                span = z - a
                for g in range(a + 1, z):
                    u = (g - a) / span
                    off[g % n] = off[a] * (1 - (u * u * (3 - 2 * u)))
                f = z % n
            f = (f + 1) % n
        # swing lift: each swing frame raised to clear_m, spread to its neighbours on a cos^2 falloff
        # only the first half of each swing (toe-off and early swing): a landing foot is left alone
        early = [False] * n
        f = start
        for _ in range(n):
            if not stance[f] and stance[(f - 1) % n]:
                run = [f]
                while not stance[(run[-1] + 1) % n]:
                    run.append((run[-1] + 1) % n)
                for g in run[:(len(run) + 1) // 2]:
                    early[g] = True
            f = (f + 1) % n
        need = [max(0.0, cfg["clear_m"] - float(world[f][:, 2].min())) if early[f] else 0.0 for f in range(n)]
        e = cfg["ease_frames"]
        for f in range(n):
            if stance[f]:
                continue
            lift = 0.0
            for g in range(n):
                k = min((f - g) % n, (g - f) % n)
                if need[g] > 0 and k <= e:
                    lift = max(lift, need[g] * math.cos(0.5 * math.pi * k / (e + 1)) ** 2)
            off[f] = off[f] + Vector((0.0, 0.0, lift))
        report[side + "_max_lift_m"] = round(max(o.z for o in off), 4)
        worst = pull = 0.0
        for f in range(n):
            d = off[f]
            if d.length < 1e-9:
                continue
            worst = max(worst, d.length)
            pose = poses[f]
            h = pose[hip].translation.copy()
            k0 = pose[knee].translation.copy()
            a0 = pose[foot].translation.copy()
            a1 = a0 + d
            l1, l2 = (k0 - h).length, (a0 - k0).length
            # the new knee: same bend plane side, lengths kept. A pinned target past the leg's
            # reach is pulled back to it, the knee kept bent at least min_knee_deg: a clamped
            # straight knee left the foot up to 3 mm off the shin and the leg on its singular pose.
            axis = (a1 - h)
            reach = math.sqrt(l1 * l1 + l2 * l2 + 2 * l1 * l2 * math.cos(math.radians(cfg["min_knee_deg"])))
            dist = min(axis.length, reach)
            axis.normalize()
            pull = max(pull, (a1 - (h + axis * dist)).length)
            a1 = h + axis * dist
            d = a1 - a0
            bend = (k0 - h) - axis * (k0 - h).dot(axis)
            bend.normalize()
            along = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
            k1 = h + axis * along + bend * math.sqrt(max(l1 * l1 - along * along, 0.0))
            r1 = Matrix.Translation(h) @ _turn(k0 - h, k1 - h) @ Matrix.Translation(-h)
            r2 = Matrix.Translation(k1) @ _turn(a0 - k0, a1 - k1) @ Matrix.Translation(-k0)
            for b in (hip, hip2):
                pose[b] = r1 @ pose[b]
            for b in (knee, knee2):
                pose[b] = r2 @ pose[b]
            for b in (foot, toe):
                pose[b] = Matrix.Translation(d) @ pose[b]
        report[side] = {"max_offset_m": round(worst, 4), "max_reach_pullback_m": round(pull, 4)}
    for b in poses[0]:
        poses[-1][b] = poses[0][b].copy()
    report["speed_m_per_frame"] = round(v, 6)
    return report


POLISHED = {}
DONOR = {}


def _polish_cfg():
    cfg = dict(POLISH)
    cfg.update(json.loads(os.environ.get("INFANTRY_POLISH", "{}")))
    return cfg


def _under(src, keep, bone):
    """`bone` and every kept bone below it."""
    return [n for n in keep if n == bone or bone in (b.name for b in src.data.bones[n].parent_recursive)]


def _graft(poses, donor, anchor, names, pin=None, turn=0.0):
    """Each pose's `names` become the donor's at the same phase, carried on `anchor` (armature
    space). With `pin`, the carry's rotation is eased by `turn` (0..1) from the anchor's toward
    none (the donor's own facing on the figure) and `pin`'s origin stays the pose's own."""
    n, m = len(poses), len(donor)
    for i, p in enumerate(poses):
        d = donor[round(i * (m - 1) / max(n - 1, 1))]
        carry = p[anchor] @ d[anchor].inverted()
        if pin:
            q = carry.to_quaternion().slerp(Quaternion(), turn)
            r = q.to_matrix().to_4x4()
            carry = Matrix.Translation(p[pin].translation) @ r @ Matrix.Translation(-d[pin].translation)
        for b in names:
            p[b] = carry @ d[b]


def _floor(poses, hand, names, socket, local, toward, lo_deg, soft_deg):
    """Turn the wrist (`names` about `hand`'s origin) so the socket's `local` direction leans toward
    the armature direction `toward` by at least a smooth floor of lo_deg (its angle off the plane
    normal to `toward`), turning in the plane of the two. Returns the largest turn in degrees."""
    lo, w = math.radians(lo_deg), math.radians(soft_deg)
    worst = 0.0
    for p in poses:
        v = (p[socket].to_3x3() @ local).normalized()
        a = math.asin(max(-1.0, min(1.0, v.dot(toward))))
        d = (lo - a + math.sqrt((a - lo) ** 2 + w * w)) / 2       # smooth max(a, lo) - a
        o = p[hand].translation.copy()
        r = Matrix.Translation(o) @ Matrix.Rotation(d, 4, v.cross(toward).normalized()) @ Matrix.Translation(-o)
        for n in names:
            p[n] = r @ p[n]
        worst = max(worst, d)
    return round(math.degrees(worst), 1)


def _shield_face(src):
    """The shield's outer face normal in its socket's frame (the disc's least axis, pointing away
    from the grip), from the rest pose."""
    _set_action(src, REST[0]); bpy.context.scene.frame_set(REST[1]); bpy.context.view_layer.update()
    sock = src.pose.bones[SOCKET["shield"]].matrix.inverted() @ src.matrix_world.inverted()
    ob = bpy.data.objects[GEAR["shield"]]
    pts = np.array([list(sock @ (ob.matrix_world @ v.co)) for v in ob.data.vertices])
    c = pts.mean(0)
    n = np.linalg.svd(pts - c)[2][2]
    return Vector(n if np.dot(n, c) > 0 else -n)


def _fold_thumb(src, poses, tip_in_hand):
    """Turn the shield hand's thumb chain about its base so its tip lands on `tip_in_hand`."""
    length = src.data.bones[THUMB[-1]].length
    worst = 0.0
    for p in poses:
        head = p[THUMB[0]].translation.copy()
        tip = p[THUMB[-1]] @ Vector((0.0, length, 0.0))
        q = (tip - head).rotation_difference(p["hand.l"] @ tip_in_hand - head)
        r = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head)
        for n in THUMB:
            p[n] = r @ p[n]
        worst = max(worst, q.angle)
    return round(math.degrees(worst), 1)


def _polish(src, keep, clip, poses):
    cfg = _polish_cfg()
    out = {}
    if clip == "STANDBY" and cfg["rest_arm"]:
        if "IDLE" not in DONOR:
            DONOR["IDLE"] = _poses(src, keep, "IDLE")
        arm = ["shoulder.l", "c_arm_twist_offset.l", "arm_stretch.l", "forearm_stretch.l",
               "forearm_twist.l"] + _under(src, keep, "hand.l")
        _graft(poses, DONOR["IDLE"], "spine_03.x", arm, "shoulder.l", cfg["rest_arm_turn"])
        out["rest_arm"] = len(arm)
        if cfg["rest_shield_up_deg"] is not None:
            out["rest_shield_max_turn_deg"] = _floor(
                poses, "hand.l", _under(src, keep, "hand.l"), SOCKET["shield"], _shield_face(src),
                Vector((0.0, 0.0, 1.0)), cfg["rest_shield_up_deg"], cfg["blade_soft_deg"])
    if cfg["thumb_tip"] is not None and clip in GAME:
        out["thumb_max_turn_deg"] = _fold_thumb(src, poses, Vector(cfg["thumb_tip"]))
    if clip == "WALK" and cfg["blade_min_deg"] is not None:
        out["blade_max_bend_deg"] = _floor(poses, "hand.r", _under(src, keep, "hand.r"), SOCKET["sword"],
                                           Vector((0.0, 1.0, 0.0)), Vector((-1.0, 0.0, 0.0)),
                                           cfg["blade_min_deg"], cfg["blade_soft_deg"])
    if out:
        POLISHED[clip] = out


def _poses(src, keep, clip):
    scn = bpy.context.scene
    act = _set_action(src, clip)
    f0, f1 = map(int, act.frame_range)
    poses = []
    for f in range(f0, f1 + 1):
        scn.frame_set(f)
        poses.append({n: src.pose.bones[n].matrix.copy() for n in keep})
    if clip in IN_PLACE:
        travel = poses[-1]["root.x"].translation - poses[0]["root.x"].translation
        travel.z = 0.0
        for i, p in enumerate(poses):
            shift = travel * (i / (len(poses) - 1))
            for m in p.values():
                m.translation -= shift
    if clip in LOOPS:
        # Close the loop by spreading only the seam residual (first pose vs last) over the last
        # frames: these clips already end on their first pose (WALK 0.8 mm, IDLE 0.7 deg apart), so
        # lerping whole frames toward frame 1 would drag a planted foot across its touchdown.
        n = len(poses)
        fix = {b: poses[0][b] @ poses[-1][b].inverted() for b in poses[0]}
        for k in range(SEAM_FRAMES):
            i = n - SEAM_FRAMES + k
            w = (k + 1) / SEAM_FRAMES
            poses[i] = {b: Matrix.Identity(4).lerp(fix[b], w) @ m for b, m in poses[i].items()}
    _polish(src, keep, clip, poses)
    LOCKED[clip] = _lock_feet(src, clip, poses)
    return poses


def _key(rig, keep, poses, game):
    rig.animation_data_create()
    act = bpy.data.actions.new("game_" + game)
    rig.animation_data.action = act
    for frame, pose in enumerate(poses):  # from 0: the clip starts on its first key (no held frame)
        for pb in rig.pose.bones:
            src_name = next(k for k in keep if RENAME.get(k, k) == pb.name)
            rest = pb.bone.matrix_local
            if pb.parent:
                psrc = next(k for k in keep if RENAME.get(k, k) == pb.parent.name)
                rel = pb.parent.bone.matrix_local.inverted() @ rest
                pb.matrix_basis = rel.inverted() @ pose[psrc].inverted() @ pose[src_name]
            else:
                pb.matrix_basis = rest.inverted() @ pose[src_name]
            for path in ("location", "rotation_quaternion", "scale"):
                pb.keyframe_insert(path, frame=frame, group=pb.name)
    track = rig.animation_data.nla_tracks.new()
    track.name = game
    track.strips.new(game, 0, act)
    rig.animation_data.action = None


def _march_measure(src, poses, keep):
    """stride_m: the planted foot's travel per frame (median, model metres) times the loop's frames;
    steps: the shares where a foot comes down (its height reaches the ground band)."""
    z = {s: np.array([p["foot" + s].translation.z for p in poses]) for s in (".l", ".r")}
    y = {s: np.array([p["foot" + s].translation.y for p in poses]) for s in (".l", ".r")}
    n = len(poses)
    planted, steps = [], []
    for s in (".l", ".r"):
        lo = z[s].min()
        down = z[s] < lo + 0.012
        for i in range(1, n):
            if down[i] and down[i - 1]:
                planted.append(abs(y[s][i] - y[s][i - 1]))
            if down[i] and not down[i - 1]:
                steps.append(round((i) / (n - 1), 2))
    return {"stride_m": round(float(np.median(planted)) * (n - 1), 3), "steps": sorted(steps),
            "frames": n}


def install(root, pivot_samples=None, pivot_seconds=None):
    assert (pivot_samples is None) == (pivot_seconds is None), "pivot samples and seconds are a pair"
    if pivot_samples is not None:
        assert type(pivot_seconds) in (int, float) and math.isfinite(pivot_seconds) and pivot_seconds > 0
    root = Path(root)
    out = root / "assets/3D/units/infantry"
    scn = bpy.context.scene
    src = bpy.data.objects["rig"]
    keep, parents = _keep(src)
    _set_action(src, REST[0]); scn.frame_set(REST[1]); bpy.context.view_layer.update()
    rest = {n: src.pose.bones[n].matrix.copy() for n in keep}
    rig = _skeleton(src, keep, parents, rest)
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    _set_action(src, REST[0]); scn.frame_set(REST[1]); bpy.context.view_layer.update()
    body, mat = _mesh(src, rig)
    files = _atlases(mat, out)
    info = {"files": files, "clips": {}}
    for clip, game in GAME.items():
        poses = _poses(src, keep, clip)
        _key(rig, keep, poses, game)
        info["clips"][game] = {"source": clip, "frames": len(poses),
                               "loop": clip in LOOPS, "in_place": clip in IN_PLACE}
        if clip == "WALK":
            info["march"] = _march_measure(src, poses, keep)
            info["march"]["lock"] = LOCKED.get(clip)
    info["polish"] = {"config": _polish_cfg(), "clips": POLISHED}
    rig.rotation_euler.z = math.pi           # Blender -Y -> glTF +Z; the game's figures face -Z
    bpy.context.view_layer.update()
    for o in bpy.context.selected_objects:
        o.select_set(False)
    rig.select_set(True); body.select_set(True)
    bpy.context.view_layer.objects.active = rig
    target = out / "infantry.glb"
    if pivot_samples is not None:
        target = out / "model_wip/pivot_export/source.glb"
        target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(target), export_format="GLB", use_selection=True,
                              export_yup=True, export_skins=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_def_bones=False, export_optimize_animation_size=False,
                              export_image_format="JPEG", export_jpeg_quality=92)
    if pivot_samples is not None:
        import importlib.util
        try:
            spec = importlib.util.spec_from_file_location("infantry_pivot", root / "tools/units3d/soldier_arp/pivot.py")
            pivot = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(pivot)
            info["pivots"] = pivot.bake(target, pivot_samples, out / "infantry.glb", pivot_seconds)
        finally:
            target.unlink(missing_ok=True)
    me = body.data
    me.calc_loop_triangles()
    lo = min(v.co.z for v in me.vertices); hi = max(v.co.z for v in me.vertices)
    info.update(tris=len(me.loop_triangles), bones=len(rig.data.bones), height_m=round(hi - lo, 3))
    return info


if __name__ == "__main__":
    import sys
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    result = install(argv[0])
    text = json.dumps(result, indent=1, default=str)
    if len(argv) > 1:
        Path(argv[1]).write_text(text)
    print("INFANTRY_EXPORT", text)
