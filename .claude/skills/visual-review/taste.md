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
  (2026-09-17). At its mouth a river BECOMES the sea's water — its colour,
  light, ripple and shelf, not a tint toward it — and runs on over the
  water as the sea's own water, with no seam at the waterline (owner
  2026-10-05: 把入海口附近的河水颜色渐变成海水颜色; critic 2026-10-06: a
  handover at the waterline drew a speckled seam across the mouth):
  a river tinted toward the sea's colour but lit and rippled its own way
  read as a grey plume laid on the sea.
- **A waterline follows the ground, not a raster** (owner 2026-10-06: 把入海口
  两侧的方形草地边缘也修掉). The sea drawn off the 50 m coast map cut the land
  beside a river's mouth into square blocks; the shore is where the ground
  meets the water.
- **Nothing ends on a hard cut.** Built-up areas thin outward into fields;
  cut-outs feather their rim; biome tiles cross-fade per pixel, never per
  Voronoi cell. A hard-edged tray, slab, disc or ring around an object is
  the most frequent reason something was called ugly.
- **A grade cannot rescue the ground; material and life do** (owner
  2026-09-30: "配色我觉得救不了画面"). Four colour grades of the same map were
  shown and none fixed "ugly and fake": the causes were ground-level photo
  textures stretched to 160-320 m tiles (grey noise from the air), bare land
  with no woods, an ink line round every coast and rust field decals. The
  ground wears pictures made AT map height (aerial, Z-Image — Qwen drew grass
  close-ups), the land carries woods (the "no trees" ruling is lifted for the
  3D map), and borders stop at the shore.
- **Rock is photographed from where the player looks** (owner 2026-09-30,
  cliff texture). A frontal photograph of a rock wall, laid on a slope seen
  from above, bent its strata into tiger stripes; a top-down crag photograph
  reads as rock. Rock sits WARM beside the golden grass — a cool blue-grey
  crag read as a second photograph pasted on — and its baked-in black holes
  are lifted, or they read as burns.
- **Snow lies ON rock, not on a lawn** (owner 2026-09-30, the snow caps:
  "山顶雪帽"). A beige snow tile with a rim that follows a contour read as a
  plaster lid set on a green dome. Snow is near-white with no colour of its
  own, its line broken by noise and lower on the shaded (north) side, and it
  ends above a margin of grey scree — never straight into grass.
- **Motion must read at the zoom the map is played at** (owner 2026-09-30:
  "我并没有看到麦浪和树摇"). A wind shown only in a 1.5 km close-up is a wind the
  player never sees: judge an effect at the opening view (~24 km) too, with
  the clock running, the sun turning and the clouds passing — they move the
  frame far more than a faint effect does. Far out, scale the effect up (broad
  gusts, not true-size waves), not merely its strength until it reads as
  cloud shadow.
- **Wind over grass is a travelling crest, never a drifting veil** (owner
  2026-09-30: "看上去就像是雾气飘过一下，不像是草地的起伏"). Round, soft noise
  blobs that lighten and grey the ground read as mist or cloud shadow. Grass
  in wind, seen from above, is thin crests ACROSS the wind — a quick rise, a
  slow fall behind — broken into dashes, coming in runs where a gust passes;
  the crest LIGHTENS the grass and keeps its colour (a greyed crest is fog),
  and far out a darkened trough reads as cloud shadow. Evenly spaced dashes
  read as ploughed ridges: break them into long, tapering pieces.
- **A ground picture must be sharp at the scale it is laid** (owner
  2026-09-30: "草地拉近看太模糊了", chose the patchy meadow T-64). A grass photo
  taken from 20 m and spread over a 120 m tile smears into brush strokes; a
  detail texture cannot rescue it (at the closest zoom a pixel is ~0.5-1 m).
  What reads as sharp from map height is crisp structure at 1-10 m — patches
  of long and short grass with clean edges, a few bushes — not fine grain.
- **The sky is sparse and even over the whole map, and faint** (owner
  2026-09-30: "云的效果请再淡一点，稀疏的分布在大地图，不要集中"). Clouds spawned
  over the view where play began read, zoomed out, as one clump there; they
  belong to the map, spread evenly, and wrap round it on the wind.
