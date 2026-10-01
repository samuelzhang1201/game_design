# The WAR ROOM's furniture — Blender build scripts

The scripts that built `assets/3D/war_room/{room,table,candlestick,rake,pennant}`
(2026-10-01) in the OWNER's open Blender through the Blender MCP (standing rule:
every Blender step in the owner's instance, never headless). They are plain
`bpy` scripts meant to be `exec`'d there, in this order:

| script | builds | collection |
|---|---|---|
| `wr_lib.py` | helpers, read by every other script: game ↔ Blender axes (`G(x, y, z)`: game x, y up, z south → Blender x, −z, y), `new_obj`, `mat_flat`, `mat_tex`, image loading | — |
| `wr_room.py` | the stone chamber: four inward walls, the floor, the window recess with its leaded glass (painted into `model_wip/textures/leaded_glass.png`), two wall sconces | `WR_room` |
| `wr_table.py` | the oak trestle table, top 1.8 × 1.7 m at y −0.045, iron clamps | `WR_table` |
| `wr_candle.py` | the three-candle iron candlestick, origin at the base | `WR_candle` |
| `wr_props.py` | the rake (origin at the head's bottom centre, shaft toward game +Z) and the 35 mm pennant (its atlas and ORM painted into `model_wip/textures/pennant_*.png`) | `WR_rake`, `WR_pennant` |
| `wr_assemble.py` | a preview only: instances of everything where the game puts them, stand-in sheet and chart, lights, the game's opening camera — never exported | `WR_assembly` |
| `wr_view.py` | `wr_view(names, …)`: frames the viewport on some objects for a screenshot | — |

## Running them

1. In the owner's Blender, with the MCP add-on's server started: a scene named
   `WarRoomArt` (`bpy.data.scenes.new("WarRoomArt")`, made current).
2. The textures, 2k JPG from Poly Haven (CC0), into
   `assets/3D/war_room/model_wip/textures/`: `stone_brick_wall_001`,
   `weathered_planks`, `dark_wooden_planks` (diffuse, nor_gl, rough, ao).
   `dark_wooden_planks_diffuse_2k_oak.jpg` is that diffuse RE-TONED toward a
   warmer oak by hand (not scripted); the one the game uses is embedded in
   `table.glb`, so extract it from there to rebuild without retoning again.
3. Each script through the MCP's `execute_blender_code`, telling it where this
   folder is (`WR`, else the default — the owner's main checkout):

   ```python
   WR = "/Users/samuelzhang/game_design/tools/war_room/blender"
   exec(open(WR + "/wr_room.py").read())
   ```

4. Export each object ALONE (select it, File > Export > glTF 2.0): glTF Binary
   `.glb`, +Y up, apply modifiers, materials exported with their images, no
   animation, no skin — to `assets/3D/war_room/<name>/<name>.glb`. The `.blend`
   is saved beside it as `model_wip/<name>_wip.blend`.
5. In Godot, `Godot --headless --path . --import` once. The room's and the
   table's `.import` carry `gltf/embedded_image_handling=2` (their textures stay
   INSIDE the imported scene as Basis Universal, VRAM-compressed — see
   `assets/3D/war_room/README.md`); the small props extract theirs beside the
   `.glb` (git-ignored build output) as the units do.

## The 1k re-export (Ruling 24)

The `.glb` files were committed as built with 2k textures (room 14.6 MB, table
8.4 MB). To shrink them, scale the images to 1024 in Blender before step 4
(`img.scale(1024, 1024)` on each `WR_stone` / `WR_floor` / `WR_table_oak`
image) and re-export; nothing in the game names the texture size.

## The references

The Qwen-Image-2512 pictures these were modelled against are each object's
`model_wip/<name>_ref_qwen2512fast.png` (git-ignored), rendered by

    python3 tools/map3d/gen_house_refs.py --model qwen2512fast --seed 20261001 \
        --prompts assets/flux/war_room_ref_prompts.csv --out assets/3D/war_room

(ask the owner before queuing any generation). The concept the owner chose is
`assets/3D/war_room/model_wip/concept/room_qwen2512fast.png`.
