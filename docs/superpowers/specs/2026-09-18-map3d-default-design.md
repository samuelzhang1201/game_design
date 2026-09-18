# The 3D map as the default map

Owner, 2026-09-18: "完全移除默认的2D地图，用3D地图作为默认地图". The chosen
route (option A of three) is staged: the 3D map becomes what the player sees
now, the 2D map stays only as the ground for the layers the 3D map cannot yet
draw, and the 2D map is deleted once every one of those has moved to 3D. At
no point does the game lose a feature.

## The rule

One rule decides which map a screen's map panel shows:

> **3D** ⇔ the pack has a built 3D scene **and** no 2D-only layer is on
> (HEIGHTS, ECONOMY, MANORS, MILITARY) **and** `balance.csv`
> `map3d_default` is 1.

Otherwise **2D**. Nothing else chooses between them.

- `GameRoot._sync_map_view()` evaluates the rule and hands the result to the
  current screen through its existing `set_map3d_view(on)`
  (`Map3DView.toggle_in` is unchanged). It runs when any of the four layers
  changes, when a screen is swapped in, and on load.
- `_map3d_view` stops being a toggle the player flips; `map3d_view()` remains
  as the read of the rule's last result, for screens, tools and tests.
- The four "lighting this layer puts 3D out" branches in `set_height_view`,
  `set_economy_view`, `set_manor_view` and `set_map3d_view`, and the 3D
  branch of the screen swap, are replaced by `_sync_map_view()`. The three
  themes' mutual exclusion among themselves stays as it is. MILITARY, which
  today draws on the 2D map with 3D left on (so its counters are hidden),
  now switches to 2D like the themes.
- "The pack has a built 3D scene" is
  `ResourceLoader.exists(Map3DView.scene_path_for(map_id))`. The scene is
  built locally by `tools/map3d/` and is git-ignored, so a fresh clone has
  none; such a machine shows the 2D map, silently, exactly as before this
  change. `Map3DView`'s own "no scene" notice stays for tools that open the
  view directly.

## The bottom bar

"3D MAP" leaves `BottomBar.TABS` and `BottomBar.TOGGLES`; the bar begins
HEIGHTS | ECONOMY | MANORS | REALM | MILITARY | … Closing a layer returns the
map to 3D by the rule; there is no control that asks for the plain 2D map.

## Tests and tools

- `map3d_default` (balance.csv, default 1) exists so the suite can hold the
  2D map: this machine has a built scene, and without the key every UI test
  would load Terrain3D and every assertion that the 2D map is visible would
  break. The test setup sets it to 0; only the 3D tab tests set it to 1.
- `tests/map3d/test_map3d_tab.gd` is rewritten around the rule: with a scene
  and no layer → 3D; each of the four layers on → 2D, off again → 3D; no
  scene (a missing path through the existing `scene_path` seam or a pack id
  with none) → 2D; the choice follows a screen swap; "3D MAP" is not a tab.
- `tools/snapshot_screen.gd` follows the default and gains `--map2d` to shoot
  the plain 2D map; `tools/snapshot_map.gd` and `tools/bench_map.gd` drive
  `WorldMapView` directly and are unaffected.

## Known gaps while the 2D map remains

With the 3D map showing, the player does not get: the hovered country's card
in the left column, kingdom name labels, the political wash, the settlement
photographs, the sea decor. Manors, the economy and the host are reached by
their layers, which switch to 2D. These are the migration list, in the order
they matter to Chapter 1:

1. Hover → the country card (the left column's precedence already takes it).
2. Kingdom labels.
3. Manor picking and the MANORS layer in 3D (the manor card's orders are the
   Chapter 1 economy).
4. MILITARY counters in 3D.
5. ECONOMY and HEIGHTS in 3D.
6. Political wash and settlement art, if the owner still wants them on the
   3D ground.

When the list is empty the 2D map (`WorldMapView` and its layers, the 2D
bakes, `map3d_default`) is deleted in its own change. Each item is its own
spec.

## Documentation

CLAUDE.md: the 3D MAP tab paragraph and the bottom-bar list change to say the
3D map is the default, the rule above, and that the 2D map is the layers'
ground until the migration list is done.