- **The ground remembers what crossed it, briefly** (owner 2026-10-01: "军事
  单位路过的时候…留下一段行走印记，后逐步消失"). A marching column leaves a trodden
  track that fades over a few game days. On olive turf trodden grass reads
  LIGHTER (flattened, straw and earth) — a dark trail vanished — but on pale corn DARKER (the stalks beaten down), or it vanishes there instead: a mark must answer the ground under it —
  and in lanes, one a file, ragged at the sides, so it is never a painted road.
- **Farmland is a system, not a scatter** (owner 2026-10-01: "地图上那一块块的
  土是什么" → "田地的布局要更合理真实"). Lone brown plots on green grass read as
  stains: fields belong to a settlement — crofts behind the houses, great
  fields in rotation, each split into furlongs of strips, meadow by the water,
  pasture beyond — and each furlong is ONE crop. Crops must READ (gold, green,
  olive) or only the bare earth shows; ploughed earth is a dark grey-brown, never
  orange; the lines between furlongs are thin and light (thick dark ones made a
  tiled floor at 3 km).
- **No base plates.** Objects stand on the map's own ground (the grass disc
  under the 3D towns was the first thing rejected).

## Type
- **Read in a book face; shout only in titles** (owner 2026-09-28, choosing
  Crimson Pro + Alegreya SC after a critique of the UI's "AI feel"). A
  capitals-only face for body text (Cinzel) read every sentence in capitals
  and truncated every fact ("WALBOVE…"), and a blackletter on every section
  header meant nothing stood out — together the template "medieval UI" look.
  Body text has lowercase; headers are tracked small capitals; the
  blackletter is kept for the game's name, window titles and the map's
  kingdom names. Numbers in a column use lining figures (an old-style 0 reads
  as an o).
- **Data wears heraldry, not a dashboard** (owner 2026-09-28, choosing the
  muted "heraldic" set with gold hairlines). Saturated web hues — a sky-blue
  bar, a lime bar, white chips with black figures, a cyan counter — read as a
  SaaS dashboard pasted over the painting. Colours come from one muted family
  (or, azure, vert, purpure, gules); gauges of one kind share ONE hue; a chip
  on the map is dark leather with light figures and a thin gold edge. Muting
  must stop short of losing the distinction a colour exists to carry — the
  ink-and-gold variant greyed the host's arms, the skills and the realms'
  counters into one another and was rejected for it.

## Panels
- **One ornament per layer; the rest is material** (owner 2026-09-28,
  choosing W3 over keeping the scrolls on the columns). The corner scrolls
  on every panel put a frame inside a frame and left nothing looking more
  important than anything else; a flat card with none read cheap. The
  answer is material, not decoration: a faint warm leather grain, light from
  above, a gold hairline inside a column's edge, and the ornament kept for
  what FLOATS (the audience window, events, menus). A grain laid in white
  greyed the leather to slate, and a cellular noise read as veined marble —
  the grain is laid light-in-parchment and dark-in-black, fine-toothed.

- **A board is a real material, and paper on it is old** (owner 2026-09-30,
  the Missive board: "外框和木质我是满意的，但是背景就是平淡整齐的羊皮纸颜色很突兀…
  每一个信息框都有边框，做旧的感觉"). A flat, even parchment or cork fill inside a
  carved frame read as a placeholder; the frame's opening is wood with real
  grain (a photographed CC0 texture, its knots lifted so they do not outshout
  the notes, tiled large enough that no knot repeats in view), and every slip
  on it is aged — yellowed, foxed, a burnt and frayed edge, its own ruled
  border — the letter being read aged to the same paper, casting a shadow onto
  the wood. Coloured header text on carved plaques read pasted on: the game's
  own ink.

- **The main screens are a WAR TABLE: every piece is an object lying on
  pale oak by daylight** (owner 2026-10-01, choosing B3 + C1's bookmarks
  from three rounds of mock-ups: "就用这个，在游戏里做出来"; he had found the
  leather chrome 简陋 with an AI feel — a sidebar/top-bar/bottom-bar admin
  template that framed the 3D map as a small window). The map is a vellum
  sheet with a deckled edge and ink rules; the facts column the steward's
  pinned report in dark ink with red ¶ rubrics and tally marks, sized to what
  is written on it; the purses a dark oak tally board with brass nails; the
  date a brass dial; the clock brass studs; ENTER THE COUNCIL a red wax seal;
  the tabs silk bookmarks hanging from under the sheet, coloured by group; the
  news a paper slip between them. ONE light, upper left, every shadow soft and
  down-right. What is held up to the eye (the audience window, events, menus,
  the council column) stays dark leather. Lessons from the critic's two
  passes: a paper texture's own ruled rim stretched over a big sheet reads
  as a gilt frame (lay only the paper's middle); a solid offset shadow is a
  sticker (step it soft); a filled vector polygon has no antialiasing (edge
  it with an antialiased line); painted icons on 20 px studs are unreadable
  (engrave a glyph); saturated royal hues on silk come from another picture
  (heraldic tinctures); and a tally that rounds draws 49 and 50 alike (count
  whole tens).

- **Entering play is a MOVE on the table, never a cut** (owner 2026-10-01,
  approving the landing: "过渡效果不错", after "游戏场景的UI是突然出现的，很突兀"):
  the title's map is picked up like a sheet (it draws back, a deckled margin
  and a soft, wide, faint shadow appear, a slight tilt), laid square on the
  sheet's place with a small swell at contact, then fades onto the real
  sheet beneath; every other piece comes from the side it lies on, one at a
  time, and the voice comes last, once the landing has been seen. Lessons:
  two half-faded copies of one picture let the table through (keep the real
  one whole under the flying one and fade only the flyer); fade only the
  print, never its paper, over the real sheet (paper over a map is a wash);
  a hard offset band beside a lifted sheet is a sticker (many faint layers,
  wider and fainter the higher it is held); and the map that is laid down
  must BE the map the title showed (hand the live view over), or the swap
  costs a frozen frame.

## Information
- **Name it; the icon is the anchor, not the word** (owner 2026-09-28,
  reversing "icons, not words" of 2026-09-13/14 for the realm card and the
  manor card). Five identical bars under five small still-lifes, and a grid
  of "10", "0/3", "8553", "Temperate ..." had to be hovered to be read. Each
  fact is now art + name + value, grouped under a section, values
  right-aligned and never truncated; figures grouped by thousands; a rate says
  it is a month's ("/mo"). The art stays — it teaches the vocabulary the map
  and top bar use.

  *Amended 2026-09-28 (second critique, owner approved): under a section
  heading that already says "Each Month" the rows drop their "/mo" and the
  goods their green "+" — one format, one ink, tabular figures so a
  right-aligned column reads straight down. A row that only repeats another
  (a pool's worth beside the good that fills it) goes; its number lives in the
  good's tooltip. A rank is a name ("Great farm"), never "3 of 3".*
- **Every reading names itself; a column's art is drawn once** (2026-09-28,
  second critique). The realm card's four figures carry their names under
  them and the people pie's legend names its slices; the top bar's purse
  rows are "Crown" and "House <name>", and the pools' art stands once over
  each column, not on both rows. Bars share a scale only when they share a
  measure — the host's arms are weighed by strength (count × power), in one
  hue.
- **A tool looks like a tool.** MEASUREMENT, which lies over any lens, wears
  a ruler before its word in the word's own ink.
- **A scroll that has more below fades at its foot** rather than cutting its
  last row through the middle.
- **A card's picture is its scene, not its paper** (owner 2026-09-28,
  approving the recommendation). The estate painting is cut to a 2:1 band
  centred where the estate stands, never more than a quarter of the card, in
  a gilt hairline like the audience portrait; a third of the card with a third
  of it bare cream pushed the facts below the fold. A 10 px fade in the
  card's colour read as a dark rim round a glowing photo.

## Commands
- **A command is small capitals in title case; a thing the player SAYS is a
  sentence in the book face** (owner 2026-09-28, approving the
  recommendation after "Start Game", "ASK THE COUNCIL" and "Wave them on" sat
  on one screen). `UiPalette.command_button` sets every verb button in the
  tab face and title case whatever case it was written in; replies, event
  options and letters stay sentences.
- **The title screen is the game's leather by candlelight.** The painted
  page keeps its figures' colour and value; only its pale paper darkens
  (a flat multiply over the whole page read as a muddy veil, the critic); the
  menu is a leather window with the ornament, its one primary Start button,
  and no footer line of key hints.

## Navigation
- **One primary action, and controls grouped by kind** (owner 2026-09-28,
  choosing the grouped bar and the council button). ENTER THE COUNCIL, the
  game's core move, was a rotated strip on the map's edge — the least visible
  thing on the screen — and the bottom bar set lenses, a tool, a placeholder
  and screens in one row of identical boxes. The core move is now the one
  gold primary button; the bar reads lenses | screens with a rule between,
  tabs as words with an underline (a box inside the bar's frame was a frame
  inside a frame); an empty strip says in the game's voice why it is empty,
  never in a developer's.

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
- **Houses are drawn at TWICE life size, and a settlement's tier reads from
  WHAT stands in it, not from how many roofs it has** (owner 2026-09-21:
  "每一个等级的定居点房屋数量要差不多，并且忽略房屋和地图的真实比例的大小，尽量
  贴近AI原图模型的生成游戏模型"). The world is built at 50 m per pack px, so a
  true-to-life 7 m cottage is 7–12 px at the closest zoom and a settlement
  reads as gravel scattered on bare ground; every mesh is scaled ×2 instead
  (`tools/map3d/scale_houses.py`, which rescales the built mesh rather than
  re-running the retopo bake, so the triangle count does not move). The five
  groups' counts are 100 / 80 / 50 / 30 / 20 — under 5:1, where they had been
  100 / 60 / 24 / 20 / 9 — and the tier is told by the palace, the church
  tower, the church or the chapel at the centre, and by townhouses against
  thatch. **Ignoring real-world scale is allowed here; what is not allowed is
  one tier that reads as a different KIND of place than another.**
- **Buildings are SIMPLE REALISM, never toy** (owner 2026-09-22, on a
  generated palace: "这个王宫太假了太卡通了，我要简约写实风格"). Real weathered
  stone with visible masonry courses, plain slate or tile roofs, sober true
  proportions, muted natural colour — no flags, no banners, no bright
  pennants, no shrubs, no little figures, and no ground slab under the
  building. **No AI 3D (owner 2026-09-24: Hunyuan3D removed over its
  licence) — houses are hand-modelled in Blender against a photoreal Flux
  reference; ComfyUI stops at the image.** (2026-09-29: every Hunyuan asset is deleted, the 2D counter art included; Tripo 3D on the owner's paid plan is allowed for UNIT sources, processed to budget in Blender — `tools/units3d/infantry_tripo/`.) The lesson from the Hunyuan
  rounds still holds for any prompt: **never ask for a "game asset" in
  words.** Three text-to-3D attempts saying "game asset for a grand strategy
  game" each came back a toy castle with orange flags and a grass base,
  and the negatives ("NOT cartoon, NO flags") did nothing — that phrase is
  itself what pulls the model toward toy. What works is IMAGE-to-3D from a
  photoreal reference rendered by the project's own Flux pipeline
  (`STYLE_CORE_photoreal_building.txt` + `NEGATIVE_photoreal_building.txt`,
  canvas `C-ICON`): the reference carries the realism and the 3D step only
  has to follow it.
- **Roofs are TILE or SLATE, never thatch** (owner 2026-09-24, on the first
  Hunyuan3D 2.1 house set: "那我们就不用茅草屋顶了，用瓦片效果还不错…可以换成
  不同颜色的瓦片"). The paint turns thatch into a flat, lumpy orange or beige
  slab with none of the reference's straw (and tore cottage_b's roof), while
  a tile roof keeps its courses and reads crisply at map size. Variety comes
  from the tile's COLOUR — red, rose-red, weathered orange terracotta,
  orange-brown, brown-grey, grey slate — not from the roofing material. NOT
  dark brown: the paint turns a dark brown tile flat black and its courses
  vanish (cottage_b, workshop, townhouse_b, 2026-09-24), a black blob at map
  size.
  *Narrowed later that day, on the hand-modelled set: "房顶颜色还是用那种带
  橘红色元素的暖色系比较好看". The houses' tile is WARM orange-red terracotta
  in several shades. Grey slate and a neutral brown-grey on houses read cold
  or lilac, and slate now marks only the church landmarks. The value must
  match the old roofs' measured albedo (roughly (120,30,20) to (80,32,19)).
  Anything lighter reads PINK under the map's sun.*
- **Walls are weathered at the foot** (owner 2026-09-24: "墙根加上有污渍、做旧").
  A clean wall down to the ground reads as CG. The hand-modelled houses
  darken each wall toward a damp earthy colour below ~2.6 m, as vertex colour.
  Limewash is kept a muted lime-ochre, never near-white (the owner found it
  too bright twice).
- **Hand-built, not machined: no edge dead straight, no corner knife-sharp**
  (owner 2026-09-24, on the hand-modelled set: "边边角角太直了，太sharp了，
  应该有点石头或者木质材质的不规则的感觉，而不是完全整齐的线条"). Stone and
  timber are irregular materials; a house of perfect boxes reads as CG. The
  kit rounds wall and roof corners, sags every ridge toward its middle as a
  smooth bow (sampled finely along the ridge; a coarse sag reads as a broken
  roof, not an old one), lets the roof's eave waver, and lays each beam a
  little off true. It never leans the house (it stands plumb) and never
  bows the walls (invisible at map size, and costly).
- **Colour a little richer than true** (owner 2026-09-24: "颜色可以再鲜艳一
  点"). Saturation rises by a SHARE toward full at the same lightness, so the
  grey walls gain as much as the red roofs and nothing gets lighter; stone
  takes half the share (at the full share it turned golden sandstone) and
  slate none (it turns olive).
- **A building stands plumb and nothing of it is ever under the ground**
  (owner 2026-09-24: "要垂直于地面，不可以被地面遮住部分"). On a slope it
  stands on the HIGHEST ground under its whole footprint, and a stone
  foundation carries the downhill side. It is never tilted with the slope,
  and its uphill wall never bites into the hill. Ground too steep for a
  modest foundation gets no house at all (the bake refuses the plot).
- **A settlement is laid out ROUND its landmark** (owner 2026-09-25: "所有房子
  几乎都一个方向，而不是围绕着标志性建筑展开…标志性建筑要在中间附近"). The
  landmark is the centre the town grows from, wherever it had to move to
  (off water, off a slope). An open square surrounds it, with a lane round
  the square whose houses face in across it. The capital's houses had been
  packed round the burg's registered point, all to one side of a palace that
  had moved 59 m onto level ground.
- **A landmark stands on a levelled terrace, and a house's footing follows
  its walls** (owner 2026-09-25: "在斜坡上的房子都加了个很方的底座，看起来非常丑
  和怪异"). The runtime's box foundation filled the mesh's whole bounding box,
  eaves and chimney included, and was dark. It read as a square pedestal.
  Now every house mesh carries its own stone footing traced from its walls
  (a real hillside house's basement). The bake cuts and fills a terrace under
  each landmark and eases it back into the hill, so a palace never stands on
  a 30 m tower of its own stone.
- **Detail that costs nothing goes in the texture** (owner 2026-09-25:
  "窗子…加个窗框，在不影响成本的前提下"). The window's frame, cross and glass
  are a texture on the recess material every window already had, so they add
  no triangles and no draw call. At map size the texture must still average
  to a DARK opening. A lighter first cut averaged to a mauve patch.
- **Variety within the palette, never outside it** (owner 2026-09-25:
  "颜色可以多样化一点，主色调不变，但可以有不同variant"). Each house wears one
  of a few wall and roof tints (the world scene's Houses node, `wall_tints` / `roof_tints`), multiplied
  into its own texture. A tint may be warmer, cooler, greyer or a shade
  deeper, never lighter (pink roofs, white limewash) and never so dark that
  a tile reads maroon or brown.
- **A landmark's sign must be BIG enough to read at map size** (owner
  2026-09-24, on the church's bell-cote and its two crosses: "太小了，根本看不
  出来，把那个钟楼直接换成一个大木质十字架"). One large hewn wooden cross on the
  gable replaces the small detail. A detail that is illegible at 30-50 px is
  noise; enlarge the one sign that carries the meaning instead.
- **A packer reserves the building, not its bounding square.** Each house is
  packed as its own measured rectangle (`width_m` × `depth_m`, in
  `bake_houses.half_extents`). A square of the long side gave a 14 × 10 m
  cottage a 14 × 14 m plot and held a third of every settlement's ground as
  air that no density could win back — the clusters read loose no matter how
  hard the density was tightened, which is the trap that cost two rounds.
  With the rectangle, each group's `house_m2_each_*` sits on its MEASURED
  packing floor (the tightest value at which it still seats its full count on
  flat, fully buildable ground), so the weave is as tight as this layout
  packs rather than as tight as someone guessed.
- **Lanes keep their real width** (3–4 m), unlike the roads and rivers this
  project deliberately draws wider than life for legibility. The owner
  accepted that a true-width lane stops reading past ~2500 m and the
  cluster becomes one solid mass at distance, rather than widen it to
  compensate.
  *Amended 2026-09-21: once every house was scaled ×2, a real 3.5 m lane was
  half a doorway wide between them and the alleys stopped reading at any
  zoom, so `lane_half_width_m` moved with the houses (1.75 → 2.5 m). The
  ruling's substance holds — a lane is narrow AGAINST ITS OWN HOUSES and is
  not widened the way roads and rivers are — but it is now proportional to
  the buildings, not to the real world the buildings left behind.*
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

- **A wargame piece is a miniature, not a monument** (2026-09-24, 3D
  regiments: "模型太大了！比例请改的合理一点"): at 96 px of screen and a
  26 m floor the soldiers towered over towns and read as giants on the
  strategic view. A piece stands a little UNDER a cottage close in (12 m
  floor against 15 m houses) and ~40 px far out — still findable, never
  the biggest thing on the map.
- **A piece is sized by what it IS, not by its tallest prop** (2026-09-27,
  the scanned cavalry: "单独调大unit，更显眼一点"): the upright lance made
  the knight's height 3.3 m, so the constant-screen rule drew horse and man
  smaller than the infantryman. `army_art.csv` `size` 1.5 for cavalry and
  royal (1.3 still read smaller than the foot; 1.8 began to read as a
  monument), and `stand_deg` 55 so a standing horse shows its flank — nose-on
  it was a sliver.
- **A wargame piece has NO base** (2026-09-27: "不满意，请撤除所有底座").
  Two tries were rejected the same day: the flat disc in the realm's colour
  ("太丑，就是一个灰色阴影") and then a modelled plinth — tall realm band,
  bronze lip, earth groundwork with stones and tufts. The figures stand on
  the map's own ground, like the houses ("no base plates"); whose piece it
  is, is the headcount chip's job. Do not bring a base back without the
  owner asking.

- **The MANORS wash is a tincture, not a highlighter** (owner 2026-09-28,
  approving the recommendation). Pastel pink, lemon and cyan at 0.8 over the
  photographic ground read as marker pen; each house keeps its hue at
  `map_manor_saturation` 0.75 and `map_manor_value` 0.8, mixed
  `manor_tint` 0.6 (`ground_look.tres`), so the relief and fields read through it. Desaturating
  alone only made paler pastels — depth (value) is what makes a tincture.
- **A map mark is ink, not a badge.** The weather mark is a bare glyph in
  dimmed parchment over a soft shadow — a black disc with a white glyph, and
  then a gold-rimmed leather disc, were both stickers on the ground.

- **The LEDGER is a star chart, read one web at a time** (owner 2026-09-30:
  a warm black night, one cluster per tab in brass, gules, purpure and
  steel-azure, small stars with a real shine, links shading between
  clusters; it replaces the palette part of the earlier "orrery of brass and
  glass" ruling and keeps its "one web at a time"). A web too dense to read
  (the court's 49 ties) shows one person's ties lit and the rest as faint
  context, not every line at full weight. A fade is set as the eye reads it:
  under linear blending an "alpha 0.25" line on a dark ground reads nearly
  whole.
  Its stars move (owner 2026-10-01: 轻微小幅度晃动，周边带有类似细微电流的感觉):
  a wobble, every star on its own phase, never a group shake; and a current
  at the rim. Then, the same day: "球体周边电流可以更大更明显一点，晃动幅度也可以
  更大更明显，现在太小了像静止的" — motion must READ at a tab's normal zoom,
  several screen px, not a sub-pixel shimmer; judge it in a strip of frames at
  1×, and let the links' ends move with their stars.
  "在court那里king aldric valorin关联的几个任务不应该都是几个彩色实线，非常突兀，
  应该和周边类似": one web wears one palette — a tie's feeling is its width and
  its card, never a foreign hue; the lit web is told by opacity.
  "3个cluster布局可以靠的再近一点，node更分散一点": the clusters close enough
  to read as one sky, each loose enough to read its stars — told apart by
  colour and haze, not by empty space. Spread means the CORE the player
  reads (the King's own ring), not only the edge; and each view keeps its
  own ground — the flat chart's clusters must not bleed into one another.

## Colour and value
- **Greyscale art takes the realm's hue; colour art keeps its own.** Symbols
  and estates carry VALUE only and are multiply-tinted; photographs, icons,
  portraits and arms keep their colour.
- **Lighten in the file, not with alpha.** A translucent mark cannot occlude
  the one under it.
- **Dark UI after Crusader Kings III:** parchment ink on dark leather, gold accent. Test
  contrast, not hexes. *Since 2026-10-01 only for what is held up to the eye
  (windows, events, menus, the council column); the main screens lie on the
  war table (see Panels).*
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

## 事件插图的硬规矩（2026-09-21，序章 21 张图，五轮才收敛）

1. **画布拼在 prompt 末尾，抢得过场景词。** `STYLE_CORE` 在最前面说的"12–14 世纪"压不住场景自己的名词——写 `livery` 就出拿破仑制服，写 `ministers` 就出 19 世纪会议室，写 `travelling gown` 就出维多利亚裙。凡是要钉死的约束，写进 `[C-...]` 画布，不要指望风格核心。
2. **画面里有纸，就一定会长出假文字。** 负面词里的 `printed typography, lettering` 挡不住账簿、请愿书、条约。唯一有效的办法是**让纸本身看不见字**：合上、折起、背过去、只露封蜡，或者以极斜的角度只看得见尺线；并且在 subject 里明写"看不见任何字"。
3. **一个场景里有国王和别人打架，模型会把王冠戴错人。** 与其反复重摇，不如**把主角移出画面**——"从国王自己的位置看出去，画面里只有他伸出的手和袖子"，歧义就没了。

附带：Flux 把 `corn` 画成玉米。中世纪欧洲的麦田一律写 `wheat`，并加 `no maize`。

4. **手和脸糟，多半是构图问题，不是参数问题。** 同 seed 下 32 步对 20 步几乎没差别。一条 12:5 的宽带里七张脸、十四只手，4B 模型一定崩。画布里规定"最多三个清晰人物，其余小而虚"，并且**每只手都要有交代**——平放且手指并拢、交叠、握住一个点名的东西，或者出画。越肩构图（前景人物只有后脑和肩膀）是最省事的解法。
5. **画布只禁止，不规定。** 为了压时代漂移往画布里写"锁子甲、头盔、鸢形盾"，结果每张图都生效：大臣成了士兵，织工成了卫兵。改成"没被点名为士兵的人不许穿甲"，需要盔甲的场景自己写。
6. **人会被画两遍。** "站在他们身后的门口"经常变成"旁边一个、门口一个"。要么明写"画面里只有 N 个人"，要么把那个人挪进主群。

## The regiment pieces (owner 2026-09-27, round 2)

- **A miniature grows with the zoom, then holds; far out it is a counter.**
  A piece held at one screen size at every zoom read wrong ("随着镜头的缩放，
  兵人大小没有变化这是不对的"): it is one world size (~20 px at the opening
  view) growing as the camera comes in, capped close in so it never towers
  over the houses, and a flat square counter once the scale bar reads 50 km.
  Bigger is not better: the cavalry at 1.5× was ruled wrong ("应该更小一点").
  Then, the same day, "骑兵和步兵的size稍微再调大一点点": +15% (ref 26→30 px,
  cap 36→41) — "a little" means a step you can see side by side, not one
  that makes a piece loom over the houses (+25% did).
- **The owner names a zoom by the SCALE BAR**, not the camera's height
  ("是比例尺，不是高度"). Put zoom thresholds in scale-bar units.
- **A selection emphasises the line that is already there.** The clicked
  province is its own black dashed seam, heavier and full ink — never a new
  gold solid line laid over it ("一个黄色实心线…很丑").
- **Status reads as two thin bars on the counter**, red (readiness) over
  yellow (supplies), in the counter's own width.
- **A miniature casts its shadow** — the table-top look wants it.
- **A garrison is its town's counter, not soldiers in the streets**
  (owner 2026-10-06, choosing A over standing them outside the houses or
  keeping them): a piece is wider than any open ground inside a town, so
  quartered regiments buried the lanes and their counters stacked over the
  town. One counter on the town — a tower, the crown with the royal
  regiment, "2100 (2)" — no bigger than a piece's chip close in; a regiment
  shows its figures again when it marches out.

## The infantry figure (owner 2026-09-29, the blueprint man-at-arms)

- **Armour is worn field kit, not a museum piece**: no mirror of the sky
  ("为什么铠甲上会有环境反光"), dirty and old ("太干净太亮了，做脏做旧"), the
  shield old painted WOOD, rivets BRASS on the plate edges. But dirty is
  judged IN THE GAME: a dark, fully metallic plate that looked grimy in Blender
  was a black silhouette at the map's 30 px. Mid-grey steel, metallic ~0.25,
  grime and rust over it; Blender's studio light then makes it look pale —
  that is expected.
- **A close helmet reads by its openings**: a real eye slit under a jutting
  brim (a gap you see into, not a painted line), breaths in the visor, the
  visor pointed and slanting up — but held close ("面罩太突出了，收进去一点").
- **Cloth moves and matches**: the cloak is the shield's colour ("和盾牌同色")
  and streams on the march ("走路的时候披风要飘动"); a spear on the march is
  SHOULDERED, tip up and back ("长矛应该扛在肩上").
- **A piece's colour must face the camera**: standing square to the view, a
  shield hung flat along the arm shows only its edge and the figure is a grey
  knight with no signature (independent critic); the shield turns to the
  front-left.

## The infantry's actions (owner 2026-09-29/30, the Tripo man-at-arms)

- **A walk is square**: the feet point where he goes and pass under the
  hips, never splayed ("士兵走路外八字太严重，很不美观").
- **Standing at ease is not a garrison** ("你现在的驻防动作其实应该算是待命动作"):
  STANDBY is the relaxed stance with the spear grounded; GARRISON is a
  fighting guard, played only under that order.
- **The guard is a fighting stance, not a pose on a plinth**: the left foot
  forward under a bent knee, the right leg back and the stance open, the body
  low, the shield up to the chin, the spear held overhand LEVEL with the eyes
  ("左腿弯曲向前，右腿在后，侧向打开…盾牌抬起到下巴附近"; "长矛…和士兵的视线方向平齐").
  Nothing invented beyond what was asked ("脚谁让你交叉的？").
- **Joints bend as a body bends**: no wrist wrung about the spear, no arm
  thrown straight through its shield, no plate torn across a joint
  ("驻防的手臂动作太扭曲了").
- **The steel is matte and warm, like the cavalry's**: Tripo's delit silver
  read white on the map; toned down, roughness at least 0.55.

## The Tripo knight (owner 2026-09-30, the cavalry remade the infantry's way)

- **Keep the design; change the maker**: the Tripo knight wears the in-game
  look (plate, a charcoal dappled horse with a white star, no barding, a
  green saddle cloth with a brass edge, a green heater with a white pale,
  an upright lance) — "沿用现在设计".
- **The shield is big and rides his back** ("盾牌太小，盾牌要背在身后"),
  with NO strap ("盾牌不要那根带子"); it is modelled on its own, not
  generated on the man ("盾牌单独做，骑士不带盾出图" — every picture of
  a shield "on the back" came back on the arm).
- **On guard the shield comes to the arm** ("用第一种"): GARRISON takes it
  from the back to his near arm, raised before him; every other clip wears
  it on the back.
- **A mounted piece gets a STANDBY too** ("加STANDBY"): the horse at rest,
  the lance upright — not the guard.

## Sunlight (owner 2026-09-28)
- **The sun models the ground; it never covers it** ("日照产生的阴影实在太厚重太大了…不要影响玩家的视线"). A cast shadow is a light wash
  you can read the map through (`map3d_sun_shadow_opacity` 0.45, soft edge),
  and the sun stays HIGH all day (-52..-60°) so shadows stay short. A low sun
  behind the map (facing the camera) blacks out every slope turned toward the
  player. No shadow opacity can fix that: the slope has only the ambient
  light, and SSAO darkens it further. So keep the sun high, and keep the fill
  and SSAO gentle.
- **Dusk is an evening, never a filter** (owner: 北边半圈当作黄昏). Warm the
  direct sun ALONE and lightly (the blue down ~10%, not ~30%): snow stays
  near-white, grass stays noon's green, the sea keeps its blue. Light a backlit
  slope with a fill light from the camera's side; darkening the whole map
  hides it too.


## Weather (owner 2026-09-29)
- **Weather is a patch, not a blanket** ("天气效果不用铺满整个省份，再小一点").
  A province's rain or snow is a soft, irregular cell round its centre that
  fades out well before the border, with clear country between the cells.
  The rule stays province-wide (the whole province slows a march, and its HUD
  mark names it). Only the LOOK is smaller than the rule.
- **Kinds of the same family must part at a glance, even on a paused clock**
  ("暴风雪和普通雪再拉开一点差别"). A blizzard is not just more flakes. It
  greys its ground blue-grey where snow stays white, and its flakes streak
  sideways where snow drifts down. A difference that only shows while the
  clock runs is not enough, because orders are given paused.

## The regiment's formation (owner 2026-09-30)

- **Strength reads as a block of figures**: 满员 3×3, 减员 前中后 1/2/3, 残兵
  前后排 1/2 ("单个军事模型的密度增加"). A DENSE block, not three squads: at
  1.1 footprints apart the 3×3 split into three files wider than a town; at
  0.7 the lances ran through the next horse. 0.85.
- **Nine must READ as nine**: a piece stands square to the camera, so ranks a
  man's (short) depth apart stacked into one grey totem and nine read as three
  (independent critic). The infantry's ranks stand 1.6× further apart
  (`army_art.csv` `rank_depth`); the horse's own length already spaces its.

## 2026-10-01 rulings
- **Roads read at a glance** (owner: 道路太细了，请加宽一点). A road ~25 m wide
  (trail 16 m, screen floor 7 / 4.5 px) — drawn far wider than life, like the
  rivers and houses; a 14 m road was a hairline at the playing zoom.
- **Text that floats over paper keeps the chip's own light ink** (owner: the
  town card's icon tooltip was 完全看不见). A theme set for one surface must
  never leak into a popup drawn on another.
- **Woods are photographs on photograph ground** (owner: 树木…非常丑非常假).
  Smooth low-poly crowns read as CG moss on the aerial ground however they are
  tinted; crowns are cut-out aerial photographs of real trees, warm olive,
  over a DARK floor so the gaps between crowns read as depth.
- **Fortifications are as refined as the houses, never kit boxes** (owner
  2026-10-01, on walls and a pier built from the house kit's primitives:
  城墙和码头都太丑太简陋了，我要更精致的感觉，走game arts流程). Walls, towers, gates
  and piers go through the art route the houses took — photoreal references,
  Tripo, processed in Blender — not boxes and merlons laid by script.

## 2026-10-02 rulings
- **The far zoom stays the real 3D world — no strategic "paper map"** (owner,
  rejecting the CK3 / Humankind option of the performance report: 缩远后切换成
  战略纸图，隐藏房屋和树 — 不同意). Performance at the far zoom is won by LOD,
  shadow distance, instance budgets and CPU work, never by swapping the
  landscape for a flat stylised map or hiding houses and woods wholesale.
- **Costly finishing effects are spent where they show: up close** (owner,
  choosing "按缩放切换" from the AA / SSAO sheets). MSAA 4x — the 2026-09-24
  ruling against stair-stepped house edges — and SSAO stay at the zooms where
  a house or a crown is big enough to show them; at the opening view and
  beyond, where matched shots showed no difference, the high tier draws SMAA
  and no SSAO. A finishing effect that cannot be seen at a zoom is not paid
  for at that zoom.
- **The council seal is a mark, not a medallion** (owner: 右上方的印记太大了，缩小它，
  再往右上方角落移动点). On the war table it sits small (64 px) and tucked into
  the map sheet's top-right corner; the map is the subject, the seal an order.
- **A screen arrives the way its object would** (owner: 点击war room的进入动画太突兀，
  做成一个从上往下的卷轴拉下来即可). The WAR ROOM comes down like a hanging scroll
  on a turned roller over what it covers — not a panel that widens while another
  rolls away.
- **The plotting map is a flat tactical chart on parchment** (owner: war room的地图
  改成纯2d平面图，战术地图，羊皮纸风格，不要3d; 战术地图加上经纬度的格子). Ground is
  told by contours on a flat sheet, never a raised relief; the sheet is mottled,
  foxed, rim-darkened parchment, not white vellum; a graticule with a chequered
  degree border and its figures marks it as a military map. Only the sheet went
  flat: the room, its table and the tin pieces stay 3D (owner's choice).
- **The war table's regiments are carved wooden pieces** (owner 2026-10-06: 固态的军事单位棋子…
  做旧，木头材质…木质底座下宽上窄，刷亮色木漆，外圈一圈金属环; 底座漆色按国家颜色; 一团一枚).
  One aged dark-oak piece per regiment on a round tapered plinth with an iron band; the
  lacquer is the realm's colour and is BRIGHT by the owner's word (not the muted base
  tincture); strength lives on the tag, not in a count of figures. The wood stays satin
  (`wood_roughness_min`): at Tripo's own gloss the oak read as polished bronze (critic
  2026-10-06). A Tripo mesh is welded before it is collapsed, or its seams crack open and
  the parchment shows through as white speckle.
- **The staff's plans are wax crayon on the parchment** (owner 2026-10-07, approving style A of the
  plans spec over ink-and-wash). NATO's overlay translated into woad-blue and minium-red crayon —
  broad bands whose wax skips on the paper's tooth with a darker pressed rim — and sepia pen for
  phase lines and objectives, so a plan never passes for the survey's own ink. A supposed enemy is
  the same carved piece in pale boxwood with a pencilled tag: oak is ours and real, translucent is
  intel's belief. The critic's first pass: an axis must lead the sheet, never a hairline (12–22 mm
  on the 1.4 m table), and teeth stay small beside it.
- **An index chart shows the land it indexes** (owner: 选择地图的格子那个纸也换成羊皮
  纸，然后画上整个大陆地图的形状). The sheet index is parchment with the continent's
  inked coast and water lines, not a grid of dots.
- **The people stand by their seal, not over the map** (owner 2026-10-02: 选A2 横列
  布局). The council's miniatures run in one row from the seal along the map's top
  edge — the independent critic's first choice too, because a column down the right
  edge outweighed the seal and sat on the map's towns. A marked minister is told
  by light and by wax (a gold ring, a drop of the seal's own oxblood, the others a
  shade darker), never by a bright notification dot.
- **An order the eye already knows needs no caption** (owner 2026-10-02: 移除蜡封下面的
  enter the council的字，改为tooltip). The seal says what it does on hover; words
  under it were a label on a label.

## Walls and harbours (owner 2026-10-04)

- **A town wall is ONE continuous line laid on the ground** (城墙…应当就是连续的根据地形铺在
  地面上). It rises and falls with the hill, never steps module by module into a sawtooth,
  and stands on no house footing (城墙不应该有那些类似房屋才有的地基): its own masonry runs
  into the ground. Towers are punctuation — at sharp turns, gates and the wall's ends —
  never a tower every few modules (加入了过多的城塔楼).
- **A harbour belongs to its town** (港口的结构应当和城市融为一体). The pier stands on the
  shore nearest the houses.
- **A harbour keeps its own proportions** (owner 2026-10-05: 这岩堡大小太不合理了). A castle
  grown to meet a town on a plateau stood three houses tall: never scale a model to
  bridge the terrain — a road links a town on its height to the harbour below.
- **A wall closes** (owner 2026-10-05: 有城墙必须要合拢). No gap where the sea, a river or a
  harbour meets it: the line runs along the shore and the cliff top, crosses a river by a
  water gate, and opens on its pier by a quay gate.
- **A moored ship lies alongside its quay, square to it** (船要规整的贴着码头停留). Not
  anchored off the pier's head, not a ship-length away.

## The map's light (owner 2026-10-05, choosing B3: "用 B3，底座 0.5")

- **The sky models the land where the sun cannot.** With the sun held high, the
  relief read flat at the opening view; a baked sky occlusion (valleys and a
  terrace's foot darker, no direction) gives it form — full far out, about a
  third up close, where a 40 m texel's dark read as a burn beside a house.
- **Depth is blue air on the far third, never grey fog.** The depth haze takes
  a blue light of its own, not the sky's grey; a stronger, greyer haze (C) was
  rejected as fog.
- **The grade only takes the acid out.** Saturation 1.15 → 1.05: the lime turns
  golden olive while terracotta roofs and gold crops keep their warmth; muting
  further (C) dulled the roofs to rose-brown and the stubble to khaki.
- **Woods are darker than the grass, the sea deepens offshore, and a river wears
  the sea's water.** A pale coastal shelf against a navy deep read as an outline
  round every coast, and a dark deep in a bay as a stain: the steps between the
  bands stay modest.
- **A piece's base on the plotting table is a muted tincture, not the raw realm
  colour** (`war_base_darken` 0.5): at 0.25 a light realm colour was a sky-blue
  slab pasted on parchment, at 0.65 the hue was lost to black.
- **An animated figure holds only poses a human body can make, from every
  view** (owner 2026-10-07, the archer's run: "呈一个C字形，人类不可能有这种形态…
  大臂和小臂应该是一个类J字形"; earlier "左手手腕和小臂扭曲严重"). A prop's angle
  never wins over the arm holding it: a wrist bent to its limit on a straight
  arm, or an elbow pushed out by a shoulder turn, reads as a C; a forearm
  twisted at one point reads as a wring. Judge the limb from the side, the
  front AND behind, with the twist measured (`validate.limb_twist`).
