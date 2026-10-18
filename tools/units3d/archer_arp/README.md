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
No decimation is applied: the original geometry and UVs remain intact.
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
actual measurements in WORK. The export has 73 bones and 381,626 triangles
across four meshes; benchmark the full formation when changing this geometry.
