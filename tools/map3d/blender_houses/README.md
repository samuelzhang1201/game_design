# Hand-modelled settlement houses (Blender)

Owner 2026-09-24: the fourteen house types in `data/map3d_houses.csv` are
modelled by hand in Blender through the Blender MCP. They were first modelled
looking at Hunyuan3D meshes as reference (no geometry or texture copied);
those meshes and the whole Hunyuan3D pipeline were DELETED later that day
over the licence (owner 2026-09-24). The references now are the Flux
pictures `tools/map3d/gen_house_refs.py` renders into
`assets/flux/out/house_ref/`.

Why: the Hunyuan3D community licence does not cover the EU, the UK or South
Korea, and its meshes were heavy (2,000 to 9,000 triangles after decimation,
from 40,000). The hand-built set is 144 to 3,858 triangles a type.

## Rebuild

```bash
python3 tools/map3d/blender_houses/textures.py      # Poly Haven CC0 textures, fetched and tinted to the palette
```

Then in Blender, with the MCP server running:

```python
exec(open("/Users/samuelzhang/game_design/tools/map3d/blender_houses/kit.py").read())
exec(open("/Users/samuelzhang/game_design/tools/map3d/blender_houses/buildings.py").read())
for t in BUILDERS: print(build_and_export(t))
```

`export()` fits each model to its row's `footprint_m`, writes
`assets/map3d_houses/<type>.glb` and records `width_m` / `depth_m` / `height_m`
in the CSV and `tris` in `houses.json`. After it:

1. Reimport: `Godot --headless --path . --import`.
2. Rebuild the world with `tools/map3d/build_pack.sh`. The house table is part of the
   world's `steps_hash`, and the packer places houses by their measured rectangles.

## Rules

- **Front is -Y** in Blender, which becomes Godot's +Z, the side the packer turns to the lane.
- **Model in game metres.** Houses are drawn at twice life size, so a door is about 2 × 4 m.
- **Every part is a closed solid**, and parts may interpenetrate.
  `test_map3d_houses_meshes.gd` fails on any hole wider than 1 m.
- **At most five materials a type.** Each material is a surface, and each
  surface is one draw call per MultiMesh. The keys are a wall, a roof, `timber`
  (frames and doors), `void` (window and door recesses) and optionally a second
  wall; the church swaps `timber` for `cross_wood`.
- **Vertex compression is OFF** in every `<type>.glb.import`
  (`meshes/force_disable_compression=true`). Godot quantises each surface
  against its own bounding box, so a seam between two surfaces lands a fraction
  of a millimetre apart on each side. The hole census then reads every window's
  rim as an open loop. These meshes are small, so the uncompressed vertices cost
  nothing measurable.
- **Roofs.** The houses wear WARM tile, orange-red terracotta in five shades
  (owner 2026-09-24). Slate is kept for the three church landmarks only. Never
  thatch, never a dark brown tile (taste.md).
- **Grime is vertex colour.** Every wall solid gets a ring of vertices
  `GRIME_H` (2.6 m) above the ground. COLOR_0 runs from a damp earthy colour
  at the foot to clean at that ring, then eases darker toward the eaves.
  Godot multiplies it into the albedo. Only the wall keys carry it
  (owner 2026-09-24: 墙根加上有污渍、做旧).
- **`void` is always surface 0.** Godot 4.7's glTF import turns
  `vertex_color_use_as_albedo` on for every surface except the FIRST
  (measured over five types). The void recess is the one surface whose
  colour the grime never touches, so it takes that slot.
- **Every new model gets its own place in the Blender scene.** `_free_slot`
  uses a 90 m grid, 6 per row, and a rebuilt model keeps its place. Never
  stack a new model on the last one (owner 2026-09-24).
- **The church wears one great wooden cross** on its west gable, in place of
  the bell-cote and its two small crosses (owner 2026-09-24: too small to
  read). The wood is Poly Haven `rough_wood`, darkened to aged oak (`cross_wood`).
- **Anti-aliasing is the viewport's job, not the mesh's.** At the closest
  zoom a house is ~40 px wide. Its stair-stepped edges came from `high`
  running without MSAA, not from the model, so `graphics_quality.csv`
  `high` / `ultra` now use MSAA 4x (+0.3 to +1.0 ms in the pan bench).
- **Texture targets sit darker than the palette.** The map's sun and Filmic
  tonemap lift a sunlit wall toward white (`textures.py`).
