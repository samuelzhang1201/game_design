# The cavalry piece becomes the ARP heavy knight on the armoured horse

Owner 2026-11-21: 替换现有骑兵 — every cavalry regiment becomes the heavy knight made 11-17..21 (the Tripo
heavy knight rigged with Auto-Rig Pro, a 2.7 m spear, the ARP armoured horse, eighteen clips; source
`assets/3D/model_wip/blender_output/heavy_cavalry/rider_clips.blend`, git-ignored, its README the whole
authoring record). The old Tripo knight (`tools/units3d/cavalry_tripo/`, `cavalry_rig/`) and its look
rulings (green saddle cloth, the shield on the back) are retired. The template of this swap was the
infantry's (`2026-11-16-infantry-arp-shortsword-design.md`).

## What changes

- `assets/3D/units/cavalry/cavalry.glb` and its three atlas JPEGs are rebuilt by
  `tools/units3d/cavalry_arp/game_export.py` (new; README there). `scenes/models/units/cavalry.tscn` is
  unchanged: its material override still lands on `cavalry_rig/Skeleton3D/cavalry` and reads the same
  file names. The look in the editor is untouched.
- Skeleton `cavalry_rig`, 120 bones: the knight's 70 deform bones + the spear socket `cc_weapon.r` under
  a bone `Saddle` riding the horse's `spine_02.x`, the horse's 48. The horse's legs carry the names the
  pivot solver binds (`FrontScapula`..`FrontHoof`, `HindThigh`..`HindHoof`); the rider's head is `head`
  (the chip's bone), the horse's `head_h`, the other horse bones `h_*`. Rest = STANDBY's first frame.
- Mesh 23,929 tris (old figure 19,047): knight 12,000 (from 47,122), horse 10,525 (as made), spear
  1,407 (from 90,291: head and butt collapsed, the shaft an 8-sided tube). One material on a 4096 x 2048
  atlas (old 2048²): knight 2048 px, horse 1536 px, spear 512 px.
- Clips, my defaults (the owner may re-map any): MARCH ← MARCH (the run), STANDBY ← STANDBY,
  GARRISON ← GARRISON, DEFEND ← DEFEND (the rear), ATTACK ← ATTACK_REAR_LOOP (in place: the rearing
  three-stab loop; ATTACK and ATTACK_STAB gallop and would run on the spot), PIVOT_LEFT / RIGHT ← the
  source turns (fixtures the provider seeks, never plays). MARCH, STANDBY, GARRISON, DEFEND and ATTACK
  loop. Not shipped: DEATH (no cavalry caller — `army_art.csv` has no duel column for the arm — and the
  rider thrown 2.3 m off would widen the body envelope the footprints come from), KICK, HEAD_BUT, GRAZE,
  RIDE_WALK / RIDE_TROT, ATTACK / ATTACK_STAB / ATTACK_REAR, STAND_REST / STAND_RISE.
- `cavalry.glb.import`: ATTACK and DEFEND added to the loops; `animation/remove_immutable_tracks=false`
  (ATTACK holds the lance in the reverse grip, a constant half turn on `cc_weapon.r`: dropped as
  immutable, the figure would show the usual grip).
- `army_art.csv` cavalry: `stride_m` 2.4224 (measured, below), `size` 1.075 (below).
- `cavalry_pivot_plan.json`: `march_phase` 63/104, new key `stand_clip` MARCH, read by
  `Map3DCavalryLocomotion.bind` (below). The royal piece's solver is not touched.
- `tools/units3d/measure_unit_bodies.gd`: the cavalry's attack bone is `cc_weapon.r` (was `Lance`).
- Re-issued: the cf01 measurement of the cavalry (`measurements.json`, the cavalry entry and the hashes of
  the files this step changed), every locomotion certificate, `data/army/unit_locomotion.csv`,
  `units3d.json`, the art kit's cavalry spec (`specs.json`, the zip).

## Export findings

1. **The source run does not touch the ground behind.** Measured in Blender on the source's own
   deformed mesh: the left hind never comes nearer than 44 mm, the right hind 11 mm, and the fronts skate
   (the horse pipeline left the run's fronts unpinned). The certifier's hover and slide bounds (29 mm)
   would fail. The export resamples the 13-frame run 8 keys a frame (as the old cavalry MARCH was) and
   locks each hoof's stance: held rigid at its mid-stance pose, set on the ground and carried straight
   back at the run's speed, the offset eased out over 2 frames either side, the leg by two-bone IK with
   the pastern kept. Each stance is the longest part of the hoof's low window whose hoof stays within
   5 cm of that straight path (a front hoof that rolls through its low window would otherwise need 34 cm
   of correction). Offsets 4.7-10.3 cm, no IK reach clamped, planted slide 0, no key under the ground.
   Stances (of 104 keys): left hind 63-70, right hind 39-53, left fore 84-1, right fore 63-91.
2. **The glTF exporter samples at the scene's fps.** The dense MARCH is exported alone at 240 fps and
   its channels moved into the 30 fps GLB (`_transplant`, the old cavalry's `march_transplant` method);
   the import already bakes at 240.
3. **The pivot stand.** The royal solver's stand is STANDBY's first pose seated; the armoured horse's
   Idle stands its left fore 22 cm ahead of the right, and from the run's body the solver could not set
   that hoof down (`FrontHoof.L:constraints_not_solved` on 39-51 of 650 sampled phases at every candidate
   hold). The cavalry's stand is now the held MARCH pose with every hoof seated: every phase of the turn
   grid solves. A stopped cavalry piece already holds that MARCH pose (the consumer contract), so its
   turn steps round from it.
4. **The hold phase.** The run's only two-hooves-down keys are 63-70 (left hind, right fore) and 84-91
   (both fores; both hinds 0.26-0.56 m up and flexed). 63/104 is taken; the other two hooves are 131 /
   124 mm up there. 7/16 (the old canter's) left only the right hind planted, where the step schedule's
   float rounding broke a contact boundary.
5. **Decimation and bake** (blender-decimate-quality). The knight COLLAPSE merged the Tripo atlas's
   thousands of UV islands (gilt edges and lame lines smeared, a normal-transfer variant shaded a dark
   triangle across the breastplate). Per the skill's section 4 the low knight and spear are unwrapped anew
   (Smart UV Project, packed) and their colour, metal-rough and tangent normals baked from the source
   (Cycles, selected to active, EMIT for colour since a DIFFUSE colour pass is black on metal). Shading:
   sharp at 45° + Weighted Normal. The skill's weld and normal recalc are skipped on the knight: its parts
   are cut apart on purpose (k2) and its winding kept (k6).

## Measured

| | Old Tripo knight | Heavy knight |
|---|---:|---:|
| MARCH | canter, 16 frames re-keyed 128 | run, 13 frames keyed 104 |
| `stride_m` | 2.4 | 2.4224 (the hinds' planted speed 0.023292 m a key x 104) |
| Rest height (lance tip) | 3.326 m | 4.030 m |
| Rider's head bone at rest | 2.18 m | 2.289 m |
| `size` | 1.0 | 1.075 |
| Tris / bones | 19,047 / 53 | 23,929 / 120 |
| Body radius over every clip (cf01) | 803.4 m | 798.7 m |
| k (world m per model m) | 20.4973 | 18.1876 |

`size`: at 1.154 the rider's head would stand as tall on the map as the old knight's (the upright lance
makes the rest mesh 21 % taller, and the map scales a figure by its rest height). But the run at full
stretch reaches 2.20 model m from the figure's origin (the old canter 1.96), which at 1.15 measures
855 m against the arm's 804 m footprint. The footprint is engine state (body motion, formations,
hashes), so this step keeps it and takes the largest size inside it: 1.075, the rider 7 % lower on the
map than before. Growing the footprint instead is an owner decision for its own step.

Decimation gate (`audit_decimate`), knight, against the source's own audit:

| | Source (self) | Decimated | Gate |
|---|---:|---:|---|
| non-manifold edges | 761 | 767 | the source's (Tripo plates) |
| slivers < 6° | 13.0 % | 4.7 % | under the source |
| soft creases | 8,577 | 2,692 | the source carries custom normals |
| flipped area | 0.009 % | 2.60 %, of which genuine 0.42 % | genuine under 0.5 %; the rest is the plates' other sheet within 6 mm |
| parts | 192 | 190 | 2 specks of 3-4 vertices |
| surface deviation p95 / max | | 0.23 % / 1.08 % of the diagonal | under 0.3 % / 2 % |

The spear's ends fail the parts gate by construction (the Tripo head is 1,988 shards; collapsed they
fuse into one head) and its slivers (27 %) equal the source's (28 %).

## Certificate

`tools/units3d/certify_locomotion.py` on `…/locomotion/cavalry/certificate.config.json` (provider
`Map3DCavalryLocomotion`, entry = exit = hold at MARCH 63/104, stride 2.4224): **NUMERIC_PASS**, digest
`11b6890d…`. k 18.1876, so the R-A bounds are contact 32,990 µm and seam 2,750 µm
(`body_locomotion_cavalry_contact_um` follows).

| Quantity | Sampled | Total (with margin) | Bound |
|---|---:|---:|---:|
| Slide, MARCH | 3,257 µm | 16,683 µm | 32,990 |
| Slide, PIVOT_LEFT / RIGHT | 1,574 / 1,575 µm | 25,546 / 25,819 µm | 32,990 |
| Hover | 488 µm | 9,902 µm | 32,990 |
| Penetration | 0 | 25,127 µm | 32,990 |
| Seams, every required boundary | 1 µm | 1 µm | 2,750 |
| Envelope | | 733 sim m | 804 |
| Skin flags introduced (R-B) | | 0 | 0 |

Planting band inherited from the shipped MARCH: H = -1.61 / -2.72 / -0.08 / -0.41 mm (fore left, fore
right, hind left, hind right). The first run on this figure failed slide at 427 mm: the left fore lay
inside the band for 30 keys after its locked stance and skated there; off its stance a hoof now clears
the ground (README, `LOCK`). Every other arm's certificate is re-issued for the hashed inputs this step
moves (`army_art.csv`, `data/army/balance.csv`, the cf01 measurements), measuring as before.

## Review

Real windows (Forward+/Metal, 2560x1600, `snapshot_screen`; before = origin/main f58735ea in a
throwaway worktree), the same staging both sides: a cavalry regiment marching (`--supply-flow -40,0
--supply-flow-piece cavalry --follow3d 350,30`), regiments at rest (`--zoom3d 350 --at3d 1383.69,676.69`;
both stand on the estuary there, before and after), a cavalry field battle (`--battle-case field
--battle-arm horse --zoom3d 300`, frames 400 and 1800), the +90 / -45 / +180 / +1 µdeg pivots
(`pivot_frames.gd --arm cavalry`), and the run on striped ground (`march_gait_review.gd`).

An independent critic (sheets, `taste.md` and the rubric only) judged the rest and the march clearly
better than the old knight (the arm reads as heavy cavalry at a glance; cloth, leather and steel part;
value separates from water and turf where the dapple-grey horses sank into the hills) and raised, for
the battle and the march:

- **Clone rearing** in the fight: every group figure of a battle starts its non-MARCH clip at phase 0
  (`Map3DUnitRig.play`, one figure per group, slot index 0). Pre-existing for every arm and in a source
  pinned by the royal carrier proof: a follow-up, not this step.
- **Lances through the horses' necks**: the source's gates measure the spear at least 241 mm from the
  horse in the rearing loop; what the crop shows is the lance passing in front of the neck from the
  camera.
- **Arms out, the run's flying gallop, the stiff tail, a red tabard on both sides**: the owner's
  approved authoring (the spear arm opened 14 cm off the trunk, "the march is the run", the knight's
  red); the old figure was also one colour for every realm. Realm colour on the cavalry is a follow-up.
- **Steel too clean and blue, barding chalky at play zoom**: the export's metal factor was bracketed
  0.45 / 0.75 / 1.0 at rest; more metal mirrors the ground's colour (bluer over water), so 0.45 stays
  (the infantry's bracketed value). The texture itself is the owner's 11-20 finish: a polish round is
  the owner's call.


## Follow-ups (not in this step)

- The folio's Take apart (`cavalry_parts.glb`) still shows the old Tripo knight's parts.
- The war room's wooden cavalry piece stays as it is.
- The spy courier borrows this scene (GALLOP / IDLE → MARCH / GARRISON): it now gallops the run.
- The footprint (804 m) against the old knight's on-map size (owner: keep 1.075, or grow the footprint).
- DEATH and the other authored clips wait for their callers (a cavalry duel / fall column).
- STANDBY's hind hooves stand 11 mm off the ground in the source (the solver seats its own stand; the
  resting figure shows the gap only at close zoom).
- The committed cf01 `measurements.json` is stale for the infantry / artillery / axemen on main
  (re-measured today: 998 m against the recorded 912 m); only the cavalry entry is refreshed here.
