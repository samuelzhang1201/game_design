# Cluster formations: activation plan

Date: 2026-11-10. Goal: cluster formations switched on in ordinary campaign play. Base: `origin/main` at `a78baa73`.
Spec: `docs/superpowers/specs/2026-10-25-cluster-formations-design.md`; task plan: `2026-10-25-cluster-formations.md`.
Owner rulings: `docs/reviews/cluster-formations/owner-rulings-2026-11-10.md` (R-A to R-F ruled, R-G pending).
Ownership: a Claude Code session carries this plan (R-E). One node is one PR with an independent review and every
required check green; parallel lanes take disjoint files (R-F).

## Rulings

| Ruling | Decision |
|---|---|
| R-A contact bounds | Penetration, stance hover and slide per stance ≤ 0.60 world m; seam jump ≤ 0.05 world m; per-arm `contact_um` in A.3 |
| R-B skin diagnostic | Thresholds unchanged; a flag fails unless the shipped native pose at the same phase is itself flagged |
| R-C certification | Dense native sampling with a velocity margin plus real-window review; no continuous-domain proofs |
| R-D Gram predicate | 1e-6 relative |
| R-E ownership | Claude Code supersedes the Codex pairs and registry; #201 and #221 continue as new PRs; #231 and #236 are evidence |
| R-F parallel | CF09–CF13 beside CF06; CF07b beside CF09 |
| R-G CF24 targets | Pending: set before the validation seeds run |

## Status

| Node | State | PR |
|---|---|---|
| R0 RULINGS-DOC | this PR | — |

Update this table as each node merges.

## A. Contact bound evidence

### A.1 Scale: model millimetres to world metres to screen pixels

