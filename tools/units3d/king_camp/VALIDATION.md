# P3.3 asset delivery checks

Final isolated Blender 5.2 build and round-trip validator passed on 2026-10-17. Python syntax compilation passed. No live editor or game code touched.

King: 19,289 triangles, 4 materials, 53 bones; five required clips only. All new king geometry passes audit_game. Preserved donor body does not: welded copy reports 15 inherited non-manifold edges and 4,265 allowed boundary edges. No original donor geometry, weights or clips were simplified.

MARCH: 0.533333 s, 2.4 m measured stride (interior stance steps about 0.150000 m/frame × 16). Donor-vs-reimported-king bone matrices differ by at most 1.07288361e-06. STANDBY/OBSERVE/COMMAND/INSPIRE: 4 s each. All five clip endpoints close below 1e-16 matrix error. All exported vertices: zero missing weights, zero >4 influence vertices, zero unnormalized weights.

Camp: 5,472 triangles, five materials, all six facility audits pass. Each facility minimum local Blender Z is exactly zero; runtime positions them separately. No camp animation or royal marker.

Dimensions including ropes/protrusions (Blender XYZ, metres):
- CommandTent: 5.584 × 6.618 × 3.125
- TentA: 3.984 × 3.298 × 1.925
- TentB: 3.984 × 3.298 × 1.925
- SupplyCart: 2.000 × 3.683 × 1.460
- Stores: 2.130 × 1.780 × 1.230
- Watch: 2.200 × 0.335 × 3.000

King meshes: KingBody, Crown, Mantle, RoyalStandardPole, RoyalStandard, RoyalStandardStripe. Rig: king_rig. Standard is saddle mounted; crown follows head; mantle follows R_Chest. Retains donor Lance/Shield bones with original fixed gear.

Validation/source evidence (git-ignored; rebuild recreates):
- assets/3D/characters/king/model_wip/king.blend
- assets/3D/characters/king/model_wip/build_report.json
- assets/3D/characters/king/model_wip/roundtrip.json
- assets/3D/characters/king/model_wip/MARCH_contact_sheet.jpg and MARCH.gif
- assets/3D/characters/king/model_wip/{MARCH_side,MARCH_front,STANDBY_quarter,OBSERVE_quarter,COMMAND_quarter,INSPIRE_quarter}_*.png
- assets/3D/buildings/field_camp/model_wip/field_camp.blend
- assets/3D/buildings/field_camp/model_wip/overview.png and overview_side.png
- assets/3D/buildings/field_camp/model_wip/build_report.json and roundtrip.json

Limits: donor mounted-idle vertex bounds reach roughly -0.036 m; no sole-contact penetration or brand-new hoof calibration is claimed. Cloth remains rigidly skinned. Gait is inherited and numerically preserved, not newly authored FK locomotion. Ground contact on slopes/water, close-up gesture feel, Godot loop/compression imports and independent visual critic remain the root integration owner’s real-window checks. No game suite or commit performed.

## Integration scope (2026-10-18)

The owner designated these assets as placeholders and explicitly waived further review of generated art; replacement Tripo assets are planned. Godot import/loop assertions and camp phase/grounding/selection logic are integration checks. No final visual or production-art acceptance is claimed.
