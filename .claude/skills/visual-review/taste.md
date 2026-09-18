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
  house, what reads is silhouette, not material. That is why procedural
  Blender towns were abandoned after five rounds; do not retry.
- **Clustered, not scattered.** Woods and ranges gather together
  (value-noise field); scattered, hash-placed marks read as "unreasonable".
- **One size where the owner said one size.** For example, estates are drawn at one height: "no big and small".

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
