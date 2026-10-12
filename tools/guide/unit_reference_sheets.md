# Reference sheets for 3D unit figures (人物 / 兵人)

The image step of every 3D unit (infantry, archers, cavalry rider, royal, courier, spy, any new figure). ComfyUI's work ends at these images; the model is built from them (Tripo on the paid plan, then the owner's Blender: `tools/units3d/`). The hand-drawn 2D art the player sees keeps its own poses; this rule is for the 3D references only.

## The rule

1. **Person and gear are generated separately.** The figure is bare-headed with EMPTY hands. Every weapon, tool and carried or worn piece (sword, spear, bow, quiver, shield, buckler, bags, banner, **helmet**) is its own image on its own plain background. A mounted figure is split too: the rider alone (T-pose) and the horse alone (plain standing, tack included, no rider).
2. **Each figure gets three views, FRONT, SIDE and BACK, all in the standard rigging T-pose**: arms straight out sideways, palms down, legs slightly apart, feet flat, facing squarely front / in profile / away. The T-pose is the pose a bone rig expects (棒骨 / 绑骨), so the weights need no un-posing.
3. **The three views are one figure**: identical proportions (head height, shoulder width, torso, leg length, the same feet-and-head lines across the three) and identical clothing (every colour, seam, belt, fold, pattern, wear). Orthographic, flat even light, plain grey background, no shadow, no perspective.
4. **Gear gets the same treatment where it matters for modelling**: a piece with a front/side/back that differs (shield, helmet, quiver) gets its own front / side / back; a long thin piece (spear, bow, sword) gets one orthographic view along its length plus one end-on or cross-section if the profile is not obvious.

## How (generate.py, both models, owner picks)

- Design first (Z-Image + Qwen, the usual batch); the owner picks.
- Views from the PICK, never re-drawn from words: `generate.py --model qwenedit_fast --images <picked design> --instruction "<…>"` (see `assets/imagegen/README.md`, edit mode). One edit per view, same seed family, the previous accepted view passed as a second `--images` reference so proportions and clothing stay locked:
  - front: "the same person in a T-pose, arms straight out to the sides, palms down, empty hands, bare head, no weapons or carried equipment, front view, orthographic, plain grey background"
  - side: "… the same person …, right-side profile …"
  - back: "… the same person …, back view …"
- Gear: "only the <piece>, alone, orthographic, plain grey background" from the picked design.
- Lay the three views out on ONE sheet (a 3×1 canvas, equal figure height, one baseline) when a tool wants a sheet; keep the single images too.
- Upright, full body in frame with margin, head and feet not cropped.

## Check before it counts (visual-review loop)

Overlay or line up the three views: head top, shoulders, hands, crotch and soles must sit on the same lines; compare clothes view by view (a belt, a cloak edge or a stripe that appears in one view only fails the sheet). A view that drifts is re-edited from the front view, not accepted. Reject: hands holding anything, a bent elbow or tilted torso, a hat, a rider on a horse, a shadow, a background that is not plain.

Ask the owner before queuing a batch (`ask-before-queuing-generation`).
