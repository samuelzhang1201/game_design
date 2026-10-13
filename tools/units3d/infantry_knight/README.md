# The Tripo knight (the game's infantry piece)

`assets/3D/units/infantry/infantry.glb` since 2026-10-13 (owner: 烘焙动作，减面，导出 glb 放进
infantry — 直接替换 infantry.glb). It replaces the man-at-arms of `tools/units3d/infantry_tripo/`.

## Sources

Three Tripo 3D generations on the owner's **paid** plan, downloaded as glTF:

| file | what it is |
| --- | --- |
| `medieval knight armor 3d model walk.glb` | the knight (one 98k-tri mesh, 4K base / roughness-metallic / normal) on Tripo's auto-rig: 65 Mixamo-named bones, clips `walk` (2.33 s, root motion) and `standing_relax` (17.6 s) |
| `medieval spear 3d model.glb` | the spear (92k tris), normalised to 1 m |
| `medieval shield 3d model.glb` | a kite shield (92k tris), normalised to 1 m |

The working scenes are in `assets/3D/units/model_wip/` (git-ignored, `.gdignore`d):
`knight_spear_shield_march.blend` (the live set-up: IK arm, props on constraints, editable) and
`knight_spear_shield_game.blend` (the baked, reduced piece the export is made from).

## What was done, in the owner's Blender (MCP)

1. **Scale.** The knight ×1.8, the spear ×2.8, the shield ×0.85; the shaft thinned to ~3.2 cm and
   the head shrunk (×0.4 across, ×0.55 long), owner: 矛改的细一点，矛的箭头小一点.
2. **MARCH** (owner: 盾牌挂在小臂上，宽边向下，尖边朝上，随着手臂摆动而摆动 / 右手手臂弯曲，把矛扛在肩上，矛尖向上):
   the walk with the right arm on a two-bone IK to a target riding `Spine`, the hand copying the
   target's rotation, the spear through the fist resting on the right pauldron (~36° back from
   upright, tip up and back); the shield hung on the left forearm, wide edge down, turned 45° about
   the forearm toward the front-left so its face shows to the camera (`unit_figures.md`: a piece's
   colour must face the camera — hung flat it read as a grey knight); the left arm keeps the walk's
   own swing. Root motion removed (the hips' forward channel detrended);
   the fingers' keys deleted and a fist posed instead.
3. **STANDBY**: `standing_relax` with the same fists, the right hand at the side holding the spear
   upright, its butt on the ground (a damped track from the butt to the grip).
4. **Bake**: MARCH and STANDBY baked with visual keying; `spear` and `shield` are bones of their own
   (children of `RightHand` / `LeftForeArm`) so each clip holds the spear its own way. The spear
   bone's rest stands upright beside the right foot, so the rest box is the spear's 2.67 m, as before.
5. **Reduce**: the knight collapsed to 15.5k tris, the shield to 3.5k; the spear rebuilt (a
   decimated shaft breaks into dashes): the head decimated to ~900 tris, the shaft an 8-sided
   tube with the high spear's UVs transferred. Total 20,195 tris.
6. **Atlas**: one 2048 atlas — the knight's 4K maps scaled into x 0–1536, the shield's into the
   right column's top half, the spear's into its bottom half, each mesh's UVs remapped by the same
   affine (exact, no bake). Steel (sat < 0.16, value > 0.30) given `infantry_tripo`'s warm tint
   (1, 0.95, 0.88) but NOT darkened: this knight's steel is already mid-grey, and darkened to 0.32 it
   was a black silhouette on the map. Metallic capped at 0.25, metal roughness ≥ 0.55 (Tripo's
   metallic ~0.6 also read black).
7. **Export frame**: bones' `mixamorig:` prefix stripped, `Head` → `head` (`Map3DUnitRig.head_m`);
   the rig `inf_rig`, the mesh `infantry` (the scene's override path); scale applied (helmet crown
   1.85 m, location keys scaled with it); turned 180° about Z to face +Y in Blender (−Z in Godot).
   Exported with `model_cavalry.export_glb`'s settings (NLA tracks per clip, JPEG 92).
8. **Godot keeps extracted textures**: a re-exported `.glb` does NOT overwrite the
   `infantry_infantry_atlas*.jpg` beside it, and Blender's glTF exporter reuses an image it already
   wrote this session — write the `.jpg`s from the `.glb`'s embedded images after each export and
   rebuild the image datablocks before re-exporting. The rig re-hides itself; unhide it before
   exporting `use_selection` or the `.glb` comes out with no skin and no clips.
9. **GARRISON** is the owner's own Tripo clip (owner 2026-10-13: 驻防的动作我这里有了), a crouched
   guard on the same skeleton, with the shield and spear fitted in
   `assets/3D/units/model_wip/knight_kneel_guard.blend` to the owner's rulings, round by round:
   the shield upright before the left side, held at the left fist and lowered 12 cm so the visor
   shows; the spear braced from the right fist, RESTING on the shield's inner edge and aimed with
   his gaze (44° to his left, 8° up); the right wrist straight (the fist turned about the shaft,
   the elbow tucked behind the right side). `kneel_guard.py` carries it onto `inf_rig` exactly
   (`record` in the kneel file, `apply` in the game file; the docstring has the method). 120
   frames, 4.96 s.

## Measured

MARCH stride 2.81 m per 56-frame loop (each foot's planted frames move 0.050 m/frame), written to
`data/screens/map3d/army_art.csv` `stride_m`. Head bone at 1.58 m.

## Open

* `infantry_parts.glb` (the folio's Take apart) is still the old man-at-arms.
* `tools/art_kit/specs.json` not rerun for the new skeleton (`extract_specs.py`, then `build_kit.py`).
