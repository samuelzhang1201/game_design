# Feature status by spec and plan

Audit of every spec (`docs/superpowers/specs/`) and plan (`docs/superpowers/plans/`) against `origin/main` at `73ee9169` and the GitHub PRs through #281, on 2026-11-10. The weighted MVP estimate stays in `PRD.md` §6; this file is the per-feature detail behind it.

**Method.** Each status comes from code, tests, data, commits and PRs, not from the document's own claims. Plan checkboxes are almost never ticked, even for merged work, and several spec headers still say "not merged" or "未实施" for work that is on main, so neither is a status source. Cluster-formation code is candidate-only: reachable only through `*_candidate` APIs called by tests, not by ordinary play.

**Status words.** Done; Mostly done (small named pieces left); Partial; Not started; Superseded (replaced or removed by a later decision); Abandoned; Unclear.

## Summary

| | Done | Mostly done | Partial | Not started | Superseded | Total |
|---|---:|---:|---:|---:|---:|---:|
| Specs | 43 | 15 | 3 | 1 | 4 | 66 |
| Plans | 80 | 4 | 4 | 2 | 5 | 95 |

The two data-folder CSV maps are counted with their spec; the seven battle-system phase plans under `plans/2026-10-16-battle-system/` are counted as plans.

### Open work that matters most for the MVP

