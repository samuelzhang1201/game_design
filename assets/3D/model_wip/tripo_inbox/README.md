# Tripo inbox

The staging folder for every 3D model the owner generates in Tripo, waiting to be processed in Blender. Everything here but this README is git-ignored (`assets/3D/**/model_wip/**`), and the `.gdignore` one level up keeps Godot from importing the GLBs.

## Layout

```
tripo_inbox/<category>/<object>/
    REF_<picked reference>.png      the picture to upload to Tripo (copied from the object's model_wip/)
    <object>_tripo[_vN].glb         what the owner exports from Tripo
```

`<category>/<object>` is the same pair as the object's home, `assets/3D/<category>/<object>/` (e.g. `buildings/wall_gate`, `ships/cog`). A folder for a new object is made when its reference is picked.

## The owner's part

1. Upload the folder's `REF_*.png` to Tripo — on the PAID plan only (only paid generations are commercially ours, Tripo terms §5.2.2) — and set the model private.
2. Export a textured GLB and drop it into the same folder, named `<object>_tripo.glb` (`_v2`, `_v3` … for more tries). Any name works; the folder says what it is.

## Processing

In the owner's open Blender (via the MCP), with the pipeline for the kind of object — buildings `tools/map3d/tripo_houses/`, units `tools/units3d/*_tripo/`. Once a GLB is processed it MOVES to its object's `assets/3D/<category>/<object>/model_wip/tripo/`, where the pipelines look for their sources, so the inbox holds only what is still waiting.