Every residual in the contracts is in **model metres** (the GLB's own units, "scale 1").
The game draws a piece at one world height at every zoom (`Map3DUnits.height_m`,
`scripts/map3d/map3d_units.gd:33`):

- reference box height `H = map3d_unit_ref_px * zoom_start_scale / map_scale_bar_max_px * m_per_px`
  `= 12 * 25 / 220 * 50 = 68.1818` world m (`data/screens/map3d/balance.csv:136,60,17`; pack `m_per_px 50`).
- drawn figure height = `H * size` (`data/screens/map3d/army_art.csv`); world scale `k = H * size / model_h`.

| Arm | model height h (m) | size | drawn height (world m) | k (world m per model m) | source |
|---|---|---|---|---|---|
| infantry | 1.604161 | 0.62 | 42.273 | 26.3519 | measurements.md:13 |
| artillery (infantry placeholder) | 1.604161 | 0.62 | 42.273 | 26.3519 | same model |
| archers | 2.264974 | 0.70 | 47.727 | 21.0719 | #231 source.json `scale.model_height` |
| cavalry | 3.326379 | 1.00 | 68.182 | 20.4973 | cavalry-march-contact-prerequisite.md:88; march-phase.json `original_scale_observation` |
| royal | 2.400321 | 0.72 | 49.091 | 20.4518 | seat 0.0360048 m / `map3d_unit_seat_clear` 0.015 (royal-native-contact-feasibility.md:75); terrain witness gives 20.34 |

Screen size of one world metre: the camera has FOV 45 (`map3d_fov_deg`), closest distance
`map3d_zoom_min_m = 100`, opening distance 10973.7 m (measurements.md:13). Metres per pixel at the
target on a 1600-px-tall window (the evidence standard, 2560x1600): `mpp(D) = 2 D tan(22.5) / 1600 = D * 0.000517767`.

| Camera distance D | m/px | infantry figure px | 0.60 m in px | 0.05 m in px |
|---|---|---|---|---|
| 100 m (closest zoom) | 0.0518 | 816 | 11.59 | 0.97 |
| 600 m (owner's size-choice shot) | 0.3107 | 136 | 1.93 | 0.16 |
| 1200 m (CF01 near review) | 0.6213 | 68 | 0.97 | 0.08 |
| 2600 m (CF01 overview) | 1.3462 | 31 | 0.45 | 0.04 |
| 10974 m (opening view) | 5.6818 | 7.4 | 0.11 | 0.009 |

At 2160 px tall (4K) multiply the px columns by 1.35. Pieces switch to symbols at a 100 km scale bar
(`map3d_unit_symbol_enter_scale`), so models are only ever drawn between 100 m and roughly the opening band.

Existing shipped allowances the game already draws (relevant to "invisible"):

- `map3d_unit_seat_clear = 0.015` of drawn height (`data/screens/map3d/balance.csv:155`): every seated piece
  is lifted 1.5% of its height over the highest ground under its base. That is 0.634 (infantry),
  0.716 (archers), 1.023 (cavalry), 0.736 (royal) world m of deliberate hover, i.e. 12-20 px at the closest zoom.
- `map3d_unit_anim_max = 2.0` (`balance.csv:158`): "past this the piece slides rather than turning its legs".
- Cavalry's shipped `stride_m 5.9` slides a planted hoof 0.392 model m per stance = **8.03 world m**
  (cavalry-march-contact-prerequisite.md:86-89), 12.9 px at 1200 m and 155 px at the closest zoom.

### A.2 Per-arm clauses, frozen residuals, certificate status

Converted with k from A.1. "px@1200" is on a 1600-px window.

**Common clause (all arms).** `cf04c-locomotion-contract.md:127-128`:
"`body_locomotion_<arm>_contact_um` (maximum certified ground-contact error, integer model micrometres)".
`:413-414`: contacts record "normal/separation, slip/penetration/hover error, transitions to/from MARCH and
both pivot signs; bind accepted error to contact_um". No value was ever approved; no `body_locomotion_*`
row exists in `data/army/balance.csv`.

**Infantry** (artillery inherits the same model).
- Clause: `infantry-pivot-metric-contract.md:117` "The finite point error is `max(abs(separation), slip)`
  in model micrometres." The zero clause that failed is the conditional proposal D,
  `infantry-pivot-feasibility-contract.md:140-141` "require zero deformed-boot separation at both endpoints
  of that plane, rather than the original certified error bound."
- Residuals (native MARCH endpoints, frozen fixture): endpoint boot-minimum height differences
  -6.360 mm (.137->.823), +1.865 mm (-2 deg), **+11.684 mm** (-1 microdegree) model
  (feasibility contract :147-156) = 0.168 / 0.049 / **0.308 world m** (0.50 px@1200).
  Highest boot minimum above the seated plane 17.208 mm = 0.454 world m. Loop-seam residual 0.356 micrometres.
  #221 pivot clips: finite stance patch displacement <= 0.0116 mm (0.0003 world m); native skin error 4.45 micrometres.
- Skin diagnostic (`>4x entry AND >.03 m`, feasibility :85): native +90 exit edge 54.935 mm vs boundary 50.668 mm
  is itself flagged (skin-acceptance :76-82); 45 introduced pairs at -2 deg; one mapper-only crossing
  49.5907 vs 49.4923 mm (feasibility :93-96).
- Placement predicate: relative Gram residual 1.0526e-7 vs strict 1e-10 -> FAIL (metric contract, raw observation section).
- Certificate: **does not exist**. `evidence/locomotion/infantry/contact-evidence-custody.json`:
  `certificate false`, `E null`, `motion_acceptance FAIL/PENDING`, full measurement attempt timed out (exit 124 at 2700 s).
  Infantry pivot clips are not on main (#221 draft); `assets/3D/units/infantry/infantry.glb` has MARCH only.

**Archers.**
- Clause: #231 `pivot-contacts.json` `continuous_argument`: "A nonzero difference at their common boundary
  prevents C0 continuity."; #236 `archers-native-transition-contract.md:202-204` "Require exact full native local
  boundary values and their C0 one-sided limits ... This gives zero mathematical material seam".
- Residuals: native MARCH->pivot seam **0.841195 mm** model on body vertex 35966 = **0.0177 world m**
  (0.34 px at the closest zoom); right sole triangle seam 0.392 mm (0.008 m); bow/quiver/arrow seams <= 0.23 micrometres.
  First right stance during pivots: separation 0.193..1.511 mm, penetration 0, slip 0.042 mm (0.0009 world m).
  Native MARCH right-sole stance heights 0.585..1.903 mm (0.040 world m) (#236 :300-306).
  #236 geometric obstruction: joints must move >= 0.379 mm (length) / 0.353 mm (split) from native (:106-108) = 0.008 world m.
- Certificate: **FAILED** (#231 `status REJECTED_NATIVE_MARCH_SEAM`, `certificate None`); #236 `B=false, C=false, CERT=failed` (:743).

**Cavalry.**
- Clause: `cavalry-march-contact-prerequisite.md:99-100` "If contact error E means maximum displacement
  from the actual planted point at entry, these two endpoints require `E >= D_v(d)`."
- Residuals (hoof vertex 16496, phases .137->.25): retained stride 5.9 slide **391.94 mm = 8.03 world m**;
  nominal 2.4: 3.74 mm (0.077 m); best scalar for that vertex 1.140 mm XZ + 1.756 mm Y (0.023 / 0.036 m).
  All-hoof sampled minimax phase map (`march-phase.json` `fit`): entry drift between **19.07 and 20.54 mm**
  = **0.391-0.421 world m** (0.63-0.68 px@1200); strongest transverse endpoint lower bound 12.55 mm (0.257 m).
  Raw-GLB vs native disagreement 5.47 mm (import optimizer, 6.13 mm) - a source-fidelity fact, not a contact residual.
- Certificate: **does not exist**. `march-native-contact.json` `BLOCKED_NOT_ACCEPTED`, `claims.contact_certificate false`,
  `policy_E null`; `march-phase.json` `DIAGNOSTIC_UNKNOWN_NOT_SUCCESS_DEPENDENCY`; penetration/hover/normal all `null`
  (terrain input missing).

**Royal.**
- Clause: `royal-native-contact-feasibility.md:138` "Stance error is `max(abs(d_v), s_v)`; all-mode penetration
  is `max(0,-d_v)`." and :174-176 "do not enlarge E from these measurements".
- Residuals: native MARCH phase .73 FrontHoof.R penetration **23.272 mm** flat (0.476 world m) and **24.810 mm**
  on actual terrain = **0.5046 world m** built-world (0.81 px@1200, 9.7 px at the closest zoom); that hoof is
  59.28 mm (1.21 world m) below the model origin, the 36.0 mm seat lift leaves 23.3 mm below ground.
  Bake-only pivot vs MARCH .73: 1.5246 m model (rejects bake-only playback, not a provider).
  Envelope: dense MARCH radius 748.860 vs R=749 simulation m (margin 0.14), conservative upper 789.96 (unproved containment).
- Certificate: **FAILED** (LOCO-CERT-ROYAL failure input; "royal full-domain contact certification remains FAIL", :16).

**Artillery.** Infantry placeholder (measurements.md:5); its own radius R=875 and policy must still be certified
(cf04c-locomotion-contract.md:132-133). No certificate. Any real gun model voids every artillery number.

### A.3 The bounds (accepted as R-A)

Measured on the ordinary rendered piece: ordinary scale, the protected placement/seat T, the actual rendered
Terrain3D ground under the figure, all equipped meshes, native (imported) skinning. One world value per quantity,
converted per arm to model micrometres by `ceil(bound_world_m / k * 1e6)`.

| # | Quantity (definition) | Bound (world m) | Frozen worst | Margin |
|---|---|---|---|---|
| 1 | **Penetration**: depth of any vertex of the whole mesh below the rendered ground, every mode (stance, swing, pivot, transitions) | **<= 0.60** | royal 0.5046 (terrain) | 16% |
| 2 | **Stance hover**: height of the planted material sole/hoof patch above the seated plane (ground + the protected `map3d_unit_seat_clear` lift), stance intervals only | **<= 0.60** | infantry 0.454 (boot minimum 17.2 mm) | 24% |
| 3 | **Tangential slide**: displacement of the planted material patch from its touchdown anchor, projected on the ground, over one stance interval | **<= 0.60 per stance** | cavalry best phase map 0.391-0.421 (as shipped with stride 5.9: 8.03, fails) | 30% |
| 4 | **Seam jump**: one-frame displacement of any vertex at any clip boundary (MARCH<->PIVOT, loop seam, start/stop, mid-stance cut) | **<= 0.05** | archers 0.0177 | 65% |

The contract's single `contact_um` (= max(|separation|, slip), metric contract :117) then becomes
`max(quantities 1-3) <= 0.60 world m`, with "separation" read as penetration below the ground or hover above the
seated plane (that reading is the answer to Pending decision 1, below). The seam bound is a separate C0 gate.

Per-arm installed values (`ceil(0.60e6 / k)` and `ceil(0.05e6 / k)` model micrometres):

| Arm | `body_locomotion_<arm>_contact_um` | seam bound (model um) |
|---|---|---|
| infantry | 22769 | 1898 |
| artillery | 22769 | 1898 |
| archers | 28474 | 2373 |
| cavalry | 29273 | 2440 |
| royal | 29338 | 2445 |

(i) **Frozen measurements already satisfy or nearly satisfy.** Every frozen value above passes, in model terms:
royal 24,810 <= 29,338 um; infantry 17,208 (hover) and 11,684 (endpoint change) <= 22,769; cavalry phase-map
upper 20,537 <= 29,273; archers seam 841 <= 2,373 and their pivot stance error 1,511 <= 28,474; #236's
required joint move 379 um is far below any bound. The one failure is cavalry at its **shipped** stride 5.9
(391,938 um); the cavalry distance-to-phase map that the cavalry contract already proposes brings it to
19,070-20,537 um, under the bound. 0.60 m is the smallest round value above the largest frozen residual
(royal 0.5046 m) with about 15% left for measurement uncertainty: `0.5046 * 1.15 = 0.580 -> 0.60`.

(ii) **Visually invisible at the game's distances.** 0.60 m = 0.97 px at 1200 m, 0.45 px at 2600 m and
0.11 px at the opening view (1600-px window). It is also below the hover every piece already shows today
(the seat lift, 0.63-1.02 m) at every zoom, and 13x tighter than the cavalry slide that ships now. At the
closest zoom (100 m) it is 11.6 px, which nothing can make invisible: the native MARCH clips already in the
game show 6-12 px there (infantry 0.308 m, royal 0.505 m). So the closest-zoom check is the real-window review
("no worse than shipped native MARCH"), not the number. Seam 0.05 m is 0.97 px even at the closest zoom
(1.3 px at 4K), because a one-frame pop is the most visible of the four.

(iii) **The skin-diagnostic gate is not weakened in its thresholds.** See Pending decision 2.

**Pending decision 1 (contact/stance interpretation and bound).** Proposed answer: the stance target is the
fixed material patch (chosen once in the bind mesh) anchored at touchdown; hover is measured from the seated
plane because the seat lift is protected placement (contract B), penetration from the actual rendered ground;
`contact_um` per the table; sampled certificate per ruling R-C below. D's zero-endpoint clause is dropped
(the owner's ruling 1); A, B and C stand.

**Pending decision 2 (absolute skin diagnostic at exact native endpoints).** The gate cannot pass at an unchanged
native endpoint that already fails it (native exit edge 54.935 mm > 4 x 12.667 mm). Proposal: keep
`length > 4 x native-entry AND > .03 m` exactly; a flag fails the step **unless the shipped native pose at the
same phase is itself flagged**. So the 45 introduced pairs and the one mapper-only crossing (native 49.183 mm,
under its 49.492 mm boundary) still fail and the coupled mapper must remove them; the 137 -1 microdegree pairs
and the +90 endpoint edge are recorded as inherited, judged in the real-window review of native MARCH, which
already ships. This narrows what the gate certifies (native-inherited flags stop blocking), which the
feasibility contract (:212-214) says needs explicit authority. **Ruled (R-B): relaxed as proposed.** No tolerance changes.

**Other quantities, not weakened.** The envelope/radius gate is untouched: if a sampled royal envelope crosses
R=749 (margin 0.14 m today), the fix is a larger R in the footprint data (CF01 rule), not a looser bound.
The strict placement Gram predicate (1e-10 relative) is unsatisfiable on a float32 transform (infantry
measures 1.05e-7, under float32 epsilon 1.19e-7). Proposal: 1e-6 relative (about 8 float32 ulps; at most
68 micrometres of world error on a 68 m figure). **Ruled (R-D): 1e-6.**

**What each draft becomes under these bounds.**
- #231 archers: its failing quantity (seam 0.841 mm) passes the 2.373 mm seam bound; certification can resume
  on the existing pivots without #236's P1 transition rework (rework only if the full sampled run fails).
- #236: becomes optional; its obstruction (joint move >= 0.379 mm) is below every bound.
- #221 infantry: contact passes; the open item is the skin gate (45 introduced flags plus 1) and visual review.
- Cavalry: still needs the distance-to-phase map (8.03 m shipped slide).
- Royal: penetration passes; it still needs a MARCH<->pivot provider (bake-only playback differs by 1.52 m)
  and an envelope check against R=749.
- #201 R1: not a contact question; resolved by the v2 stop-pivot-move consumer (B, node CF04c-CONSUMER).

---

## B. Activation roadmap

### B.1 Where main stands

Merged, candidate-only: CF01 #186, CF08 #185, CF02 #191, CF03 #192, CF04a #194, CF04b #199, LOCO-TIME #203,
LOCO-MARCH #206, B-PV2 #218, B-BOUNDARY #232, B-TIME #237, B-CLOSE #240, B-CONTACT #261, B-ENTER #264,
B-DEPLOY #265, B-CHARGE #267, B-FLANK #269, B-WITHDRAW #272; contracts #200, #202, #208, #209 (CF05), CF06
damage/power, encounter continuity, royal/cavalry/infantry feasibility and evidence PRs. Pivot clips are
installed for archers, cavalry and royal; infantry has MARCH only. No locomotion policy row is installed, so
the v2 planner rejects every real arm. `ClusterLayout` has no caller.

Known blockers on main:
- `BattleSystem._start` (`scripts/engine/battle_system.gd:645`): `if not BattleGroups.refresh(repo, state, b): return`
  silently declines a battle when a deployment row lands on blocked ground.
- The inherited **55 failures / 6 risky** from the original live CF02 attempt (cf02-rollout-boundary.md):
  same-day defeat retreat 8 rows -> 3 overlaps; `test_enemy_invasion` 1 failure with 496 admission refusals on
  roads; a fresh campaign with no body store overlaps horses on first migration and save/load fails.
- Royal envelope margin 0.14 m at R=749; cavalry shipped stride slide 8.03 m; artillery is a placeholder.

### B.2 Nodes

Size: S = one small PR, M = one normal PR, L = large or several PRs. "Par" = can run in parallel with.
VR = needs real-window visual review (`visual-review` skill, local session). OR = needs an owner ruling first.

**Rulings and handover**

| Node | Scope | Depends | Covered by | Size | Par | Flags |
|---|---|---|---|---|---|---|
| R0 RULINGS-DOC | Record the bound values, the stance reading, the skin-gate scope, the Gram tolerance and the sampled-certificate method in `cf04c-locomotion-contract.md` (+ infantry contracts); record that Claude Code supersedes the Codex pair/registry bindings; turn #231/#236 into evidence | owner rulings R-A..R-E | none | S | engine branch | OR |

**Locomotion / render branch**

| Node | Scope | Depends | Covered by | Size | Par | Flags |
|---|---|---|---|---|---|---|
| LOCO-CERT-TOOL | One per-arm certifier: dense Godot-native samples of every clip, transition, turn grid (+/-1 microdegree, 180 tie, wrap) and the four quantities + envelope, with a velocity-based sampling margin | R0 | #231 `tools/units3d/certify_archers_locomotion.py` as base | M | engine branch | - |
| LOCO-INF-CLIP | Finish #221: coupled mapper removing the 45 introduced + 1 mapper-only skin flags, real-window review | R0 (skin ruling) | #221 (pivot.py, game_export.py, infantry.glb) | M | other arms | VR |
| LOCO-CERT-INF | Certify infantry | INF-CLIP, CERT-TOOL | custody evidence #259 | S | other certs | VR (crops) |
| LOCO-CERT-ART | Certify the artillery substitute at R=875 | INF-CLIP, CERT-TOOL | none | S | other certs | VR |
| LOCO-CERT-ARCH | Re-run archers under the bounds; P1 transition only if it fails | CERT-TOOL | #231, #236, #216 | S (M if P1) | other certs | VR |
| LOCO-CAV-PHASE | Runtime distance-to-phase map for cavalry MARCH (replaces the stride-5.9 slide) | R0 | cavalry contract + #249-#271 evidence | M | other arms | VR (gait) |
| LOCO-CERT-CAV | Certify cavalry | CAV-PHASE, CERT-TOOL | cavalry evidence | S | other certs | VR |
| LOCO-ROY-PROVIDER | Royal MARCH<->pivot transition provider from arbitrary native phase (PHASE/JETS/CARRIER/BOUNDARY/R2 collapsed into one step under R-C; 5-6 PRs without it); R bump if the envelope exceeds 749 | R0 | royal-boundary-phase-contract, #235 | M (L without R-C) | other arms | VR |
| LOCO-CERT-ROY | Certify royal | ROY-PROVIDER, CERT-TOOL | royal evidence | S | other certs | VR |
| LOCO-POLICY | Install `turn_q` + `contact_um` rows per arm in `data/army/balance.csv` and each certificate in the new `data/army/unit_locomotion.csv` (replaces the contract's "no new table": no source.json exists, data/ is CSV-only, and unit_footprints.csv is hashed by every certificate); one PR for all five | each CERT, LOCO-MARCH (merged) | none | S | - | - |
| CF04c-CONSUMER | Rework #201 into the v2 consumer: stop-pivot-move timeline, PIVOT_LEFT/RIGHT selection, `sample_locomotion_candidate`; resolves R1 (no transverse walking with fixed facing) | R0 (handover), LOCO-MARCH | #201 (render consumers, test, fixture) | M | everything above | - |
| CF04c-VISUAL | Real-window near/far, pause/1x/4x, crossing/turn and FPS acceptance with the real policies | CONSUMER, LOCO-POLICY (all 5) | #201 fixture | M | engine branch | VR |

**Engine branch**

| Node | Scope | Depends | Covered by | Size | Par | Flags |
|---|---|---|---|---|---|---|
| B-MERGE | Field union, transfer-before-delete, side map, parties/tasks | B-WITHDRAW (merged) | cf05 contract :755-760 | M | locomotion branch | - |
| B-END | End/cancel/call-off release, transfer before deletion | B-MERGE | cf05 :761-767 | M | locomotion branch | - |
| B-ROUND | Round-ready resumable candidate driver | B-END | cf05 :768-775 | M | locomotion branch | - |
| D-QUERY | Physical exposure and melee contact counts | B-ROUND | cf06-damage-contract DAG | M | - | formula test |
| D-FIRE | Actual direct-fire query, cross-field | D-QUERY, B-MERGE | cf06 | M | - | formula test |
| D-POWER | Physical power arithmetic | D-FIRE | cf06-power-contract | M | - | formula test |
| D-RECONCILE | Frozen-round reconciliation | D-POWER, B-END | cf06 | M | - | - |
| D-PENDING | Pending round save/resume | D-RECONCILE | cf06 | M | - | - |
| D-SETTLE | Atomic personnel/cost/body/outcome settlement | D-PENDING | cf06 | M | - | formula test |
| D-DRIVER | Wire one candidate round transition | D-SETTLE, D-FIRE | cf06 | S | - | - |
| FIX-BLOCKED-START | Stop `BattleSystem._start` silently declining on blocked ground (legacy path now; body path covered at cutover) | none | FEATURE_STATUS item 8 | S | anything | - |

**Activation (production bridge)**

| Node | Scope | Depends | Covered by | Size | Par | Flags |
|---|---|---|---|---|---|---|
| ACT-LIFECYCLE | Inactive lifecycle/compatibility adapter: zero-delta row transfer at start/join/merge/exit/end | B-END (B-CONTACT merged); serial with D-* where files overlap | encounter-continuity contract adapter 1 | L | locomotion branch | - |
| ACT-LOAD | Fresh-campaign body initialization and legacy save classification (lawful legacy rows kept, overlapping or corrupt saves fail closed, no MIN_SAVE_VERSION bump) | ACT-LIFECYCLE | cf02-rollout-boundary missing-pose blocker | M | ACT-DRIVER | - |
| ACT-DRIVER | Inactive production driver and ordinary writers (create/load/march/garrison/arrival/withdraw, one publication) | ACT-LIFECYCLE, LOCO-POLICY (all 5) | encounter contract adapter 2 | L | - | - |
| ACT-PROJECTION | Inactive admitted projection in map3d + `map3d_view.gd` bridge, `(unit,slot)` continuity across owners | ACT-DRIVER, CF04c-VISUAL | encounter contract adapter 3 (overlaps #201 files) | M | - | VR |
| ACT-CUTOVER | Atomic switch of lifecycle + writers + projection + damage; resolve the inherited 55 fail / 6 pending; road contact, defeat continuation, roundtrip, perf; live-world real-window | ACT-PROJECTION, ACT-LOAD, D-DRIVER, FIX-BLOCKED-START | plan "激活的不可删门禁" | L | - | VR, perf |

**Retirement and cluster features (plan tasks)**

| Node | Scope | Depends | Size | Par | Flags |
|---|---|---|---|---|---|
| CF07a | Retire per-unit tactical effects and old formation warrants | ACT-CUTOVER | M | - | - |
| CF07b | Retire old formation controls and figure tiers (editor) | CF07a | M | CF09 if relaxed | VR, editor |
| CF09 | Cluster save, membership, versioned orders, CLUSTER_SET/CANCEL costs | CF07a+b, CF08 (merged) | M | - | formula test (costs) |
| CF10 | Real couriers, receiver unit, king in formation | CF09 | M | - | - |
| CF11 | Assembly/reform/failure phase machine | CF10 | L | - | formula test (prep count) |
| CF12 | Slowest common pace, no-formation arrival | CF11 | M | - | formula test (100/80/60) |
| CF13 | Reinforce, partial selection, cross-cluster switch | CF12 | M | - | - |
| CF14 | Steady line + shared tactic entry | CF13 | M | CF22, CF23 | - |
| CF15 | Archer-infantry | CF14 | M | CF22, CF23 | - |
| CF16 | Double envelopment | CF15 | M | CF22, CF23 | - |
| CF17 | Cavalry charge | CF16 | M | CF22, CF23 | - |
| CF18 | Depth defence | CF17 | M | CF22, CF23 | - |
| CF19 | Strong wing | CF18 | M | CF22, CF23 | - |
| CF20 | Lure and counter | CF19 | M | CF22, CF23 | - |
| CF21a | Artillery hold | CF20 | M | CF22, CF23 | - |
| CF21b | Conditional support facts and exposure (shares battle_presentation.gd with CF23) | CF21a | M | CF22 | formula test (115) |
| CF22 | Left-drag military box selection and cluster order panel | CF13, CF08 | L | CF14-CF21 | VR, editor |
| CF23 | Known-only preview, phase receipts, body display | CF22, CF12; serial with CF21b | M | CF14-CF21a | VR, editor |
| CF24 | Balance experiments, formation vs none | CF21b, CF23 | L | - | OR (targets) |
| CF25 | End-to-end save/symmetry/real-window acceptance | all | L | - | VR |

Node count: **49** (1 rulings + 12 locomotion/render + 11 engine + 5 activation + 2 retirement + 18 features).

### B.3 Dependency graph

```
R0 ──> LOCO-CERT-TOOL ──┬──> CERT-ARCH ─────────────────┐
  ├──> LOCO-INF-CLIP ───┼──> CERT-INF, CERT-ART ────────┤
  ├──> LOCO-CAV-PHASE ──┼──> CERT-CAV ──────────────────┼──> LOCO-POLICY x5 ──┐
  ├──> LOCO-ROY-PROVIDER┴──> CERT-ROY ──────────────────┘                     │
  └──> CF04c-CONSUMER ─────────────────────────────────> CF04c-VISUAL <───────┤
                                                                │             │
B-MERGE > B-END > B-ROUND > D-QUERY > D-FIRE > D-POWER > D-RECONCILE >        │
          │                 D-PENDING > D-SETTLE > D-DRIVER ───────────┐      │
          └> ACT-LIFECYCLE ──> ACT-DRIVER <─────────────────────────────┼──────┘
                 └> ACT-LOAD      └> ACT-PROJECTION <── CF04c-VISUAL    │
                                         └──> ACT-CUTOVER <─────────────┘  (+ FIX-BLOCKED-START)
ACT-CUTOVER > CF07a > CF07b > CF09 > CF10 > CF11 > CF12 > CF13 ┬> CF14 > ... > CF21a > CF21b ┬> CF24 > CF25
                                                    CF12 ──────┴> CF22 > CF23 ───(serial w/ CF21b)┘
```

### B.4 Critical path

Engine and feature chain (32 nodes). The locomotion branch (R0 -> tool -> slowest arm provider -> cert ->
policy -> visual, about 6 nodes) runs beside the 10-node B/D chain and joins at ACT-DRIVER/ACT-PROJECTION,
so it is not critical **if** R-C is granted; without R-C the royal chain (5-6 extra PRs) and the cavalry
continuous-bound work can overtake it.

1. B-MERGE
2. B-END
3. B-ROUND
4. D-QUERY
5. D-FIRE
6. D-POWER
7. D-RECONCILE
8. D-PENDING
9. D-SETTLE
10. D-DRIVER
11. ACT-LIFECYCLE (can start after B-END, beside D-*, where file hunks are disjoint; that shortens the path by up to 7)
12. ACT-DRIVER
13. ACT-PROJECTION
14. ACT-CUTOVER
15. CF07a
16. CF07b
17. CF09
18. CF10
19. CF11
20. CF12
21. CF13
22. CF14
23. CF15
24. CF16
25. CF17
26. CF18
27. CF19
28. CF20
29. CF21a
30. CF21b
31. CF24
32. CF25

Shortening options (rulings): run CF07b beside CF09 (disjoint files; the plan makes CF09 wait for CF07 whole);
start CF09-CF13 as candidate work beside D-* (they need bodies and marches, not damage) - R-F.

### B.5 The twelve design section 9 gates: where each is proved

1. Ten figures, 901->900 / 1->0, fixed footprint: ACT-CUTOVER (live), CF07b (display), CF25.
2. No overlap through crossing, narrow paths, turns, reload: CF04c-VISUAL, ACT-CUTOVER, CF25; turns need the five certificates.
3. 2 units no cluster, 3 yes, eligibility of all eight: CF08 (merged layout), CF09, CF22.
4. Independent speeds, slowest common pace, local budgets: CF12.
5. Undelivered orders, partial arrival, stale versions, king in formation: CF09, CF10.
6. Assembly under attack can fail; stable old line not penalized: CF11, CF13.
7. Reinforce/reform/partial selection, single membership: CF13, CF22.
8. Normal/blocked/member-loss for each of eight; real flanks; no forced pursuit; no forts: CF14-CF21a.
9. No remote melee, range/obstruction, explained non-duplicated bonuses: D-QUERY..D-SETTLE, CF21b.
10. Determinism under pause/speed/offscreen/mid-substep save, no double charge, old saves: ACT-LOAD, ACT-CUTOVER, CF25.
11. Reproducible formation-vs-none and countered outcomes: CF24.
12. Real 3D-map windows for all of the above: CF04c-VISUAL, ACT-CUTOVER, CF07b, CF22, CF23, CF25.

### B.6 Steps needing real-window visual review (local session, not cloud)

LOCO-INF-CLIP, every LOCO-CERT (native foot/hoof crops, near/far, pause/1x/4x), LOCO-CAV-PHASE,
LOCO-ROY-PROVIDER, CF04c-VISUAL, ACT-PROJECTION, ACT-CUTOVER (plus perf bench), CF07b, CF22, CF23, CF25.
CF07b, CF22 and CF23 also need gdai editor work for the look.
