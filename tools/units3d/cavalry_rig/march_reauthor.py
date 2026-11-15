"""LOCO-CAV-MARCH (owner ruling 2026-11-13, "Re-author cavalry MARCH"): the canter re-keyed so a
planted hoof holds the ground between keys. Exec'd in the owner's Blender AFTER the helpers the
README lists (royal_rig/* then cavalry_rig/*), on a copy of cavalry_rig_work.blend:

    G["__file__"] = ".../cavalry_rig/march_reauthor.py"; exec(open(G["__file__"]).read(), G)
    G["march_dense"](); G["export_march"]("/path/cavalry_march_dense.glb")

What was wrong (measured on the shipped clip): the generator keys 16 frames, and a 3- or 4-bone leg
whose fetlock follows a straight stance path, keyed at its ends, leaves that path between the keys
when Godot interpolates each bone's rotation (93 mm per-vertex slide at the canter's true 2.4 m loop,
10.8 mm at the keys alone). And `op_aim` turns the hoof by the least rotation from wherever the leg
left it, so a planted hoof rolls 3-4 degrees about its own axis through the stance.

And op_gait's swing (a smoothstep) starts and ends at rest in the model frame, so at lift-off a hoof
still inside the 0.5 mm planting band jumps to the body's speed over the ground and skates.

What changes, the gait only, everything else the same functions of u:
  * KEYS_PER_FRAME keys per original frame (128 over the same 0.5333 s, at 240 fps), so the in-between
    error falls with the square of the spacing (the .import's animation/fps must be 240 too: Godot
    re-bakes every clip at that rate);
  * the hoof's orientation is the least rotation from its REST frame to the generator's own aim
    direction (`op_hoof`): identical direction, no roll carried in, so a planted hoof is rigid;
  * the swing is a Hermite curve whose end slopes are the stance's travel (`swing`): the hoof keeps
    going back a little after lift-off and reaches forward before it lands, at zero ground speed at
    both ends; the fold is the generator's sin (FOLD_POWER).
Stance path, lift heights, timing and every other bone are the generator's. The loop still closes
(u = 0 and 1 are the same pose) and every other clip is untouched (only MARCH is transplanted,
`march_transplant.py`).
"""
KEYS_PER_FRAME = 8
FOLD_POWER = 1  # the generator's fold; 2 (eased in) left a lifting hoof dangling toe-down (critic 2026-11-13)
DENSE_FPS = 30 * KEYS_PER_FRAME


def op_hoof(a, bone, d):
    """The hoof bone given the rest frame turned by the least rotation onto `d` (armature space)."""
    pb = a.pose.bones[bone]
    rest = pb.bone.matrix_local.to_3x3()
    R = (rest.col[1].normalized().rotation_difference(Vector(d).normalized()).to_matrix() @ rest).to_4x4()
    R.translation = pb.matrix.translation
    pb.matrix = R
    _upd()


def swing(k, half, back):
    """The swing's fore-aft offset from home at k in 0..1: a cubic Hermite from +half to -half whose
    end slopes are the stance's own backward travel `back` (per unit k), so the hoof's world
    velocity is zero at lift-off and at touchdown (op_gait's smoothstep stopped it dead, and a hoof
    still in the planting band skated forward at the body's speed)."""
    h00, h10 = 2 * k ** 3 - 3 * k ** 2 + 1, k ** 3 - 2 * k ** 2 + k
    h01, h11 = -2 * k ** 3 + 3 * k ** 2, k ** 3 - k ** 2
    return h00 * half + (h10 + h11) * back - h01 * half


def op_gait_rigid(a, u, stride=STRIDE, lift=1.0):
    """op_gait's canter, the same stance path, lift and fold, with the swing by `swing` and each hoof set
    by op_hoof."""
    for hoof, ph in CANTER.items():
        kind, s = ("Front" if hoof.startswith("Front") else "Hind"), hoof[-1]
        cb = a.data.bones[kind + "Cannon." + s]
        home = Vector(cb.tail_local)
        p = (u - ph) % 1.0
        half = stride * DUTY * 0.5
        if p < DUTY:
            y, z, fold = home.y + stride * DUTY * (p / DUTY - 0.5), home.z, 0.0
        else:
            k = (p - DUTY) / (1 - DUTY)
            y = home.y + swing(k, half, stride * (1 - DUTY))
            z = home.z + LIFT[kind] * lift * math.sin(math.pi * k)
            fold = math.sin(math.pi * k) ** FOLD_POWER
        if kind == "Front":
            op_rot(a, "FrontForearm." + s, (10 + 25 * fold, 0, 0))
            op_rot(a, "FrontCannon." + s, (-20 - 60 * fold, 0, 0))
            op_ik(a, "FrontCannon." + s, a.matrix_world @ Vector((home.x, y, z)), 4)
        else:
            op_rot(a, "HindShin." + s, (-8 * fold, 0, 0))
            op_ik(a, "HindCannon." + s, a.matrix_world @ Vector((home.x, y, z)), 3)
        hb = a.data.bones[hoof]
        rest = (hb.tail_local - hb.head_local).normalized()
        target = (0, 0.9, 0.45) if kind == "Front" else (0, 0.85, 0.5)
        op_hoof(a, hoof, rest.lerp(Vector(target), fold * (0.9 if kind == "Front" else 0.8)))


def march_dense():
    """The re-keyed MARCH, replacing cavalry_MARCH (keep a copy of the shipped action first)."""
    n = CANTER_FRAMES * KEYS_PER_FRAME
    OPS["gait"] = op_gait_rigid
    try:
        return clip("MARCH", [(f, canter_pose(f / n)) for f in range(0, n + 1)])
    finally:
        OPS["gait"] = op_gait


def export_march(path):
    """The rig and mesh exported at DENSE_FPS; only MARCH is read from it (the other clips' times are
    meaningless at this rate and are never transplanted)."""
    sc = bpy.context.scene
    fps = sc.render.fps
    sc.render.fps = DENSE_FPS
    try:
        bpy.ops.object.select_all(action="DESELECT")
        a = rigo()
        a.select_set(True)
        for o in a.children_recursive:
            o.select_set(True)
        bpy.context.view_layer.objects.active = a
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_skins=True,
                                  export_animations=True, export_animation_mode="ACTIONS", export_frame_range=False,
                                  export_force_sampling=True, export_optimize_animation_keep_anim_armature=False,
                                  export_apply=False, export_yup=True)
    finally:
        sc.render.fps = fps
