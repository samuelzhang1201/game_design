# Reference sheets for 3D unit figures (人物 / 兵人)

The image step of every 3D unit (infantry, archers, cavalry rider, royal, courier, spy, any new figure). ComfyUI's work ends at these images; the model is built from them (Tripo on the paid plan, then the owner's Blender: `tools/units3d/`). The hand-drawn 2D art the player sees keeps its own poses; this rule is for the 3D references only.

## The rule

1. **Person and gear are generated separately.** The figure is bare-headed with EMPTY hands. Every weapon, tool and carried or worn piece (sword, spear, bow, quiver, shield, buckler, bags, banner, **helmet**) is its own image on its own plain background. A mounted figure is split too: the rider alone (T-pose) and the horse alone (plain standing, tack included, no rider).
2. **Each figure gets three views, FRONT, SIDE and BACK, all in the standard rigging T-pose** (the Mixamo T-pose, below): arms straight out sideways, palms down, legs straight under the hips, toes forward, feet flat, facing squarely front / in profile / away. The T-pose is the pose a bone rig expects (棒骨 / 绑骨), so the weights need no un-posing.
3. **The three views are one figure**: identical proportions (head height, shoulder width, torso, leg length, the same feet-and-head lines across the three) and identical clothing (every colour, seam, belt, fold, pattern, wear). Orthographic, flat even light, plain grey background, no shadow, no perspective.
4. **Gear gets the same treatment where it matters for modelling**: a piece with a front/side/back that differs (shield, helmet, quiver) gets its own front / side / back; a long thin piece (spear, bow, sword) gets one orthographic view along its length plus one end-on or cross-section if the profile is not obvious.

## The Mixamo T-pose (for an Auto-Rig Pro rig driven by Mixamo clips)

Retargeting copies each bone's turn FROM ITS REST POSE, so whatever the generated figure does differently from Mixamo's own T-pose is carried into every clip. Measured on the ARP knight (2026-10-18, `tools/units3d/soldier_arp/`): palms facing forward made every hand face up; legs turned out 20° made a heavy toe-out walk; ankles 17 cm off the centre (Mixamo: legs vertical) tripled the step width. Each cost a rest-pose fix and a rebuild of every clip. Ask for the pose exactly:

| Part | Mixamo T-pose | Fails as |
|---|---|---|
| Arms | straight out sideways, level with the shoulders, elbows straight | A-pose, raised or drooping arms, bent elbows |
| Hands | palms DOWN, thumbs pointing forward, fingers straight and slightly apart (five readable fingers: ARP detects them), empty | palms forward/up (thumb above the arm), fists, mittens |
| Legs | straight and VERTICAL, ankles under the hip joints (feet about a fist apart) | legs spread, A-stance, knees bent |
| Feet | parallel, toes straight forward, flat on the ground | toes turned out (外八), turned in, on tiptoe |
| Body | upright, head level facing forward, shoulders level | twist, lean, tilted head |
| Proportions | realistic adult (about 7.5 heads) | chibi / big head: the clips are made for real proportions |

Clothing and armour that rig cleanly (a generator fuses touching layers into one surface, which then cuts through itself in motion):

- A clear gap under the arms and between the legs; no cloak, wide sleeves or long robe joining arm to torso or leg to leg.
- Layers kept few and close: plates riveted flat onto the mail or cloth, no loose skirt of plates hanging over a second skirt of mail; a mail or cloth skirt that ends above mid-thigh, split front and back. The plate-over-mail skirt was this knight's worst clipping.
- Metal named as metal (polished steel plates, steel mail) and the 3D generation run with PBR, so the model carries a metallic-roughness map; a colour-only export renders steel as cloth (`metal_map.py` authors one after the fact).

Prompt words: *standard Mixamo T-pose, arms straight out horizontally at shoulder height, elbows straight, palms facing down, thumbs forward, fingers straight; legs straight and vertical, feet directly under the hips, feet parallel, toes pointing straight forward; standing upright, head level; clear gap between arms and torso and between the legs.* Negative: *A-pose, palms forward, palms up, fists, wide stance, legs apart, toes turned out, bent knees, cape, long robe, layered skirt.*

Check the Tripo model before rigging (the numbers above are measurable): the thumb sits in FRONT of the hand, not above it; foot and knee yaw about 0°; ankles about 4–5 % of the height from the centre line. Fix a failing one in the rest pose before any clip is retargeted.

## How (generate.py, both models, owner picks)

- Design first (Z-Image + Qwen, the usual batch); the owner picks.
- Views from the PICK, never re-drawn from words: `generate.py --images <picked design> --instruction "<…>"` (see `assets/imagegen/README.md`, edit mode). One edit per view, same seed family, the previous accepted view passed as a second `--images` reference so proportions and clothing stay locked:
  - front: "the same person in a standard Mixamo T-pose, arms straight out to the sides at shoulder height, palms down, thumbs forward, empty hands, legs straight and vertical with the feet under the hips, toes pointing straight forward, bare head, no weapons or carried equipment, front view, orthographic, plain grey background"
  - side: "… the same person …, right-side profile …"
  - back: "… the same person …, back view …"
- Gear: "only the <piece>, alone, orthographic, plain grey background" from the picked design.
- Lay the three views out on ONE sheet (a 3×1 canvas, equal figure height, one baseline) when a tool wants a sheet; keep the single images too.
- Upright, full body in frame with margin, head and feet not cropped.

## Check before it counts (visual-review loop)

Overlay or line up the three views: head top, shoulders, hands, crotch and soles must sit on the same lines; compare clothes view by view (a belt, a cloak edge or a stripe that appears in one view only fails the sheet). A view that drifts is re-edited from the front view, not accepted. Reject: hands holding anything, a bent elbow or tilted torso, a hat, a rider on a horse, a shadow, a background that is not plain.

Ask the owner before queuing a batch (`ask-before-queuing-generation`).
