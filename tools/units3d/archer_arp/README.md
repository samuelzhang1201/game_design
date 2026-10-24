# Equipped ARP archer

`scenes/models/units/archers.tscn` inherits the character-only `archers.glb`.
Its bow, loaded quiver and arrow come from separate GLBs beside that file.
Their MeshInstance3Ds share the character's Skeleton3D using **named skin
binds**, with identity mesh transforms. Gear palettes retain only their
weighted bones (bow: two; quiver and arrow: one each). Copy each named bind
pose from the BODY skin when assembling after import; a separate GLB
importer can choose a different skeleton origin. Do not add another grip offset or
copy the equipment's skeleton into the assembled scene.

The owner-provided source is the corrected, equipped ARP soldier. The source
blend, FBXs and intermediate blends remain local under `model_wip/`; playing
a fresh checkout uses only the committed models and extracted textures.
No generation service or Blender add-on is needed to play.

The six source clips map as follows:

- Standing Idle 03 Examine → STANDBY (loop)
- general/Standard Walk → MARCH (loop, in place)
- Standing Sprint Forward → SPRINT (loop, in place)
- Standing Draw Arrow → DRAW (one shot)
- Standing Aim Overdraw → GARRISON (loop)
- Standing Death Forward 02 → DEATH (one shot)

The map's existing order routing selects STANDBY, MARCH and GARRISON;
DEFEND falls back to GARRISON. The other clips are available in the model's
AnimationPlayer. This installation does not add new battle behavior.

The original corrected body weights are retained. DRAW is mirrored to a
left-hand bow and right-hand retrieval/draw; the other clips retain that side.
The original gear is reflected onto its matching mounts; the quiver is on the
right, the bow is parented to `DEF-weapon.L`, and fingers retain the equipped
grip. Walking, aiming and sprinting wrists are fitted to this bow. Locomotion root travel is removed and its
measured walk stride goes into `army_art.csv`. Sole contact is corrected at
each sampled frame. The falling wrist lays the bow flat as the body lands.
The body retains its original geometry and UVs; the gear follows the
simplification pipeline below.
The scene uses generated LODs with `lod_bias = 0.1`. The quiver and arrow
fade beyond the close map view; the body and bow remain visible at every
zoom. Per-surface roughness, metallic response and normal strength are baked
into shared maps so the body and arrow each need one surface, preserving
cloth/mail/leather differences while reducing formation draw calls.

## Rebuild

Run with the owner's Auto-Rig Pro installed; paths after `--` are explicit:

```sh
blender -b --python tools/units3d/archer_arp/retarget.py -- SOURCE_PROJECT WORK
blender -b --python tools/units3d/archer_arp/export.py -- WORK DESTINATION_PROJECT
blender -b --python tools/units3d/archer_arp/validate.py -- WORK
```

`retarget.py` reads the equipped blend's saved ARP mapping and calibrates the
source's rest offset against the matching draw FBX. `export.py` makes a
constraint-free skeleton, keeping `DEF-weapon.L/R`, `DEF-bow`, `DEF-quiver`,
`DEF-arrow` and `DEF-string`. The string's original linear shape animation
is represented by weighted translation of `DEF-string`; source keys remain
in the authoring file. Export retains all influences (the inner hem uses six).
The public head bone is `head`; Blender −Y is converted to game −Z.

After import, update the inherited scene through the Godot editor: keep one
skeleton; copy each gear mesh under it with `skeleton = NodePath("..")`;
save the gear meshes as compressed, material-free `.res` resources beside
the GLBs (avoids copying geometry into scene text); copy each imported
surface material to a scene override; copy each gear skin and replace its
bind poses by name from the BODY skin (not inverse global rest transforms);
keep the scene's LOD
and detail visibility settings. Extract textures
beside the GLBs and import them with Basis Universal compression. Set the
four repeating clips to LOOP_LINEAR and DRAW/DEATH to LOOP_NONE in the GLB
import settings. Re-run the material, skin, clip and real-window visual checks.

`validate.py` checks every sampled frame for body/bow penetration and a fixed
left-hand grip, checks the loaded arrow against the evaluated string, measures
MARCH stride from planted-foot speed, and compares body coordinates, topology,
UVs and weights against the corrected source. It rejects missing or
unnormalized weights. `export_metrics.json` and `validation.json` record the
actual measurements in WORK. The original export has 73 bones; its body and clip tracks are retained by
the gear pipeline below. Benchmark the full formation when changing geometry.

## Gear simplification

The body, its original skin and all six clips remain unchanged. Only the bow,
arrow and loaded quiver use surface-constrained isotropic retopology, new UVs
and rebaked albedo/metal-rough/normal atlases. Bow-string weights are interpolated
from the original surface; both other props retain their rigid named mounts.
The installed meshes retain generated LODs and the scene's existing visibility
settings and material overrides. No scene edit is needed for a mesh delivery.

Build settings are `archer_gear_lod` in the data index. Keep the original
high-resolution GLBs in a local `model_wip/` source directory; the installed
GLBs are the simplified deliveries, not the inputs for another simplification.
The build writes both candidates outside the installed assets and rejects any
failed default decikit topology/surface/skin audit before export. It requires
Blender, NumPy and PyMeshLab only when rebuilding, never when playing.

```sh
python3 tools/units3d/archer_arp/gear_lod.py WORK \
  --source HIGH_RES_GEAR_GLB_DIRECTORY --blender BLENDER_BINARY \
  --decikit PATH_TO_BLENDER_DECIMATE_QUALITY_SKILL/scripts/decikit.py
Godot --path . --script res://tools/units3d/archer_arp/gear_install.gd -- WORK
# After comparing both candidates, explicitly install the selected one:
Godot --path . --script res://tools/units3d/archer_arp/gear_install.gd -- WORK --install proposed
Godot --headless --path . --import
```

`gear_install.gd` transfers the imported palette indices onto the existing
scene's named binds, saves compressed meshes with their original UIDs and
installs the matching GLBs/atlases. The GLBs preserve the extracted image names,
so a fresh import and the scene's existing material overrides use the same UVs.
The proposed gear has 8,130 / 13,310 / 17,863 triangles (bow / arrow / quiver),
39,303 together; the body remains 94,096 triangles. Acceptance evidence and
source hashes are in `docs/reviews/archer-gear-lod/`.