1. **The chapter story.** `2026-10-05-prologue-three-acts-design.md` is approved but has no plan and no code: no act-close handover, no Acts II–III beats or 36-month calendar, no `chapter_arcs.csv`, no chapter close. This is the largest gap against PRD §7.
2. **Sieges and area tasks (battle P6) and release integration (P7).** P6.1 has issue, preview and search travel only; search execution and reports, raid and destroy, return handling, P6.2 siege works and P6.3 task flags have no code; there is no WAR ROOM or UI for area tasks. P7 (visual review, the 800–1000 and 10k performance gates, end-to-end flow, old saves, release) has not started.
3. **Cluster formations are not in the game.** 6 of 29 tasks merged, all candidate-only; CF05 lacks B-MERGE, B-END and B-ROUND; the CF04c render (draft #201) waits on locomotion certificates (drafts #221, #231, #236, idle since 2026-11-03); the eight formations a player would see (CF14–CF21), the command panel (CF22) and acceptance (CF25) are unstarted.
4. **Deception loop and conversation phases 3–5.** Nothing calls `ClaimLedger.record`, so the monthly reckoning always runs on an empty ledger; `Propagation`, `AgentTools`, `CredibilityJudge` and `ConversationAgent` do not exist (`2026-08-30-ai-conversation-system-design.md`).
5. **WAR ROOM gaps.** `WarRoom.believed_hosts` returns `[]`, so the table shows no enemy ghosts; tools polish batches C2 and D were never designed; the room's art (candle flame and flicker, tool box, floor litter) is missing.
6. **LEDGER links to the battle system.** `attacks`, `commands`, `enemy_host` and the `war_chest` loop are still `planned` in `data/ledger/ledger_link_types.csv`; `source`, `witnessed`, `contradicts` and `faction_governs` wait on intel and PRD Step 5.
7. **Missing art.** No 3D spy model (it borrows the cavalry piece); no campaign-zoom settlement variant; archers have no `_parts.glb`; fleets still use a tin token.
8. **Known play defects on main.** `BattleSystem._start` silently declines a battle when a deployment row lands on blocked ground; garrison deaths in the walled-town trial fell from 584 to 22 after #248 and need a balance ruling.

### Specs with no plan

- **Not yet built:** `2026-10-05-prologue-three-acts-design.md`.
- **Partly planned, the unplanned parts not built:** `2026-08-30-ai-conversation-system-design.md` (the plan covers phases 1–2 of 5); `2026-09-14-economy-and-staging-design.md` §7 staging (it contradicts the current "an order never starts the clock" rule, so it probably wants marking abandoned); `2026-10-08-war-room-tools-polish-design.md` batches C2 and D; `2026-10-02-war-room-v2-design.md` sub-project D (partly built under the sunlit-chamber spec).
- **Built straight from the spec:** house arms, weather visuals, the 3D look route (run as phases), army location and town defence, wooden pieces, march waypoints, war room annotations and draw orders, march slope detour, player sight and ghosts, courier slope and rivers, war room front line, ground detail textures, landform rework, open-field layout, sunlit chamber, unit clearance and scouting, infantry ARP knight.
- **Superseded without a plan:** map line meshes (the 2D map was removed), LEDGER battle (replaced by the battle-system specs).
- **Plans with no spec:** `2026-10-18-isolated-step-ci.md`, `2026-10-24-signal-hub.md`.

### Plans with unfinished work

| Plan | Unfinished |
|---|---|
| `2026-10-16-battle-system-implementation.md` | P6.1 remainder, P6.2, P6.3, P7.1–P7.3 |
| `2026-10-16-battle-system/02-roster-and-recruitment.md` | P2.3 national-colour and noble/commoner identity samples |
| `2026-10-16-battle-system/06-area-tasks-and-sieges.md` | P6.1d2, e, f, g; P6.2; P6.3 |
| `2026-10-16-battle-system/07-art-and-release.md` | all of it |
| `2026-10-25-cluster-formations.md` | CF04c, CF05 (B-MERGE, B-END, B-ROUND), CF06, CF07a/b, CF09–CF25 |
| `2026-10-23-p4-group-readability-repair.md` | R1 material separation of the unit models |
| `2026-10-23-p4-pursuit-group-contraction.md` | R1, R2; no owner since N1 was superseded |
| `2026-10-23-p4-narrow-deployment-reserves.md` | N1/N2 folded into CF; the requirement is still unmet on main |
| `2026-09-28-courier-art.md` | Task 8 the 3D spy model; Task 9 the record (`courier_art.csv` still says INTERIM) |
| `2026-09-20-map3d-settlement-houses.md` | Task 11 campaign-zoom variants |
| `2026-09-20-map3d-refactor.md` | Task 23 (optional) lite terrain build; `map3d_view.gd` is 635 lines against a 450-line target |
| `2026-10-12-owner-batch-oct12.md` | owner items in its Outcome (wind sway, far-pier track, pier identity, union sheet, chart margin, busts, slope bar) and rulings R1–R19 |

### Owner rulings still open

Enemy-AI §10 defaults and the march-waypoints rulings (unconfirmed in their specs); owner batch 10-12 rulings R1–R19; the landform slope spike and option B; ground-detail tuning and the low-tier VRAM bench; the dead key `war_hover_budget_ms`; whether `FORTIFY_BORDER` and `MUSTER_DRILL` are still wanted; the garrison-death balance after #248; and #279's exception that a withdrawing column goes round an enemy.

### Docs that no longer match the code

The house-arms spec still names Flux.2 klein (Flux is gone); the map3d-look spec's "no trees" and "settlement rings" were reversed; the 10-17 unit-behaviour spec says "未实施" though most of it is merged; the army split, supply lines, laws and march-waypoint specs still say "not yet merged"; five `.tscn` files and one `.gdshader` still name old flat `data/*.csv` paths.

## Detail by period

The tables below are the per-file audit. "Evidence" names the code, tests, PRs or commits each status rests on.

### 2026-08-28 to 2026-09-19

Checkout: origin/main 73ee9169. Almost all of this lane predates the PR workflow (PRs start ~2026-09-18 with #1; the rest landed as direct commits), so the evidence is commits and code. Key reversal: **the 2D map was deleted in 9586886e (2026-09-24)** — `world_map_view.gd` (2396 lines), `map_info_card.gd`, `mark_mesh.gd`, `map_dash_cache.gd`, biome/sea/cloud 2D layers, `bench_map`, `snapshot_map` — so every 2D-rendering feature below is Superseded. Plan checkboxes: only the 09-03, 09-08 and 09-09 plans were ticked; all others are 0-ticked even where the code is fully built.

#### 1. Specs (19)

| Spec file | Feature (short) | Plan(s) | Status | Evidence (paths, PR #s, commits) | What is left |
|---|---|---|---|---|---|
| 2026-08-28-slice1-skeleton-council-design.md | Walking skeleton: tick engine, 5 founding ministers, suggestions, free-text orders, save/load, determinism, offline | 2026-08-28-slice1-skeleton-council.md | Done | `scripts/engine/{rng,data_repository,game_state,character_factory,action_system,concern_scanner,suggestion_generator,tick_engine,tick_report,save_load}.gd`, `scripts/llm/{template_voicer,response_validator,openai_client,prompt_builder,voicer}.gd`; a5690516 | Nothing. Pixel-art look and 24-tick year were later replaced (dark CK3 theme; 12 monthly ticks) |
| 2026-08-28-slice2-opinion-events-design.md | Ideology-signature opinion drift, promises, 20-event random pool | 2026-08-28-slice2-opinion-events.md | Done | `opinion_drift.gd`, `trigger_dsl.gd`, `event_effects.gd`, `event_system.gd`, `data/realm/action_signatures.csv`, promise resolution `tick_engine.gd:695`; RANDOM_EVENTS.md now 36 `### EV-` entries; 2fe56776 | `# slice-4 upgrade` stand-ins for relation effects were the spec's own deferral (not audited further) |
| 2026-08-28-slice3-ux-redesign-design.md | VN-style flow: main menu, one-minister conversation, kingdom card, round-table voice, day-run, R restart | 2026-08-28-slice3-ux-redesign.md | Done | `main_menu.gd`, `conversation_scene.gd`, `court_screen.gd`, `assets/2D/portraits/cast/round_table.png`; 2b2a1be1 | Parts later reversed: DayRunScreen removed by owner ruling 96ceda56 (no End Turn, clock-driven); conversation moved into the CK3 audience window; KingdomCard became the realm card/top bar |
| 2026-08-30-ai-conversation-system-design.md | Character knowledge, memory, belief, player lies + reckoning, propagation, agent tools, credibility judge, ConversationAgent | 2026-08-30-knowledge-and-deception-core.md (phases 1–2 only) | Partial | Built: `world_rules.gd`, `knowledge.gd`, `source_trust.gd`, `belief.gd`, `claims.gd` (ClaimLedger.resolve_due called `tick_engine.gd:694`), `agent_memory.gd` (used by `prompt_builder.gd:38`, `game.gd:612`), `data/intel/{facts,world_rules,claim_types}.csv`, tests `tests/engine/test_{belief,claims,knowledge,source_trust,world_rules}.gd` | Phase 3 `Propagation` (no `propagation.gd`), phase 4 `AgentTools`, phase 5 `CredibilityJudge` + `ConversationAgent` (none in `scripts/llm/`). Nothing calls `ClaimLedger.record` from conversation, so player claims never enter the ledger in play — the reckoning runs on an empty ledger |
| 2026-09-03-beria-map-integration-design.md | Import Azgaar "Beria" export to CSVs + hit-test bitmap; pan/zoom world-map screen | 2026-09-03-beria-map-integration.md | Done | `tools/import_azgaar.gd` (the .py importer was replaced by GDScript), `scripts/engine/map_index.gd`, `data/maps/beria/{geography,political,economy,military,society}/`; 13c3fb2c, dceaa52a | 2D MapScreen overlay superseded by the 3D map (9586886e) |
| 2026-09-08-map-objects-design.md | Hoverable/clickable towns, roads, rivers, POIs, terrain with info cards + "Ask the council" | 2026-09-08-map-objects.md | Mostly done | 2D pins/`map_info_card.gd` deleted 9586886e; on 3D `map3d_picker.gd` picks burg, route, province, landmark, manor, army, courier; cards in `map_objects.gd` (`burg_card`, `province_card`…); Ask hook `map_detail_panel.gd:220,448` | Rivers and Azgaar POI markers (`marker_types.csv`) are not pickable on the 3D map; no biome/terrain card |
| 2026-09-09-world-database-and-order-impacts-design.md | Domain-folder world DB, schema-clamped world deltas, every order costs, two-part {narrative, impacts} order call, province seams | 2026-09-09-world-database-and-order-impacts.md | Done | `world_ledger.gd`, `order_costs.gd`, `order_pipeline.gd`, `data/realm/{world_schema,order_costs,metric_polarity}.csv`, pack domain folders; invariants 1/8 in root CLAUDE.md; eb2d4b43; 3D dashed seams 6147a66e | Nothing |
| 2026-09-11-terrain-from-data-design.md | Draw 2D terrain as a vertex-coloured mesh from cell data, drop the Azgaar PNG | 2026-09-11-terrain-from-data.md | Superseded | Built 6d4ec421, d873782b, a1f995fb; 2D render deleted 9586886e. `map_terrain.gd` (204 lines) survives as data helpers | Nothing — the 3D Terrain3D map replaced it |
| 2026-09-13-map-line-meshes-design.md | Bake 2D line layers (rivers, routes, borders, seams) to one ArrayMesh per zoom for 60 Hz pan | none | Superseded | Precursor a5c7c8f6 (dashes cut once per zoom); LineMesh landed in batch 0ef0b863; deleted with the 2D map 9586886e | Nothing (3D lines are `Map3DLayerLines` ribbons) |
| 2026-09-14-economy-and-staging-design.md | Manor monthly tax/strategic/civil goods, three pools, month tick, top-bar two lines, goods buy/sell; §7 staged orders + command log | 2026-09-14-manor-economy.md (explicitly §2–6, §8–12; "§7 staging is a separate plan" — never written) | Mostly done | `manor_economy.gd` (RealmEconomy sums), `market_system.gd`, `GOODS_BUY/SELL` in `data/ledger/ledger_actions.csv`, `civil_cost` + `build_rush_gold_per_day` `action_system.gd:678,693`, `salary_gold` in `council_seats.csv`, `tools/bench_economy.gd`, root invariant 11, `docs/design/MANOR_SYSTEM.md` | §7 never built: no `GameState.staged`, `Game.stage/commit_staged`, `command_log`, staged-list UI. Effectively abandoned — current rule is orders apply at once and "an order never starts the clock" (root CLAUDE.md). Grain folds into civil done as `metrics.grain` alias |
| 2026-09-15-ck3-dialogue-design.md | CK3-style centred audience window; whole UI dark (leather, wood, gold) | 2026-09-15-ck3-dialogue.md | Done | 6a6bf8aa (dark theme), 96dafb0f (audience window); `audience_backdrop.gd`, `ui_palette.gd`, `tests/ui/test_ui_palette_dark.gd`, `backdrop` column in `data/story/locations.csv`; scripts/ui/CLAUDE.md line 22 | Backdrop paintings per location (slot only, by design) |
| 2026-09-15-house-arms-design.md | Generated coat of arms for every house and kingdom from Azgaar `coa` | none | Done | `scripts/engine/house_arms.gd`, `heraldic_shield.gd`, 396 files in `assets/2D/arms/beria/`, `tools/arms_report.gd`, `assets/imagegen/arms_prompts.py`; 06ce0628, 0ef0b863; tools/CLAUDE.md line 24 | Spec's model (Flux.2 klein) is superseded — Flux removed; pipeline is now Z-Image/Qwen. Re-generation only when `arms_report` says the borrow pool ran short |
| 2026-09-17-regiment-state-design.md | Regiment morale/wounded/supplies/hidden training & attack/defence, terrain buffs, placeholder battle odds, counters never thinned, WAR ROOM placeholder tab | 2026-09-17-regiment-state.md | Done | `army_system.gd` (73 state refs; `battle_odds` line 2295), `data/army/{army_terrain,army_training_grades}.csv`, 5182cd98 (card), 0ef0b863 | Superseded pieces: 2D counters → 3D wargame pieces (78ce67a1); placeholder WAR ROOM → full `scripts/war_room/`; placeholder odds → `battle_system.gd` |
| 2026-09-17-relief-detail-design.md | Synthesized fractal landforms over the height field for the relief bake | 2026-09-17-relief-detail.md | Done | `MapIndex.stamp_polylines`/`detail_field` (`map_index.gd:86,124`), `tools/bake_relief.gd`; 6ec9d4fc, e6419447, 0ce0d138, ce4cf67a, cef9c1a1 | Still baked for 3D (tools/CLAUDE.md line 8), but `bake_world.py` does NOT take height from it (only the open sea) — its 2D hillshade purpose is gone |
| 2026-09-18-map3d-default-design.md | 3D map shown by default, 2D only for 2D-only layers; 3D MAP tab goes | 2026-09-18-map3d-default.md | Superseded | Built cd8c6e34, cf0df006, PR #1 (032bf3f0); then the 2D map was deleted outright 9586886e | Nothing — staged migration finished (see heights/manor-themes) |
| 2026-09-18-map3d-look-design.md | 3D zoom (trackpad, 800 m), ground materials, rings for settlements, scale bar + compass, clouds, rivers, sea, ≥60 fps, no trees | 2026-09-18-map3d-look.md | Done | 8fff4c40, 2a1c7971, 460c38ee, cdbd369b, f675b66b, 40c12312, 2f13f4fa, 28054d15, de995deb, 077d98bf | Later reversed: rings → hand-modelled houses; "no trees" → woods (`map3d_layer_trees.gd`); look reworked by the Humankind look route (65e1c5e0) |
| 2026-09-19-map3d-border-look-design.md | Remove border/seam curls (centripetal smoothing); kingdom border as realm band + halo + warm ink | 2026-09-19-map3d-border-look.md | Done | 4b8b4365, 99818837, 888ac07f, 8839b6d7; `map_geometry.gd:123`, `map3d_borders.gd:20` (`one_sided` realm band) | Look was the implementer's call, logged for owner reversal |
| 2026-09-19-map3d-heights-design.md | HEIGHTS heat map + named high/low landmarks on 3D; height advantage and height-tier supply burn in war | 2026-09-19-map3d-heights.md | Done | `elevation.gd` 7a0f842c, 2b1693d8 (war), e1a14b9a/99a44d28 landmarks, d721f54a, 30ed5d34, 1f53b3eb, a1e08766, e90aedca; `data/world/landmark_names.csv`, `data/army/army_height_supply.csv`, `map3d_hud_landmarks.gd`, `map3d_hud_heat_legend.gd` | Nothing; the "next spec" (delete 2D) landed 9586886e |
| 2026-09-19-map3d-manor-themes-design.md | ECONOMY/MANORS tint the 3D ground, cell edges, manor pick on 3D | 2026-09-19-map3d-manor-themes.md | Done | cfda78e4 (`manor_palette.gd`), 9468730a (`map3d_ground_tint.gd`), d6ac3b27, 0f86fe9e, 7c9cef2d | Deferred sub-projects 2 and 3 were later done too: f4c385dd (output badges), bd01056a (settlements in house colour) |

#### 2. Plans (17)

| Plan file | Implements spec | Tasks done/total | Status | Evidence | Unfinished tasks (named) |
|---|---|---|---|---|---|
| 2026-08-28-slice1-skeleton-council.md | slice1-skeleton-council-design | 14/14 (0 boxes ticked) | Done | every Task 1–14 class exists (see spec row) | none |
| 2026-08-28-slice2-opinion-events.md | slice2-opinion-events-design | 9/9 (0 ticked) | Done | opinion_drift, trigger_dsl, event_effects, event_system, promises; 2fe56776 | none |
| 2026-08-28-slice3-ux-redesign.md | slice3-ux-redesign-design | 7/7 (0 ticked) | Done | 2b2a1be1; main_menu, conversation_scene, court_screen | none (Task 4 DayRunScreen built then removed by 96ceda56) |
| 2026-08-30-knowledge-and-deception-core.md | ai-conversation-system-design (phases 1–2) | 8/8 (0 ticked) | Done | world_rules, knowledge, source_trust, belief, claims, tick integration `tick_engine.gd:694`, tests; docs in `docs/design/role_player.md` | none in the plan; spec phases 3–5 have no plan |
| 2026-09-03-beria-map-integration.md | beria-map-integration-design | 3/3 (all ticked) | Superseded | Task 1 importer (now `import_azgaar.gd`), Task 2 MapIndex live; Task 3 MapScreen 2D overlay deleted 9586886e | none |
| 2026-09-08-map-objects.md | map-objects-design | 5/5 (all ticked) | Superseded | Tasks 3–4 (2D pins, tooltip, MapInfoCard) deleted 9586886e; Task 2 MapObjects card text and Task 5 Ask hook survive into 3D | none (3D lacks river/POI picking — not a plan task) |
| 2026-09-09-world-database-and-order-impacts.md | world-database-and-order-impacts-design | 7/7 (all ticked) | Done | world_ledger, order_costs, order_pipeline, schema CSVs | none (Task 7 2D province view → 3D seams) |
| 2026-09-11-terrain-from-data.md | terrain-from-data-design | 6/6 (0 ticked) | Superseded | 6d4ec421, d873782b, a1f995fb; deleted 9586886e | none |
| 2026-09-14-manor-economy.md | economy-and-staging-design §2–6, §8–12 | 10/10 (0 ticked) | Done | manor_economy, market_system, GOODS_BUY/SELL, civil_cost/rush, salary_gold, top bar af792489, bench_economy, invariant 11 | none (staging §7 deliberately out of scope) |
| 2026-09-15-ck3-dialogue.md | ck3-dialogue-design | 3/3 (0 ticked) | Done | 6a6bf8aa, 96dafb0f | none |
| 2026-09-17-regiment-state.md | regiment-state-design | 7/7 (0 ticked) | Done | army_system state, army CSVs, card 5182cd98, 0ef0b863 | none (Tasks 6–7 2D counters / placeholder tab later superseded) |
| 2026-09-17-relief-detail.md | relief-detail-design | 7/7 (0 ticked) | Done | b5a22f5e (T1), 6ec9d4fc (T2), e6419447 (T3), 0ce0d138 (T4), ce4cf67a (T5), cef9c1a1 (T6/T7) | Task 7 "retune slope sampling" — no distinct commit; Unclear but moot after 2D removal |
| 2026-09-18-map3d-default.md | map3d-default-design | 3/3 (0 ticked) | Superseded | cd8c6e34, cf0df006, PR #1; then 9586886e | none |
| 2026-09-18-map3d-look.md | map3d-look-design | 10/10 (0 ticked) | Done | one or more commits per task (see spec row) | none |
| 2026-09-19-map3d-border-look.md | map3d-border-look-design | 3/3 (0 ticked) | Done | 4b8b4365, 99818837, 888ac07f | none |
| 2026-09-19-map3d-heights.md | map3d-heights-design | 7/7 (0 ticked) | Done | 7a0f842c, 2b1693d8, e1e6db1d, d721f54a, 30ed5d34, 1f53b3eb, 5b00aceb/a1e08766 | none |
| 2026-09-19-map3d-manor-themes.md | map3d-manor-themes-design | 5/5 (0 ticked) | Done | cfda78e4, 9468730a, d6ac3b27, 0f86fe9e, 7c9cef2d | none |

#### 3. Lists

**Specs with NO plan**
- 2026-09-13-map-line-meshes-design.md (built anyway, then superseded)
- 2026-09-15-house-arms-design.md (built without a plan)
- Partial coverage only: 2026-08-30-ai-conversation-system-design.md (plan covers phases 1–2 of 5); 2026-09-14-economy-and-staging-design.md (§7 staging's "separate plan" was never written)

**Plans with unfinished work**
- None of the 17 plans has an unbuilt task (stale checkboxes aside). Only 2026-09-17-relief-detail.md Task 7's slope-sampling retune is Unclear.
- The unfinished work in this lane sits in specs with no plan for it: ai-conversation phases 3–5 and the economy spec's §7 staging.

### 2026-09-20 to 2026-09-30

Nearly all of this lane landed by direct merges in late Sep 2026, before the PR gate (PR #1 is 09-18, #2 is 10-02), so the evidence here is mostly commits and code. Plan checkboxes are never ticked (0 ticked in every plan), so each status below comes from code, tests and data.

#### 1. Specs

| Spec file | Feature (short) | Plan(s) | Status | Evidence (paths, PR #s, commits) | What is left |
|---|---|---|---|---|---|
| 2026-09-20-map3d-refactor-design.md | Break up map3d_view.gd into layers under an authored scene; quality tiers; world cache; baked layers; .tres look; @tool previews | 2026-09-20-map3d-refactor.md | Mostly done | `scripts/map3d/map3d_context.gd` (a446deb3, 09-20), ~25 `map3d_layer_*.gd`, `map3d_picker.gd`, `map3d_camera_rig.gd`, `map3d_world_cache.gd` (38275da6), `map3d_quality.gd` + `data/screens/ui/graphics_quality.csv` (e7a877d3), `tools/map3d/bake_layers.gd`, `build_pack.sh`, `scenes/map3d/world_map_3d.tscn`, `ground_look.tres`/`weather_look.tres`, `map3d_preview.gd` | Optional lite terrain build for the low tier was never built (the csv `world` column is still `full`, with a "once the optional lite build exists" note). `map3d_view.gd` is 635 lines against the ≤450 coordinator target. The plan's GL Compatibility premise was superseded by Forward+ (2026-09-24 look route). |
| 2026-09-20-map3d-settlement-houses-design.md | Settlements as baked 3D house clusters, never at sea, lane-grown | 2026-09-20-map3d-settlement-houses.md | Mostly done | `tools/map3d/bake_houses.py` (1ba05a1c) + `test_bake_houses.py`, `make_houses.py`, `map3d_houses.gd`, `map3d_layer_houses.gd` (aaadd2dd, 30 commits), guide `scripts/map3d/guide/settlements_and_houses.md`; walls/piers/ships added later (PR #69) | Spec §8 item 1 is still OPEN: what to draw at campaign zoom (impostor / names / tier symbol) was never built. The owner reversed "remove the dots", so a white dot is kept at far zoom (`map3d_layer_settlements.gd`). The procedural meshes were later partly replaced by handmade/Tripo houses (`tools/map3d/tripo_houses`, `scenes/models/buildings/`). |
| 2026-09-24-map3d-humankind-look-gap.md | 3D map look route toward a Humankind reference (Forward+, camera, relief, trees, water, settlements, borders) | none | Mostly done | §4b commits e1a14b9, 2fcac5b, b864fc5, d60cdec, 82db021, 31d341d; `project.godot` forward_plus; trees later (`map3d_layer_trees.gd`, `bake_trees.py`); rock face 85228112 / 39cde14e; hedges/fields PRs #51 #59 #63 #65 #67; walls PR #69; PRD §6 row "3D map look 80%" | Owner approval of the look at the three poses; a stylised ground texture set (new art). City banners and the thin glowing realm-border restyle are unbuilt (§2.8 left them as proposals). Far-zoom road/dot clutter. The last critic rounds barely moved the scores, so the next step is owner-approved art. |
| 2026-09-27-courier-core-design.md | Missive sub-project A: couriers ride the road network; army orders take effect on delivery; weather slows them | 2026-09-27-courier-core.md (also cited by the missive and courier-art plans) | Done | `scripts/engine/road_graph.gd`, `weather.gd`, `courier_system.gd` (7d89de29, 53 commits), `courier_card.gd`, `map3d_layer_couriers.gd`, `map3d_hud_couriers.gd`, `tests/engine/test_weather.gd`; later one courier per target batch (PR #14), slopes and rivers (PRs #24 #28) | Sub-project C (interception) is deferred with enemy AI, by owner ruling; it is outside this spec. |
| 2026-09-28-courier-art-design.md | Missive sub-project D: 3D courier rider, separate 3D spy, card paintings, board art U-20..U-26 | 2026-09-28-courier-art.md | Mostly done | Courier rider `assets/3D/units/courier/courier.glb` + `scenes/models/units/courier.tscn` (4b27e587, re-rigged 10-07); paintings `assets/2D/paintings/couriers/*.png` (45edbeb8); board art `assets/2D/ui/missive_board/` + `assets/imagegen/missive_art_install.csv` U-20..U-26 (959ae75b); design picks 63e414cb | **The 3D spy (merchant on a pack pony, S2) was never modelled.** `courier_models.tres` maps `spy` → cavalry.tscn, and `data/screens/map3d/courier_art.csv` spy row still says "INTERIM stand-in until sub-project D". |
| 2026-09-28-missive-board-and-spies-design.md | Missive sub-project B: fog of knowledge, spy couriers, Missive board in 4 credibility columns | 2026-09-28-missive-board-and-spies.md | Done | `missive_log.gd` (b79146d4), `missive_writer.gd`, `spy_system.gd` (d4030cb0), `intel.gd`, `SPY_SEND` in `data/realm/action_signatures.csv`, `scenes/screens/missive_screen.tscn`, `missive_report_popup.tscn`, `envelope_flight.gd`; tests `test_missive_log/writer`, `test_spy_system`, `test_intel`, `test_fog_cards`, `tests/ui/test_fog_panels`, `test_missive_*`, `test_spy_orders`; later fixes PR #14, board hung in the WAR ROOM PR #2 | — (interception C deferred) |
| 2026-09-29-weather-visuals-design.md | Weather drawn on the 3D ground: field, ground channels, cross-fade, clouds, rain/snow particles, snowy roofs | none (spec carries its own build order) | Done | `map3d_weather_field.gd` (36a1f409), `map3d_layer_weather.gd`, `map3d_layer_precip.gd` (84695268), `precip_*.gdshader`, `weather_look.tres`, `graphics_quality.csv` `weather_particles`; tests `test_map3d_weather_field.gd`, `test_map3d_layer_weather.gd` | Only the bench's absolute numbers were left unread (spec Status: the GPU was busy that night). |
| 2026-09-30-ledger-battle-design.md | LEDGER M4: ARMY_ATTACK, commanders, spoils; lights `attacks`/`commands`/`war_chest` | none ("not implementable yet") | Superseded | The battle mechanics were built under 2026-10-07-enemy-ai-and-battle and 2026-10-16-battle-system-design instead (PR #76 and the P4.x PRs #93..#276). No `ARMY_ATTACK` and no `commander_bindings.csv` exist. `data/ledger/ledger_link_types.csv` still has `attacks`/`commands` as `planned M4`, `enemy_host` object `planned M4`, and loop `war_chest` running `never`. | The LEDGER is not wired to the real battle system: the `attacks` and `commands` links, the Enemy host type and the war_chest loop are all still unlit. |
| 2026-09-30-ledger-galaxy-design.md | LEDGER redrawn as one galaxy: clusters per tab, province folding, flat 2D view | 2026-09-30-ledger-galaxy.md | Done | `scripts/ledger3d/ledger_galaxy_layout.gd` (eaa328f1), `ledger_link_mesh.gd`, `ledger_view_3d.gd`, `scripts/ui/ledger_screen.gd`, `tests/engine/test_ledger_galaxy.gd`; generated art PR #8; lineage PRs #35 #37; budget PR #30 | The flat 2D view was built (9558155b) and later REMOVED by ruling (0fc5cbb2, "the 2D view goes"); `scripts/ledger3d/CLAUDE.md` now says "There is no 2D view". |
| 2026-09-30-ledger-governors-design.md | LEDGER M3 + L1: governors' efficiency and skim, audit, accounts that differ | 2026-09-30-ledger-m3-governors.md | Done | `scripts/engine/governance.gd` (5943ac96), `data/ledger/ledger_governance.csv`, `GOVERNOR_SET`/`LEDGER_AUDIT` in `action_signatures.csv`, "Accounts differ" in `ledger_cards.gd`, `tests/engine/test_governance.gd`, `test_ledger_governors.gd` | Link `contradicts` is still `planned L1` (it waits for intel P0's claims). The sk_admin-vs-sk_martial default awaits owner confirmation. |
| 2026-09-30-ledger-industry-trade-design.md | LEDGER M5 + M6: buildings eat inputs, artisans, markets, trade routes, tolls | 2026-09-30-ledger-m5-m6-industry-trade.md | Done | `industry_system.gd` (33be2f19), `market_system.gd` (7d5751c0), `data/economy/building_inputs.csv`, `TRADE_ROUTE_SET` (action_system, order_costs), `tests/engine/test_industry.gd`, `test_artisans.gd`, `test_markets.gd`, `test_ledger_trade.gd` | — |
| 2026-09-30-ledger-ontology-design.md | LEDGER charter (object, link and action types) + L0 screen replacing RELATIONSHIP | 2026-09-30-ledger-l0.md (+ m1-m2, m3, galaxy) | Mostly done | `ledger.gd` (6274f142), `ledger_resolvers.gd`, `ledger_cards.gd`, `data/ledger/*.csv`, `ledger_screen.gd`, `ledger_order_menu.gd`; RelationshipGraphScreen gone; `snapshot_screen --ledger`; L0/L1/M1/M2/M3/M5/M6 live per `ledger_link_types.csv` | Still `planned`: M4 (`attacks`, `commands`, enemy_host); `source` type (intel P0/P1); `witnessed` (intel P1); `faction` + `faction_governs` (PRD Step 5). The §6.2–6.3 orrery look was superseded by the galaxy spec. |
| 2026-09-30-ledger-supply-design.md | LEDGER M1 + M2: war workshop, supply lines, morale from stores | 2026-09-30-ledger-m1-m2-supply.md; 2026-10-07-army-supply-lines.md (replaces §3) | Done | `workshop_system.gd` (b284166f), `supply_system.gd` (f045b0ea, 19 commits), `WORKSHOP_RATE`, `data/economy/workshop_rates.csv`, loop `hungry_host`; tests `test_workshop_system.gd`, `test_workshop_orders.gd`, `test_supply_system.gd`, `test_ledger_supply.gd` | §3's monthly capital resupply is superseded by 2026-10-07-army-supply-lines (banner at the top of the spec). |

#### 2. Plans

| Plan file | Implements spec | Tasks done/total | Status | Evidence | Unfinished tasks (named) |
|---|---|---|---|---|---|
| 2026-09-20-map3d-refactor.md | 2026-09-20-map3d-refactor-design | 23/24 (the 24th is optional) | Mostly done | 83 commits in scripts/map3d, tools/map3d and scenes/map3d from 09-19 to 09-23; every class named in the plan exists except `Map3DLineStyle` (folded into the lines layer); world cache, quality tiers, bench gates, `bake_layers.gd`, .tres looks, `@tool` previews | Task 23 (optional): lite terrain build for the low tier. Also the ≤450-line coordinator goal (now 635). |
| 2026-09-20-map3d-settlement-houses.md | 2026-09-20-map3d-settlement-houses-design | 9/11 | Mostly done | Tasks 1–8 and 10 done: tables, bake_houses.py + test, make_houses.py, houses.csv, Map3DHouses, Map3DLayerHouses, bench, guide `settlements_and_houses.md` | Task 9 "Remove the dots" was reversed by the owner (the dot is kept at far zoom). Task 11, the campaign-zoom comparison (variants a impostor / b names / c tier symbol), was never built; spec §8.1 is still open. |
| 2026-09-27-courier-core.md | 2026-09-27-courier-core-design | 12/12 | Done | road_graph, weather, courier_system, courier_card, map3d_layer_couriers, map3d_hud_couriers, tests | — |
| 2026-09-27-regiment-pieces-round2-handover.md | none (session handover for the owner's 13-point request) | 6/6 batches (13/13 items) | Done | Commit 1f9a2527 (09-27): no MILITARY tab, dev mode, 25 km start, size rule `map3d_unit_ref_px`, 50 km counters, bars, Commit/Cancel march + Edit route, ground-paced MARCH, shadows, sun sweep, cavalry guard pose, dashed seam highlight; 925bcdb2 follow-up | — (the pieces were later re-done: wooden war-room pieces, Tripo/ARP knight PR #101) |
| 2026-09-28-courier-art.md | 2026-09-28-courier-art-design | 7/9 (Task 9 partial) | Mostly done | Tasks 1–2 design sheets and picks (63e414cb); Task 3 gallop/idle; Tasks 4–5 painting and board slots; Task 6 courier model (4b27e587); Task 7 paintings 45edbeb8 + board art 959ae75b | **Task 8: the spy model** (still the cavalry stand-in). Task 9 (record what D shipped) is incomplete: `courier_art.csv` still says the spy is "INTERIM until sub-project D". |
| 2026-09-28-missive-board-and-spies.md | 2026-09-28-missive-board-and-spies-design | 10/10 | Done | missive_log, missive_writer, intel, spy_system, SPY_SEND, missive_screen, report popup, envelope_flight, fog tests, 8c2068a7 docs + art prompts | — |
| 2026-09-30-ledger-galaxy.md | 2026-09-30-ledger-galaxy-design | 11/11 | Done | ledger_galaxy_layout, ledger_link_mesh, ledger_view_3d, ledger_screen, test_ledger_galaxy, test_ledger_open_schema; 9558155b tabs-as-clusters; PR #8 art | — (the Task 9 flat chart was later removed by ruling, 0fc5cbb2) |
| 2026-09-30-ledger-l0.md | 2026-09-30-ledger-ontology-design (L0) | 11/11 | Done | data/ledger/*.csv, ledger.gd, ledger_resolvers.gd, ledger_cards.gd, ledger_screen.gd, ledger_order_menu.gd, `snapshot_screen --ledger`, RelationshipGraphScreen removed; tests test_ledger_data/schema/resolvers/snapshot/cards | — (the Tasks 6 and 10 orrery look was replaced by the galaxy plan) |
| 2026-09-30-ledger-m1-m2-supply.md | 2026-09-30-ledger-supply-design | 6/6 | Done | workshop_system, supply_system, WORKSHOP_RATE, host_hungry loop, tests | — (supply-line mechanics later reworked by 2026-10-07-army-supply-lines) |
| 2026-09-30-ledger-m3-governors.md | 2026-09-30-ledger-governors-design | 5/5 | Done | governance.gd, ledger_governance.csv, GOVERNOR_SET, LEDGER_AUDIT, accounts-differ strands, test_governance, test_ledger_governors | — |
| 2026-09-30-ledger-m5-m6-industry-trade.md | 2026-09-30-ledger-industry-trade-design | 5/5 | Done | industry_system, market_system, building_inputs.csv, TRADE_ROUTE_SET, test_industry, test_artisans, test_markets, test_ledger_trade | — |

#### Specs with NO plan
- 2026-09-24-map3d-humankind-look-gap.md (a route doc; its work ran as phases, see §4b)
- 2026-09-29-weather-visuals-design.md (built straight from the spec's own build order)
- 2026-09-30-ledger-battle-design.md (never planned; superseded by the battle-system specs)

#### Plans with unfinished work
- 2026-09-28-courier-art.md: Task 8, the 3D spy model; Task 9, the record (the csv still says INTERIM).
- 2026-09-20-map3d-settlement-houses.md: Task 11, the campaign-zoom variants (Task 9 reversed by the owner).
- 2026-09-20-map3d-refactor.md: Task 23 (optional), the lite terrain build; the coordinator is 635 of ≤450 lines.

### 2026-10-01 to 2026-10-08

Method: spec/plan headings skimmed; status decided from code (`scripts/engine`, `scripts/war_room`, `scripts/ui`, `scripts/map3d`), data tables, tests, `git merge-base --is-ancestor` on key commits, and PRs (#2, #3, #9, #15, #20, #29, #32, #38, #60–#68, #76). No plan checkbox in this lane is ticked (0 of ~800); every plan's status comes from code, not from boxes. Several spec Status lines still say "built on feat/… (not yet merged)" though the work is on main (army split, supply lines, laws, march waypoints). Those lines are out of date.

#### 1. Specs (17)

| Spec file | Feature (short) | Plan(s) | Status | Evidence (paths, PR #s, commits) | What is left |
|---|---|---|---|---|---|
| 2026-10-01-war-room-design.md | WAR ROOM v1: 3D plotting room, vellum sheet, pieces, folio, ink figure, take-apart | plans/2026-10-01-war-room.md | Done | `scripts/war_room/*` (WarRoomView, WarCamera, WarPieces, WarInkFigure, WarExplode), `scripts/engine/war_room.gd`, `war_folio.gd`, `war_sheets.gd`; tests/war_room/*; merged 939ac32 / c5c5691a | Enemy ghost pieces deferred to intel P2 (ruling 9): `WarRoom.believed_hosts` still `return []`. No archer `_parts.glb`, so archers cannot be taken apart (only infantry and cavalry have one). Tin pieces, rake and order menu were later replaced (wooden pieces, drawn orders) |
| 2026-10-01-war-table-ui-design.md | Main-screen "war table" chrome: oak, vellum sheet, brass dial, tally board, wax seal, bookmarks | plans/2026-10-01-war-table-ui.md | Done | `scripts/ui/war_table/{paper_style,war_table_backdrop,brass_dial,wax_seal}.gd`; `data/screens/ui/ui_table_palette.csv`; balance `ui_war_table`=1; merges e5035d81, 31ad0312 (follow-ups) | — |
| 2026-10-02-war-room-v2-design.md | v2: A turnable room + column roll-up + easel board, B graticule sheets/index chart/toss, C drafts + Deploy scroll, D room art | v2-a, v2-b, v2-c plans | Mostly done | A: PR #2 (WarCamera, WarBoard, board-only MissiveScreen). B: PR #3 (MapCoords, WarSheets, WarBake, WarToss, WarIntelInk). C: PR #3 (WarDrafts, `GameState.war_drafts`, WarDeployScroll, WarLeavePrompt). D: furniture came from the 10-13 sunlit-chamber spec (PRs #60/#62/#64/#68) | D is unfinished: no `candle_flame.gdshader`, no `war_candle_flicker_*` keys, no tool-box model, no barrels/bandages/litter, no moving rakes (rakes were dropped when the draw-orders spec made orders drawn). §1.2's card over the left side was replaced by the docked folio |
| 2026-10-05-prologue-three-acts-design.md | MVP chapter story: three acts over 36 months, Acts II–III beats, Malvern's death, twists, law thread | none | Not started | Spec says "Not built". PRD §6 (2026-11-10): "Acts II–III, the arc tracker, stages 4–6 and the chapter close are not" built. No `chapter_arcs.csv`, and nothing for act_close or Act II in scripts/data/game_story | Everything: act-close handover from the four endings, Tomas faction at month 13, Acts II–III beats and calendar, deadline rule, chapter framework (PRD Step 6), factions (Steps 5/7), chapter close |
| 2026-10-06-army-location-and-town-defence-design.md | A regiment's live place: town / field / height, town defence, garrison where it stands, ground pace | none | Done | 9ddd6d31 "towns, garrisons and the ground's pace follow where a regiment stands" (on main); `data/army/army_town_defence.csv`, `army_ground_speed.csv`, `army_town_reach.csv`; `ArmySystem.town_at` | §6b's garrison counter was reversed by the army-split spec (one piece per unit). §5 item 4: supply was explicitly left for later and is now covered by the supply-lines spec |
| 2026-10-06-war-room-wooden-pieces.md | Carved-oak war-room pieces on realm-lacquered plinths, artillery shown as a trebuchet | none | Done | `assets/3D/war_room/piece_{archers,bombard,cavalry,infantry,royal,trebuchet}`, `war_pieces.tres`, `wood_piece.gdshader` lacquer; `GameArt.WAR_PIECES` | Fleet still uses a tin token (by design until a wooden ship is made; no `piece_ship`) |
| 2026-10-07-army-split-and-ground-design.md | Opening armies split into ~40 pure-arm units of 300–1000; town seat + camps in hex rings; ARMY_SEAT; multi-select | plans/2026-10-07-army-split-and-ground.md | Done | `scripts/engine/army_split.gd`, `army_ground.gd`, `camp_system.gd`; `GameState.army_roster`; `ARMY_SEAT` in action_signatures/order_costs; 6415afbe, 311d7816, 86090dc7 (slot pitch 1500 after visual review) on main; tests test_army_split / test_army_ground / test_camp_system | — (the spec's Status line still says not merged; that line is out of date) |
| 2026-10-07-army-supply-lines-design.md | Carried days (10–30), town stores, road supply lines with cartage fee, interception, missives, morale under 5 days | plans/2026-10-07-army-supply-lines.md | Done | `scripts/engine/supply_lines.gd`, `town_stores.gd`, `supply_system.gd`; `scripts/map3d/map3d_supply_{lines,road,broken}.gd`; `army_carry_loads.csv`, `army_supply_orders.csv`; tests test_supply_* (10 files); later PRs #10, #24, #28, #38 build on it | — (Status line says the look of the line awaited a ruling; PR #38 settled the broken-line look) |
| 2026-10-07-enemy-ai-and-battle-design.md | Raider invasion AI (3 hosts), two-army battle with player intervention, siege, raid/plunder, defeat (no game over) | plans/2026-10-07-enemy-ai-and-battle.md | Mostly done | `scripts/engine/enemy_ai.gd`, `battle_system.gd`, `siege_system.gd`, `raid_system.gd`; `hazard_kinds.csv` Raided row; tests test_enemy_* / test_invasion_end_to_end / test_siege; merge 51533752 "invasion engine"; guide `scripts/engine/guide/battle_and_ai.md` | P4 presentation is only partly done: scout ghosts on the 3D map (PR #9) and delivered battle reports (PR #76) exist, but there are no enemy ghost pieces in the WAR ROOM. The battle round model has since been extended or replaced by the 2026-10-16 battle-system spec (PRs #76–#279). §10's defaults were never confirmed by the owner |
| 2026-10-07-march-waypoints-design.md | March waypoints (max 8), a bendable centripetal Catmull-Rom route, carry asked on confirm | none | Done | `scripts/engine/march_route.gd` (MarchRoute), `army_order_menu.gd` `_add_waypoint_row`, `march_confirm_panel.gd` carry rows; balance `army_route_sample_m`, `army_march_waypoints_max`; test_march_route*.gd; merge 51de6438 | The rulings in "Rulings made without the owner (to confirm)" are still listed as unconfirmed in the spec |
| 2026-10-07-war-room-annotations-and-planning-pieces-design.md | Supposed enemy pieces (saved, draggable, terrain-adjusted figures) plus wax-crayon NATO-style annotations | none | Done | `scripts/engine/war_plans.gd`, `scripts/war_room/war_plan_{pieces,ink,input,draw,geometry,hud,tool}.gd`, `data/army/war_plan_kinds.csv`, `GameState.war_plans`; tests test_war_plans / test_war_plan_*; guide `scripts/war_room/guide/plans.md` | — (pen retired by the tools polish; red/blue sides added by the draw-orders spec) |
| 2026-10-07-war-room-p2-tactical-layer-design.md | P2: A map marks (brigands/pirates hit supply), B zones become timed hazards | p2a-marks, p2b-hazards | Done | A: `scripts/engine/war_marks.gd`, `data/screens/war_room/war_marks.csv`, `data/army/war_mark_hazards.csv`, `SupplySystem.mark_loss`, test_war_marks / test_supply_marks. B: `scripts/engine/hazards.gd` (seed_pack, settle_month, pace_permille), `data/army/hazard_kinds.csv`, WarIntelInk hatching, test_hazards; merge e34f91ab | — |
| 2026-10-07-war-room-p3-economy-layer-design.md | P3: A works / markets / trade flows inked on the sheet; B foraging | p3a-war-economy (A only) | Done | A: `scripts/engine/war_economy.gd` (trade_flows, food_price_permille), `data/army/war_works.csv`, test_war_economy. B: done under a later spec, `2026-10-10-foraging-and-desertion` (`scripts/engine/forage.gd`, PR #15) | B (foraging) was replaced by the 10-10 foraging-and-desertion spec; there is no p3b plan |
| 2026-10-07-war-room-scale-hover-design.md | P1: 10° sheets (twice the scale), fine print, hover slip (`WarGround`), gated near-zoom detail patch | plans/2026-10-07-war-room-scale-hover.md | Done | `war_fine_print.gd`, `war_near.gd`, `war_hover_dwell.gd`, `scripts/engine/war_ground.gd`, `ArmySystem.power_on`; the gate called for the patch and it was built: `war_detail_ink.gd`, 31540825 (on main); tests test_war_fine_print / test_war_near / test_war_detail_ink / test_war_ground | — |
| 2026-10-08-laws-tab-design.md | Laws layer (economy / political / military), decreed by courier, data-driven effects, laws screen | plans/2026-10-08-laws-tab.md | Done | `data/realm/{laws,law_effects,law_words}.csv`, `scripts/engine/law_system.gd`, `law_effects.gd`, `scripts/ui/laws_screen.gd`, `scenes/screens/laws_screen.tscn`; b1ca31cd, ca15c7ad (visual review wave 1) on main; 9 test_law_*.gd; later 40b56fe9 added seven laws | Out of scope by the spec's own §9: chivalry laws (§6), fleets as recipients, courier interception, laws shown in the war room |
| 2026-10-08-war-room-draw-orders-design.md | Two-sided tool roll (red/blue); marches given only by drawing a blue arrow over a selection; fronts that face the enemy; supply town picked after the destination | none | Done | `war_order_sketch.gd`, `war_order_arrows.gd`, `war_tool_roll.gd`, `WarPlanInput.sel_side`, `WarPlans.facing_flip`, `ArmyOrderMenu.plan_group`; commits 8228b5ee, 293d7b56, 4595a806; owner rulings of 2026-10-11 in the spec; PR #38 | — |
| 2026-10-08-war-room-tools-polish-design.md | Tools polish in batches: A logic, B sheet layout and ink, C tool roll (C1 glyphs, C2), D performance and cleanup | tools-polish-a, tools-polish-b | Mostly done | A: e0a5b2dd..b8b178ed (on main). B: PR #20. C1: PR #29 (painted glyphs, photographed scroll) | C2 was never designed: smaller roll, hover ring on slots, a cursor per tool, why-messages for a faint slot or a scraper miss, a facing preview, a wider scroll-button rect. D was never designed or built: cache order arrows in table space, the supply ribbon rebuilt per box drag, throttle the order-tip reading, dead pen/rake/piece-menu code (`war_rake_min_px` still in 8 places), `Game.landed` still a static on the autoload, red arrows from one gesture still one undo step each, the Esc order with the book held up, the listed test tightenings |

#### 2. Plans (16)

| Plan file | Implements spec | Tasks done/total | Status | Evidence | Unfinished tasks (named) |
|---|---|---|---|---|---|
| 2026-10-01-war-room.md | 2026-10-01-war-room-design | 16/16 (3 later replaced) | Done | All the classes named in Tasks 1–14 exist with tests; merge c5c5691a | T10 "tin pieces" replaced by wooden pieces; T11 "rake arrow, COMMIT, pennants" replaced by v2 C drafts and then drawn orders; T15 "room's art" replaced by v2 D and the sunlit chamber; T14 take-apart has no archer parts model |
| 2026-10-01-war-table-ui.md | 2026-10-01-war-table-ui-design | 9/9 | Done | `scripts/ui/war_table/*`, `ui_table_palette.csv`, bookmarks, `ui_war_table` key; e5035d81 | — |
| 2026-10-02-editor-native-ui-pilot.md | none (owner ruling 2026-10-02; became the root CLAUDE.md "look lives in the editor" rule) | 7/7 | Done | 9417c16f; `assets/2D/ui/theme/game_theme.tres`, `assets/fonts/roles/*.tres`, `assets/2D/icons/resource_icons.tres`, `scenes/hud/top_bar.tscn`, `scenes/screens/court.tscn`, `@tool` PaperStyle; guards test_editor_owned_look | — (step 7, carrying it to the other screens, is now a binding project rule) |
| 2026-10-02-war-room-v2-a-camera-layout.md | v2 spec §1 (A) | 10/10 | Done | PR #2; `war_camera.gd`, `war_board.gd`, `war_room_gestures.gd`, MissiveScreen board-only f3de7d77 | T5 "card unrolls over the room's left" later replaced by the docked folio |
| 2026-10-02-war-room-v2-b-graticule-scale.md | v2 spec §2 (B) | 12/12 | Done | PR #3; `MapCoords`, `war_sheets.gd`, `war_bake.gd`, `war_toss.gd`, `war_index_chart.gd`, `war_intel_ink.gd` | — (the 20° sheet size was later changed to 10° by the scale-hover spec) |
| 2026-10-02-war-room-v2-c-deploy.md | v2 spec §3 (C) | 8/8 | Done | PR #3; `war_drafts.gd`, `GameState.war_drafts`, WarDeployScroll, WarLeavePrompt, test_war_drafts | — (T3's order-menu drafting was later replaced by drawn orders) |
| 2026-10-07-army-split-and-ground.md | army-split-and-ground spec | 10/10 | Done | `army_split.gd`, `army_ground.gd`, ARMY_SEAT, `Map3DDeclutter`, 86090dc7 (T10 slot pitch), 311d7816 (T9 grouped lists) | — |
| 2026-10-07-army-supply-lines.md | army-supply-lines spec | 12/12 | Done | `town_stores.gd`, `supply_lines.gd`, map3d supply layers, supply missives, test_supply_* | — |
| 2026-10-07-enemy-ai-and-battle.md | enemy-ai-and-battle spec | 12/12 | Done | `enemy_ai.gd`, `battle_system.gd`, `siege_system.gd`, `raid_system.gd`, test_enemy_* / test_siege / test_invasion_end_to_end; merge 51533752 | — (the spec's P4 presentation was not in the plan; see the spec row) |
| 2026-10-07-war-room-p2a-marks.md | p2-tactical-layer §1 (A) | 6/6 | Done | `war_marks.gd`, `war_mark_glyph.gd`, `war_marks.csv`, `SupplySystem.mark_loss`, test_war_marks / test_supply_marks | — |
| 2026-10-07-war-room-p2b-hazards.md | p2-tactical-layer §2 (B) | 8/8 | Done | `hazards.gd`, `hazard_kinds.csv`, WarIntelInk hatches, `WarGround.hazard_words`, test_hazards | — |
| 2026-10-07-war-room-p3a-war-economy.md | p3-economy-layer §1 (A) | 7/7 | Done | `war_economy.gd`, `war_works.csv`, fine print and slip entries, test_war_economy | — |
| 2026-10-07-war-room-scale-hover.md | war-room-scale-hover spec | 11/11 | Done | T10's gate called for the patch, so T11 was built (`war_detail_ink.gd`, 31540825); `war_ground.gd`, `war_fine_print.gd`, `war_hover_dwell.gd` | — |
| 2026-10-08-laws-tab.md | laws-tab spec | 9/9 | Done | law_system / law_effects / laws_screen, test_law_guard, test_law_missives, visual review ca15c7ad | T8 step 3 bench numbers not found in the repo (Unclear whether the bench was run) |
| 2026-10-08-war-room-tools-polish-a.md | tools-polish spec, batch A | 9/9 | Done | e0a5b2dd, dac01b0c, 571d047b, aca5cff9, 5a10e3e6, 2488353d, 57724f8a, 8637bc36, b8b178ed (all on main) | — (A's deferred minors were moved to batch D, not done) |
| 2026-10-08-war-room-tools-polish-b.md | tools-polish spec, batch B | 8/8 | Done | PR #20 (19 commits B1–B8 plus critic and final review fixes) | — |

#### 3. Specs with NO plan

- 2026-10-05-prologue-three-acts-design.md (Not started)
- 2026-10-06-army-location-and-town-defence-design.md (Done, built straight from the spec)
- 2026-10-06-war-room-wooden-pieces.md (Done)
- 2026-10-07-march-waypoints-design.md (Done)
- 2026-10-07-war-room-annotations-and-planning-pieces-design.md (Done)
- 2026-10-08-war-room-draw-orders-design.md (Done)
- 2026-10-07-war-room-p3-economy-layer-design.md sub-project B (no p3b plan; done under the 10-10 foraging spec)
- 2026-10-02-war-room-v2-design.md sub-project D (no v2-d plan; partly done under the 10-13 sunlit-chamber spec)
- 2026-10-08-war-room-tools-polish-design.md batches C and D (no plan; C1 shipped in PR #29 without a plan)

#### 4. Plans with unfinished work

None of the 16 plans has an unbuilt task. All the open work sits in specs whose later phases never got a plan:
- tools-polish C2 and D: no plan, not designed.
- v2 D, the room's art: candle flame, flicker, tool box, floor litter.
- enemy-AI P4: enemy ghost pieces in the WAR ROOM.
- prologue three acts: no plan at all.
- laws plan T8: bench evidence unclear.

### 2026-10-10 to 2026-10-14

Nothing in either folder is dated 2026-10-09 or 2026-10-15. Lane: 14 spec files (12 design docs + 2 CSV maps, counted as one data-folders item, so 12 spec items) and 4 plans.

#### 1. Specs

| Spec file | Feature (short) | Plan(s) | Status | Evidence (paths, PR #s, commits) | What is left |
|---|---|---|---|---|---|
| 2026-10-10-foraging-and-desertion-design.md | Army brief B phase I: foraging/plunder, desertion, 13th law `desertion_penalty`, marshal's letters | 2026-10-10-foraging-and-desertion.md | Done | PR #15; `scripts/engine/{forage,desertion,army_conduct}.gd`; `ArmyConduct.day_step` called in `tick_engine.gd:196,494`; law in `data/realm/laws.csv`/`law_effects.csv`; 9 tests (`test_forage`, `test_desertion`, `test_army_conduct_{day,switch,take}`, `test_conduct_{data,state,lines,missives}`); `scripts/engine/guide/foraging_and_desertion.md` | Phase II (prisoners, quarter, ransom) was out of scope for this spec; later built under the battle system (PR #76, `guide/prisoners_and_reports.md`) |
| 2026-10-10-march-slope-detour-design.md | Columns detour slopes steeper than `army_max_slope` (slope as the 3D map draws it) | none | Done | PR #13; `scripts/engine/march_path.gd`; `data/army/balance.csv` `army_max_slope`; `tests/engine/test_march_path.gd`. `army_max_slope` retuned under the landform rework ruling 1 | Nothing; the spec's "rulings made without the owner" were never marked confirmed |
| 2026-10-10-player-sight-and-ghosts-design.md | Crown sight of foes (`player_sight_km`), ghosts from seen/spy/rumour, fogged chips, sighting cards | none | Mostly done | PR #9 (commits 071b7b63, 27d7f0bb, 2088d3e0); `scripts/engine/sighting.gd`; `Map3DContext.fogged/ghosts` (`scripts/map3d/map3d_context.gd:131-132`); `test_sighting.gd`, `test_sighting_invasion.gd`; `guide/sight_and_ghosts.md`; keys in `data/intel/balance.csv` | §6 left over: (1) no visual review of the ghost / seen-foe look on record (`ghost_alpha`, STANDBY vs paused pose, ring/tint, the `≈` chip); (2) the card rows were never reviewed; (3) `WarRoom.believed_hosts` (`scripts/engine/war_room.gd:31`) still returns `[]`, so the war room shows no ghosts |
| 2026-10-11-courier-slope-and-rivers-design.md | Couriers and supply wagons detour scarps, cross water, take rivers/sea at 80% of road pace | none | Done | PRs #24 and #28; `MarchPath.of_pack(repo, water_open)` / `water_runs` (22 references in the engine); `road_speed.csv` rows `river,800` and `sea,800`; `test_courier_ways.gd` and other courier tests | Nothing |
| 2026-10-11-data-folders-by-scene-design.md (+ `-key-map.csv`, `-table-map.csv`) | `data/` split into scene folders, one `balance.csv` per folder, `data/tables.csv` index, dead keys removed | 2026-10-11-data-folders-by-scene.md | Done | PR #39; `data/{army,battle,council,economy,intel,ledger,realm,screens,story,world,maps}/`; `data/tables.csv`; commit 7b9740d2 (dropped 14 dead keys); `test_data_layout.gd`, `test_data_layout_loader.gd`, `test_data_csv_shape.gd` | Small leftovers: flat `data/*.csv` paths are still named in `scenes/models/units/{infantry,cavalry,royal,courier}.tscn`, `scenes/screens/main_menu.tscn` and `scenes/war_room/war_table.gdshader` (`army_art.csv`, `courier_art.csv`, `title_entrance.csv`, `balance.csv`); the remaining dead key `war_hover_budget_ms` still waits on a ruling; difficulty presets were out of scope and are not built; the spec header still says "draft" |
| 2026-10-11-war-room-front-line-design.md | A blue front stroke posts one regiment per post (WarFront), hold on arrival, line formation + DEFEND, camp after N days | none | Done | PR #32 (commits f0413704, 79862326); `scripts/engine/war_front.gd`; `Game.plant_front` via `scripts/ui/war_plan_desk.gd:288`; `battle_stances.csv` `hold … line,DEFEND`; `army_formations.csv` `line_slots`; `camp_after_days`; camp art `scenes/models/buildings/field_camp.tscn` via `assets/3D/buildings/camp_models.tres`; `scripts/map3d/map3d_unit_camps.gd` | PR #73 removed the manual Hold/Steady/Evade menu buttons, but front drafts keep `ARMY_STANCE` on arrival, so the front line still works (partly superseded on the menu side only) |
| 2026-10-12-development-axes-design.md | Renaissance and Chivalry scores, tiers, law drift, tier effects, ruler preference, AI drift, threshold events, honour bound (sub-projects A+B) | 2026-10-12-development-axes.md | Done | PR #45; `scripts/engine/development_system.gd`, wired in `tick_engine.gd:672`, `action_system.gd:1215`, `battle_strength.gd:61`, `battle_rules.gd:129`; `data/realm/development_axes.csv`, `development_tier_effects.csv`, 12 `dev_` law-effect rows; events ev_21+ (`data/story/events.csv`, `flag=dev_*_up_N`); 8 `test_development_*.gd`; `guide/development.md` | Out of scope here: sub-project C (equipment, uniforms, formations and tactics, plus one document per weapon) and the development panel UI, neither of which exists. The `unlock` rows in tier effects are unread. The spec header still says "awaiting owner review" |
| 2026-10-12-ground-detail-textures-design.md | Ground variant sets so close-in meadow/crop/upland texture never visibly repeats | none | Done | PR #48 (phase 0 detiling shift), PR #50 (phase 1: 7 Z-Image variants, `bake_world.split_variants`, 15 layers); `data/screens/map3d/map3d_fields.csv` (`g2_meadow_*`); `scripts/map3d/guide/ground.md` | "Phase 1 tuning" rulings are still pending the owner (2 vs 3 variants per class); no evidence that the acceptance low-tier VRAM bench (11 → 15 layers) was run |
| 2026-10-13-landform-rework-design.md | Heightmap rework: river-corridor phase 0, then option A stream-power erosion for gullies and spurs | none | Mostly done | PR #55 (commits 5db82d63, ad159ace); `tools/map3d/bake_world.py`; `data/screens/map3d/map3d_bake.csv` `erosion_*` keys; owner's rulings recorded | Round 4 + finer erosion shipped. Not reached: the 0.35 slope spike (32.7%). Still open by the critic's account: dark wall and bowl under the range's cloud, saw-tooth escarpment, soft ridgelines. Option B (oriented ridges) was never tried. Stretched cliff texture was handed to the rock-face art (PR #57) |
| 2026-10-13-open-field-layout-design.md | Open-field look: hedges where they stood (phase 1), furlong layout (phase 2), meadow interiors (phase 3), reverse-S (phase 4) | none | Mostly done | PR #59 (phase 1 hedges), PR #63 (phase 3 grass interiors), PR #65 (far view), PR #67 (field edges); spec "Phase 2 trials (2026-10-14): not kept" | Phase 2 (§1 bold furlong layout) was built on the unmerged `feat/open-field-phase2-trials` branch and dropped after critics ranked phase 1 first (Abandoned). Phase 4 (reverse-S, optional) not built. "Open for the owner" defaults remain unconfirmed |
| 2026-10-13-war-room-sunlit-chamber.md | War room art D: west lancet window, sun and lattice shadow, ceiling, full dressing | none | Mostly done | PRs #60, #62, #64, #68; `assets/3D/war_room/{rack,lectern,map_chest,strongbox,window_cushion,floor_candle,rug,scroll_basket,side_table,easel,tapestry}/`; `scenes/war_room/materials/war_window_{glass,lattice}.tres`; `graphics_quality.csv` `war_sun_shadows`, `war_fog` | Tier bench (`scenes/tools/war_room/bench.tscn`) never run (PRs #64 and #68 both say so). PR #68 critic points still open: weak diamonds on the sun band, dark empty east floor, gridded rack scrolls, floor/wall value split. Sconces are in the room mesh, not separate props |
| 2026-10-14-unit-clearance-and-scouting-design.md | No unit overlap (per-arm clearance), halt in front of an occupied target, contact and scout letters, the scouting fan | none | Done | PR #72 (commits 8180cd4e, 27dbb0cb); `scripts/engine/march_clearance.gd`, `army_ground.gd`, `Sighting.scout_day/scout_shape`; `data/army/army_clearance.csv`, `army_scouting.csv`; `scripts/map3d/map3d_unit_scout.gd` + fan shader. Reverses the 2026-10-07 army-split §4 "pass through" ruling; extended later (PR #117 deployment clearance) | Nothing named in the spec |

#### 2. Plans

| Plan file | Implements spec | Tasks done/total | Status | Evidence | Unfinished tasks (named) |
|---|---|---|---|---|---|
| 2026-10-10-foraging-and-desertion.md | 2026-10-10-foraging-and-desertion-design.md | 10/10 (no checkbox ticked: 0/53) | Done | PR #15; the classes, tests and guide named in the spec row are all on main | None |
| 2026-10-11-data-folders-by-scene.md | 2026-10-11-data-folders-by-scene-design.md | 6/6 (0/28 ticked) | Done | PR #39; commit 7b9740d2 (Task 1); `DataRepository.table_path/load_balance` + `test_data_layout_loader.gd` (Task 2); folders + `tables.csv` (Task 3); `test_data_layout.gd` (Task 4); guides name folders (Task 5) | None from the plan. The flat paths still in 5 `.tscn` files and 1 `.gdshader` were not in Task 5's scope (`.md` guides only) |
| 2026-10-12-development-axes.md | 2026-10-12-development-axes-design.md | 8/8 (0/42 ticked) | Done | PR #45; tables (T1), `DevelopmentSystem` and its save (T2), dev law rows and `settle_month` (T3), `arm_permille` (T4), `decree_opinions` (T5), AI drift (T6), ev_21+ events (T7), honour bound + `guide/development.md` (T8) | None |
| 2026-10-12-owner-batch-oct12.md | none (the owner's 16-item debug batch is the plan's own spec section) | Tasks 0–14 + Phases E, V, R all done (0/44 ticked) | Done | PR #40; `scripts/ui/user_dir_migration.gd` (T1), `SpySystem.is_controlled` (T2), `NarrationLeftFrame` (T3/E2), `scenes/hud/load_wheel.tscn` (T4/E3), Hand gone from `war_tool_roll.tscn` (T5/E4), `UNIT_GLOW` (T6), `Map3DLayerAprons` + `apron_{dirt,brick}.tres` (T8/E6), `wind_tilt` (T9), `blocked_runs` (T10), `tray_markers` (T11/E7), `war_chart_tilt_deg` (T12), Candlestick2–4 deleted (E9), `port_plain`/`pier_cliff_landings` (T14) | The plan's own "Outcome" list is still open for the owner: wind sway not visible at play zoom (item 13: needs a wider crest, woods mask or crop cards); no track from a far pier to its town (11); walbover/cambrid_2 piers do not read as their towns'; the 1×4 union sheet is too thin (7); the chart's cream margin is too loud (6); narration busts are full figures with small faces (2); the slope bar reads as a flat badge (5). Implementer rulings R1–R19 are not confirmed |

#### Specs with no plan

- 2026-10-10-march-slope-detour-design.md
- 2026-10-10-player-sight-and-ghosts-design.md
- 2026-10-11-courier-slope-and-rivers-design.md
- 2026-10-11-war-room-front-line-design.md
- 2026-10-12-ground-detail-textures-design.md
- 2026-10-13-landform-rework-design.md
- 2026-10-13-open-field-layout-design.md
- 2026-10-13-war-room-sunlit-chamber.md
- 2026-10-14-unit-clearance-and-scouting-design.md

(Each was built straight from its spec through the PR named above.)

#### Plans with unfinished work

- 2026-10-12-owner-batch-oct12.md: every task landed, but the owner-facing items in its Outcome (wind sway, far-pier track, pier identity, union sheet, chart margin, busts, slope bar) and rulings R1–R19 are still open.
- None of the other three plans has unfinished tasks. All four plans have every checkbox unticked even though the work landed.

### 2026-10-16 onward: battle system and cluster formations

Checkout: origin/main at 73ee9169. Status comes from code, tests, PRs and review notes, not from the docs' own checkboxes. Most small step plans have no checkboxes, or never ticked them; each one maps to one merged PR named after it.

**Candidate-only rule (cluster formations):** `UnitBodies`, `BodyMotion`, `BodyBattle*` and `ClusterLayout` (scripts/engine/unit_bodies.gd, body_motion.gd, body_battle*.gd, cluster_layout.gd) can only be reached through `*_candidate` entry points, for example `TickEngine.begin_body_march_candidate` / `begin_locomotion_march_candidate`. Those entry points are called only from tests (tests/engine/test_body_marches.gd, test_body_placement.gd, test_body_battle_closure.gd). `ClusterLayout` has no caller outside its own file. The guide (scripts/engine/guide/cluster_formations.md) says: "no production lifecycle, load, march, damage or render callers". Campaign play still runs the legacy route. Every CF entry marked "Done" below is **Done (candidate-only, not in production)**.

#### 1. Specs

| Spec file | Feature (short) | Plan(s) | Status | Evidence (paths, PR #s, commits) | What is left |
|---|---|---|---|---|---|
| 2026-10-16-battle-system-design.md | Full battle system: daily battles, roster/recruitment, king and camps, formations/terms/orders/events, prisoners/reports, area tasks, sieges, art/release | 2026-10-16-battle-system-implementation.md + 7 phase sub-plans (folder 2026-10-16-battle-system/); p61a–d1; p2b1–3 | Partial | P1–P5 merged (#78, #79, PR #76 bundle, #89–#160); classes KingSystem, CampSystem, MilitaryRoster, PrisonerSystem, BattleReport, BattleRules/Orders/Events/Merge/Command/Presentation, ArmyTasks exist in scripts/engine/; reviews docs/reviews/battle-system/P1–P5.3.md | §13 area tasks only partly done (issue/preview/travel); §14 sieges (SiegeTactics, works, blockade, assault, contracts) missing; §16–18 P7 art/perf/release missing; national-colour and noble/commoner samples missing |
| 2026-10-17-unit-behavior-and-battlefield-design.md | Automatic unit behaviour, unit tasks, walk/run gait, group positions, pursuit bounds, actual-contact merge, scoped terms | Implementation plan (header names it); p44a–p44e4, p4-pursuit-region, p4-voluntary-battle-gait, 4 × 2026-10-23 p4 plans | Mostly done | BattleTaskSystem; P4.4a–e PRs #89, #93–#95, #97–#100, #102–#104, #106, #107, #109, #116–#118, #126, #129, #130, #132, #135; follow-ups #136–#141, #144, #145, #147, #148, #151–#154, #156, #157, #159, #160, #163, #164; LG01/LG02 #245/#248; fixes #276, #279. Spec header still reads "未实施" (stale) | Search execution (P6.1d2), raid/destroy, return lifecycle; narrow-frontage deployment and reserves (N1/N2 moved to CF); pursuit group contraction (R1/R2); open defect: `BattleSystem._start` declines a battle on blocked deployment ground; P7 presentation |
| 2026-10-19-infantry-arp-knight-design.md | Infantry piece becomes the ARP sword-and-shield knight, clip chosen by situation (army_art.csv `chains`) | **None** | Done | PR #88 (rig/export), PR #101 (install + chains) | Only the owner's open look items in the spec (relaxed idle, shield face, per-figure turn, figures standing in town walls) |
| 2026-10-23-unit-size-and-zoom-presentation.md | Cap of 1000 living per unit, groups of 100 fit, near models of ceil(fit/100), mid/far military symbol and legend | 2026-10-23-unit-size-and-zoom-presentation.md | Done | p4.19.1 #170, p4.19.2 #171, p4.19.3 #173, p4.19.4 #174; follow-ups #177 (restore miniature size), #179, #180 (symbols at the 100 km scale) | None in scope ("reported formation overlap" was left to a separate decision, which LG02 #248 and CF took up) |
| 2026-10-25-cluster-formations-design.md | Physical unit bodies, swept motion, eight multi-unit cluster formations | 2026-10-25-cluster-formations.md | Partial (candidate-only) | 6 of 29 tasks merged (CF01, CF02, CF03, CF04a, CF04b, CF08); CF04c and CF05 partial; docs/reviews/cluster-formations/*; draft PRs #201, #221, #231, #236 | CF04c render/locomotion certificates; CF05 B-MERGE/B-END/B-ROUND; CF06 damage; CF07a/b retiring the legacy route; CF09–CF25 (every formation the player sees, the UI, balance, end-to-end); no production wiring at all |

#### 2. Plans

| Plan file | Implements spec | Tasks done/total | Status | Evidence | Unfinished tasks (named) |
|---|---|---|---|---|---|
| 2026-10-16-battle-system-implementation.md | 10-16 + 10-17 | about 14/22 phase tasks (see table 3) | Partial | P1–P5 merged; P6.1 partial; P6.2/P6.3/P7 have no PR (PRD §6 says the same) | P6.1 remainder, P6.2, P6.3, P7.1, P7.2, P7.3 |
| 2026-10-16-battle-system/01-clock-and-save.md | 10-16/10-17 | 2/2 (P1.1, P1.2) | Done | #78 (P1.1), P1.2 inside #76; reviews P1.md, P1.1-final-acceptance.md, P1.2-final-acceptance.md. The 7 unticked P1.2 boxes are stale | none |
| 2026-10-16-battle-system/02-roster-and-recruitment.md | 10-16/10-17 | 2/4 full + P2.3 mostly + P2.4 superseded | Mostly done | P2.1 #79; P2.2 paid recruitment in #76 plus family losses #125/#127/#128; portraits #105–#124 (287/287 keys), #142 window check; review P2.md, P2-portraits.md | P2.3: national-colour and commoner/noble identity samples (P2-portrait-window-acceptance.md:64 puts them out of scope); P2.4's 50-person `representative_count` replaced by the 100-fit rule (#173) |
| 2026-10-16-battle-system/03-king-and-camps.md | 10-16 | 3/3 | Done | #76; p3-king-acceptance-audit.md, P3.3-map.md, P3.3-review.md; assets/3D/units/king, field_camp. Boxes unticked (stale) | none |
| 2026-10-16-battle-system/04-battle-rules-orders-events.md | 10-16 | 3/3 (P4.1–P4.3) | Done | #76; P4.1.md, P4.2.md, P4.3.md; six battle events in assets/2D/events/battle/ | none in this file (P4.4 lives in the p44* plans) |
| 2026-10-16-battle-system/05-prisoners-and-reports.md | 10-16 | 3/3 | Done | #76; P5.1.md, P5.2.md, P5.3.md | none |
| 2026-10-16-battle-system/06-area-tasks-and-sieges.md | 10-16 | 0/3 full (P6.1 about 40%) | Partial | ArmyTasks, TaskCoverage, data/army/task_kinds.csv; #131, #133, #134, #143; no ARMY_TASK in scripts/ui or scripts/war_room; no SiegeTactics class | P6.1d2 search execution/reporting, P6.1e/g raid and destroy plus the WAR ROOM circle UI, P6.1f supply floor/return/post-battle; P6.2 siege works/blockade/assault/contracts; P6.3 task flags and siege-engine art |
| 2026-10-16-battle-system/07-art-and-release.md | 10-16 | 0/3 | Not started | No P7 PR. Earlier work points toward it: #173/#174 (density/symbols), #176 (archer gear LOD and formation bench) | P7.1 choreography/animation/all-arm national colour; P7.2 visual and 800–1000/10k performance gates; P7.3 full flow, old saves, release |
| 2026-10-18-isolated-step-ci.md | none (owner harness instruction) | 3/3 | Done | HARNESS.1 #83, HARNESS.2 #84, HARNESS.3 #86 (+#87) | none |
| 2026-10-18-p44a-unit-task-ledger.md | 10-17 §4 | 1/1 | Done | #89 | none (later steps all merged) |
| 2026-10-19-p44b1-task-dispatch.md | 10-17 | 1/1 | Done | #93 | none |
| 2026-10-19-p44b2-task-cancellation.md | 10-17 | 1/1 | Done | #94 | none |
| 2026-10-19-p44b3-unit-combat-action.md | 10-17 | 1/1 | Done | #95 | none |
| 2026-10-19-p44b4-unit-task-retreat.md | 10-17 | 1/1 | Done | #97 | none |
| 2026-10-19-p44b5-task-pursuit.md | 10-17 | 1/1 | Done | #98 | none |
| 2026-10-19-p44b6-unit-formation-state.md | 10-17 | 4/4 | Done | #99 | none |
| 2026-10-19-p44b7-formation-receipt.md | 10-17 | 3/3 | Done | #100 | none |
| 2026-10-19-p44b8-public-task-formation.md | 10-17 | 3/3 | Done | #102 | none |
| 2026-10-19-p44b9-war-room-task-ui.md | 10-17 | 5/5 | Done | #103 (+ window evidence #158) | none |
| 2026-10-19-p44c1-gait-arithmetic.md | 10-17 §5 | 1/1 | Done | #104 | none |
| 2026-10-20-p2b1-family-losses.md | 10-16 (P2 leftover) | 1/1 | Done | #125 | none |
| 2026-10-20-p2b2-round-family-losses.md | 10-16 | 1/1 | Done | #127 | none |
| 2026-10-20-p2b3-capture-family-losses.md | 10-16 | 1/1 | Done | #128 | none |
| 2026-10-20-p4-pursuit-region.md | 10-17 §9 | 1/1 | Done | #145 | none |
| 2026-10-20-p4-voluntary-battle-gait.md | 10-17 §5 | 1/1 | Done | #144 (+#147 pursuit/withdrawal contexts, #153 key-point gait) | none |
| 2026-10-20-p44c2-saved-gait.md | 10-17 | 1/1 | Done | #106 | none |
| 2026-10-20-p44c3-pursuit-bounds.md | 10-17 | 1/1 | Done | #107 (+#151 route clipping) | none |
| 2026-10-20-p44c4-target-tracking.md | 10-17 | 1/1 | Done | #109 | none |
| 2026-10-20-p44d1-battle-groups.md | 10-17 | 1/1 | Done | #116 (its 50-person groups later became 100-fit in #173) | none |
| 2026-10-20-p44d2-deployment-lines.md | 10-17 | 1/1 | Done | #118 | none |
| 2026-10-20-p44d3-deployment-clearance.md | 10-17 | 1/1 | Done | #117 | none |
| 2026-10-20-p44d4-contact-strength.md | 10-17 | 1/1 | Done | #126 | none |
| 2026-10-20-p44e1-battle-merge.md | 10-17 §11 | 1/1 | Done | #129 (+#157 ranged-contact merge) | none |
| 2026-10-20-p44e2-unified-commander.md | 10-17 | 1/1 | Done | #130 | none |
| 2026-10-20-p44e3-scoped-terms.md | 10-17 | 1/1 | Done | #132 (+ scope fixes #137, #138, #140, #141) | none |
| 2026-10-20-p44e4-merge-warrants.md | 10-17 | 1/1 | Done | #135 | none |
| 2026-10-20-p61a-task-coverage.md | 10-16 §13 | 1/1 | Done | #131 | none |
| 2026-10-20-p61b-task-preview.md | 10-16 §13 | 1/1 | Done | #133 (+#136, #148, #156 intel fixes) | none |
| 2026-10-20-p61c-task-orders.md | 10-16 §13 | 1/1 | Done | #134 | none |
| 2026-10-20-p61d1-search-travel.md | 10-16 §13.1/.2/.6 | 1/1 | Done | #143; guide scripts/engine/guide/area_tasks.md | Its named dependents P6.1d2, P6.1e/g and P6.1f have no plan and no PR |
| 2026-10-23-p4-group-geometry-visual-acceptance.md | 10-17 §6–8, 14 | 1/1 (G1) | Done | #164 (map consumer), #163 (N0 continuity) | none |
| 2026-10-23-p4-group-readability-repair.md | 10-17 | 1/2 | Partial | R0 #166 (`--yaw3d` capture); no scenes/models change after 10-23 | R1: material separation of the unit scenes at playing scales (editor variants, visual review) |
| 2026-10-23-p4-narrow-deployment-reserves.md | 10-17 §6–8, 12, 14 | N0 1/3; N1, N2 moved to CF | Superseded | N0 #163 merged; N1 #178 closed "superseded: fold … into passable frontage"; docs/reviews/cluster-formations/n1-migration.md hands the requirements to CF02–CF07 | N1/N2 requirements now wait inside CF04b/CF05/CF07 |
| 2026-10-23-p4-pursuit-group-contraction.md | 10-17 §7–9, 12, 14 | 0/2 | Not started | No test_pursuit_group_contraction.gd or test_pursuit_group_distance.gd; it builds on N1, which was superseded; n1-migration.md names no CF step that receives it | R1 region-edge contraction; R2 shared route budget for tactical travel (no longer has an owner) |
| 2026-10-23-unit-size-and-zoom-presentation.md | 10-23 | 4/4 | Done | #170, #171, #173, #174 (+#177, #179, #180) | none (38 boxes unticked, stale) |
| 2026-10-24-signal-hub.md | none (approved in a chat, 2026-10-24) | 1/1 | Done | #175; scripts/ui/signal_hub.gd | none |
| 2026-10-25-cluster-formations.md | 10-25 | 6/29 merged, 2 partial | Partial (candidate-only) | see table 3 | CF04c, CF05 (3 B-steps), CF06, CF07a/b, CF09–CF25 |

#### 3. Battle phases and cluster-formation tasks

| Item | Status | Evidence | Left |
|---|---|---|---|
| P1.1 resumable daily transaction | Done | #78; P1.1-final-acceptance.md | – |
| P1.2 clock bridge and encounter window | Done | #76; P1.2-final-acceptance.md | – |
| P2.1 personnel ledger and commander choice | Done | #79; P2.md | – |
| P2.2 paid recruitment, noble effects, supply | Done | #76 (P2.md "Paid recruitment" checkpoint); family losses #125/#127/#128 | – |
| P2.3 portrait manifest, national colour, estate samples | Mostly done | #105–#124 (287/287 keys, 302 people), #142 | National-colour and commoner/noble identity samples |
| P2.4 display-group count interface (ceil/50) | Superseded | replaced by the 100-fit rule, p4.19.3 #173 | – |
| P3.1 king position, couriers, presence | Done | #76; p3-king-acceptance-audit.md | – |
| P3.2 automatic camps, one-day break camp | Done | #76; scripts/engine/camp_system.gd | – |
| P3.3 king and camp map presentation | Done | #76; P3.3-map.md, P3.3-review.md; assets/3D/units/king, field_camp | – |
| P4.1 formations and per-term parley | Done | #76; P4.1.md | – |
| P4.2 order costs and daily combat | Done | #76; P4.2.md | – |
| P4.3 events, legal auto-decisions, presentation data | Done | #76; P4.3.md | – |
| P4.4 a–e unit tasks, gait, groups, merge (+ follow-ups) | Mostly done | #89–#160, #163, #164, #245, #248, #276, #279 | Open: `BattleSystem._start` (scripts/engine/battle_system.gd:639) declines a battle when a deployment row lands on blocked ground; garrison deaths 584→22 after #248 need a balance ruling; N1/N2 and pursuit contraction are not done |
| P5.1 capture, surrender, conservation | Done | #76; P5.1.md | – |
| P5.2 ransom, exchange, release | Done | #76; P5.2.md | – |
| P5.3 reports and prisoner card | Done | #76; P5.3.md | – |
| P6.1 authorized areas, four task kinds | Partial | a #131, b #133, c #134, d1 #143 | d2 search execution, e/g raid and destroy plus the UI, f return lifecycle |
| P6.2 siege works, blockade, assault, contracts | Not started | no SiegeTactics, no PR | all |
| P6.3 task flags and siege-engine art | Not started | no PR | all |
| P7.1 choreography, animation, national colour | Not started | earlier groundwork only (#173, #174, #176) | all |
| P7.2 visual acceptance and performance gates | Not started | – | all |
| P7.3 full flow, old saves, release | Not started | – | all |
| CF01 body measurements | Done | #186; docs/reviews/cluster-formations/measurements.md | – |
| CF02 fixed footprint, persistent bodies, migration | Done (candidate) | #187–#191; data/army/unit_footprints.csv; unit_bodies.gd | – |
| CF03 swept motion, deterministic yielding | Done (candidate) | #192; body_motion.gd | – |
| CF04a march transaction | Done (candidate) | #193, #194 | – |
| CF04b spawn/park in legal body slots | Done (candidate) | #198, #199 (+B-PV2 #218) | – |
| CF04c map consumer of body paths | Partial | render contract #200, render draft #201 (open); locomotion contract #202 and about 40 merged locomotion/contact PRs (#203–#207, #212, #215–#217, #219, #220, #222–#225, #227–#230, #233–#235, #238–#244, #246, #247, #249–#260, #263, #266, #268, #270, #271); drafts #221 (infantry clips), #231 (archer CERT failure), #236 (archer transition) | Locomotion certificates for infantry, cavalry, archers and royal; merge of #201 |
| CF05 battle movement and enemy contact | Partial (10/13 B-steps) | PV2 #218, BOUNDARY #232, TIME #237, CLOSE #240, CONTACT #261, ENTER #264, DEPLOY #265, CHARGE #267, FLANK #269, WITHDRAW #272 (+#277); contract #209 | B-MERGE, B-END, B-ROUND |
| CF06 contact damage and direct fire | Not started (contracts only) | #210, #213 | implementation |
| CF07a retire in-unit tactics and old orders | Not started | – | all |
| CF07b retire old formation display and controls | Not started | – | all |
| CF08 eight-formation eligibility, pure layout | Done (candidate) | #185; cluster_layout.gd (no caller outside its file) | – |
| CF09 cluster save and member-version commands | Not started | – | all |
| CF10 couriers, receiving units, king with the cluster | Not started | – | all |
| CF11 muster/reform/attacked/failure state machine | Not started | – | all |
| CF12 common slowest speed | Not started | – | all |
| CF13 reinforcement, partial selection, switching | Not started | – | all |
| CF14 line advance + common plan entry | Not started | – | all |
| CF15 archer-infantry coordination | Not started | – | all |
| CF16 double envelopment | Not started | – | all |
| CF17 cavalry charge | Not started | – | all |
| CF18 defence in depth | Not started | – | all |
| CF19 oblique strong wing | Not started | – | all |
| CF20 feigned retreat and counter | Not started | – | all |
| CF21a artillery hold | Not started | – | all |
| CF21b shared condition support and exposure sources | Not started | – | all |
| CF22 box select and cluster command panel | Not started | – | all |
| CF23 known preview, phase receipts, body display agreement | Not started | – | all |
| CF24 numeric experiments and balance | Not started | – | all |
| CF25 end-to-end save, symmetry, real-window acceptance | Not started | – | all |

#### Specs with no plan

- 2026-10-19-infantry-arp-knight-design.md (built directly in #88 and #101).
- (Plans with no spec: 2026-10-18-isolated-step-ci.md and 2026-10-24-signal-hub.md, both from owner or chat instructions.)

#### Plans with unfinished work

- 2026-10-16-battle-system-implementation.md: P6.1 remainder, P6.2, P6.3, P7.1–P7.3.
- 2026-10-16-battle-system/02-roster-and-recruitment.md: P2.3 national-colour and estate samples.
- 2026-10-16-battle-system/06-area-tasks-and-sieges.md: P6.1d2/e/f/g, P6.2, P6.3.
- 2026-10-16-battle-system/07-art-and-release.md: everything.
- 2026-10-23-p4-group-readability-repair.md: R1 material separation.
- 2026-10-23-p4-pursuit-group-contraction.md: R1, R2 (no owner since N1 was superseded).
- 2026-10-23-p4-narrow-deployment-reserves.md: N1/N2, superseded into CF (requirements still unmet on main).
- 2026-10-25-cluster-formations.md: CF04c, CF05 (B-MERGE/B-END/B-ROUND), CF06, CF07a/b, CF09–CF25; drafts #201, #221, #231, #236 open; nothing wired into production.
