# The owner's taste — rulings distilled into principles

Each line is a principle the owner ruled on, the reason, and where it came
from. When a new ruling lands ("太粗糙了", "completely wrong", "这个效果可以"),
add it here as a principle with its why — not as a changelog entry.

## Whole-picture coherence
- **One world, one medium.** Everything on the map must look like the same
  photograph: a painted town on satellite ground read as a sticker, so towns
  became aerial photos (2026-09-17). Before adding any art, ask "which medium
  is the ground in right now?"
- **Water is one water.** A river and the sea it runs into share a colour
  (2026-09-17).
- **Nothing ends on a hard cut.** Built-up areas thin outward into fields;
  cut-outs feather their rim; biome tiles cross-fade per pixel, never per
  Voronoi cell. A hard-edged tray, slab, disc or ring around an object is
  the most frequent reason something was called ugly.
- **No base plates.** Objects stand on the map's own ground (the grass disc
  under the 3D towns was the first thing rejected).

## Shape and reading
- **Read by width and fade, not by rule.** Roads are worn tracks with a soft
  shoulder, never ruled lines (2026-09-17).
- **Relief comes from height, not from texture.** Tiles carry material only;
  landform words in a texture prompt made a wallpaper of feathers.
- **Geometry density beats texture relief** at small draw sizes: at ~80 px per
  house, what reads is silhouette, not material. Procedural Blender towns
  were abandoned after five rounds on 2026-09-16 for this reason.
  *Amended 2026-09-20: that ruling was about a 3D town rendered down to a 2D
  sprite pasted on the 2D map's own photographic ground ("3d城市的建模没有用，
  删掉"); the owner OVERRULED it for the 3D map itself ("推翻它，这次是真3D地图")
  — houses now stand as real meshes on Terrain3D under the scene's own light,
  which is a different thing from a sprite. **No base plates** survives from
  that 2026-09-16 ruling unchanged: the grass disc under those towns was the
  first thing rejected, and a house mesh may not carry one either.*
- **At a 10 px draw size, what reads is silhouette, roof colour, and whether
  a landmark stands above the rest — not detail** (owner's 800 m closest
  zoom on the 3D map, 2026-09-20: a house is 9–17 px there). The house
  meshes are low-poly by design and the roof colour, not the geometry, is
  what tells a thatched cottage from a tiled townhouse.
- **Clustered, not scattered.** Woods and ranges gather together
  (value-noise field); scattered, hash-placed marks read as "unreasonable".
- **A settlement ends in a buffer, not at its last house** (owner 2026-09-20):
  between the houses and the fields lies a ring of built ground with nothing
  standing on it — yards, threshing floors — because a cluster that stops
  where its buildings stop reads as a sticker laid on the ground beneath it.
- **A medieval town reads by its lanes, not by its buildings**: compact and
  messy, with negative space threading through it, never evenly-spaced
  houses. The owner rejected an even scatter TWICE (a jittered grid with a
  radial density falloff, then a denser version of the same thing) as
  scattered and unreasonable; the fix was to grow a lane network out from
  the settlement's centre first and pack houses along its frontage, filling
  whatever block is left behind the lanes.
- **Lanes keep their real width** (3–4 m), unlike the roads and rivers this
  project deliberately draws wider than life for legibility. The owner
  accepted that a true-width lane stops reading past ~2500 m and the
  cluster becomes one solid mass at distance, rather than widen it to
  compensate.
- **The marker dot is a far-zoom affordance only, not a settlement's whole
  representation** (owner 2026-09-20): now that a settlement is a real
  cluster of houses up close, the dot that used to stand for every
  settlement at every zoom is kept only where the houses themselves are too
  small to read — white and solid, the capital's alone with a dark centre.
- **One size where the owner said one size.** For example, estates are drawn at one height: "no big and small".

- **On the 3D map, lines rank by pattern, not by colour** (2026-09-18): the
  kingdom border is a thin SOLID black line, province seams DARK DASHES at
  half opacity, roads a soft darker-sand track. The 2D map's chequered
  ribbon was rejected there, and pale seams had the same hue as the sand
  roads, so the two could not be told apart.
  *Reversed for the kingdom border by the owner on 2026-09-19: "the thin
  solid black line is ugly — make it better".*
- **A bare thin black line is not enough for a border** (2026-09-19): a
  border should say whose side is whose. (The band in each realm's colour
  fading inward, the pale halo and the warm-ink line now drawn are the
  implementer's recommendation of 2026-09-19, pending the owner's
  confirmation — not a ruling.)

- **A tool must not borrow the map's line language** (2026-09-18, ruler):
  the MEASUREMENT ruler's dashes alone read as one more border. What makes
  it a ruler is a crossbar at each end and ticks standing on ONE side (a
  tick across the dashes makes "+" and "T" noise). Ticks no closer than
  ~100 px; at 48 px they merged into a railway track.

## Colour and value
- **Greyscale art takes the realm's hue; colour art keeps its own.** Symbols
  and estates carry VALUE only and are multiply-tinted; photographs, icons,
  portraits and arms keep their colour.
- **Lighten in the file, not with alpha.** A translucent mark cannot occlude
  the one under it.
- **Dark UI after Crusader Kings III:** parchment ink on dark leather, gold accent. Test
  contrast, not hexes.
- **Blackletter only where it can be read:** headers in title case, never
  all-caps runs.

## Sharpness
- **Look right at any window size.** Linear + mipmaps. Judge at a real
  fractional window (`--resolution`), never only 1280x720.
- **Size art by its use:** design px × ~3 window scale. A blurry icon is
  often a resolution/fit problem before it is an art problem.
- **Sharp up close and clean from far.** One tile size cannot serve both
  zooms (tile LOD); check the nearest AND the farthest zoom.

## Process the owner prefers
- Show 2–3 samples and let the owner choose (arms: matte over glossy and
  gouache). Never queue a generation batch without asking.
- The owner judges from snapshots at map zoom 1 and 3. Bring those.

## 事件插图的三条硬规矩（2026-09-21，序章 21 张图，三轮才收敛）

1. **画布拼在 prompt 末尾，抢得过场景词。** `STYLE_CORE` 在最前面说的"12–14 世纪"压不住场景自己的名词——写 `livery` 就出拿破仑制服，写 `ministers` 就出 19 世纪会议室，写 `travelling gown` 就出维多利亚裙。凡是要钉死的约束，写进 `[C-...]` 画布，不要指望风格核心。
2. **画面里有纸，就一定会长出假文字。** 负面词里的 `printed typography, lettering` 挡不住账簿、请愿书、条约。唯一有效的办法是**让纸本身看不见字**：合上、折起、背过去、只露封蜡，或者以极斜的角度只看得见尺线；并且在 subject 里明写"看不见任何字"。
3. **一个场景里有国王和别人打架，模型会把王冠戴错人。** 与其反复重摇，不如**把主角移出画面**——"从国王自己的位置看出去，画面里只有他伸出的手和袖子"，歧义就没了。

附带：Flux 把 `corn` 画成玉米。中世纪欧洲的麦田一律写 `wheat`，并加 `no maize`。
