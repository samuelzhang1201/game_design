# Interchangeable weapons and shields: one attachment contract across modelling, rigging and animation

A unit's weapon and shield are separate assets fitted to named attachment bones; helmet, clothes and breastplate stay part of the figure. Three stages share one recorded attachment mapping, so each stage below states what it adds and the contract at the end holds for all three. The Blender skills (`3d-model-build-up`, `blender-auto-rig`, `blender-natural-animation`) apply it; this guide is the project's copy of the rules.

## 1. Modelling

Beyond the King's Words 的武器和盾牌必须独立建模、独立导出，不能合并进人物网格；头盔、衣服和胸甲为人物固定部分。

- **统一装配基准**：建模前读取目标人物及绑骨交付的挂点约定，统一真实单位、人物比例、握持位置和局部坐标朝向。同类装备沿用同一约定；已有约定不得逐件另设。不同长度的武器保留合理尺寸，不要为了包围盒一致而统一缩放。
- **握持原点**：武器的装配根节点或原点设在约定的手握位置；盾牌设在约定的握把或前臂安装位置。明确记录局部轴向、安装侧、比例及必要的局部偏移，使游戏按人物骨骼挂点装配时无需逐件目测修正。
- **独立资产**：装备可由多个建模部件组成，但每件装备有独立装配根节点，导出不夹带人物网格。人物与装备保持相同单位和导出轴向，应用缩放时不得破坏握持基准。
- **装配验证**：交付前将武器、盾牌挂到目标人物骨骼挂点上检查比例、朝向、握持和身体/固定盔甲间隙；同类替换装备逐件验证。保留带装备的预览供动画调试，最终人物与装备仍分别导出，并重新导入验证对齐。缺少目标人物或挂点约定时，注明采用的临时基准及尚未验证的装配项，不得声称已完成兼容验证。

## 2. Rigging

For Beyond the King's Words characters, reserve named weapon and shield attachment bones when building the rig, even when the equipment is not present. Helmets, clothes and breastplates remain fixed parts of the character.

- Parent the weapon attachment bone to the wielding hand and the shield attachment bone to the shield-bearing hand or forearm, matching the intended grip. Measure placement using the equipment or dimensionally accurate proxies; record stable names, parent bones, local grip transforms, scale and orientation for runtime attachment.
- Attachment bones carry rigid equipment and need no character vertex weights. Keep weapons and shields as separate objects/assets; do not merge or skin interchangeable equipment into the character mesh.
- Test both attachments through representative arm poses with the weapon and shield fitted. Confirm stable grip, correct facing and clearance from the body and fixed armour. Hand off the equipped authoring setup to the animation workflow.
- **Export gate:** preserve both attachment bones in the exported character skeleton. The Only Deform Bones / `export_def_bones=True` recipe below must not strip them: use an export skeleton/filter that retains the attachment bones and their parent hierarchy. Re-import the GLB and check their names, parents and transforms, then attach the separate equipment again to verify alignment. Include this attachment mapping in the hand-off report.

## 3. Animation

For Beyond the King's Words characters, weapons and shields are interchangeable; helmets, clothes and breastplates are fixed parts of the character.

- Fit the intended weapon and shield as separate objects on the character's bone attachment points **before authoring or adjusting animation**. Keep them visible during motion review; do not approve an armed animation from the character alone. If final assets are unavailable, use proxies matching their dimensions and grip positions.
- Tune grip, wrist and elbow poses, weapon arcs, shield coverage and body clearance with the equipment attached. Check the full clip for slipping grips and intersections with the body or fixed armour. A firmly held weapon or shield follows its attachment rigidly; do not apply the generic damped-follow rule to that grip.
- Group clips by grip configuration (such as one-handed weapon with shield or two-handed weapon). Review compatible replacement equipment against those clips; a different grip configuration needs its own appropriate animation.
- Keep equipment separate throughout authoring and export. Export the character mesh, skeleton and animation clips without the interchangeable weapon/shield meshes; export weapons and shields as separate assets. Preserve and document attachment bone/socket names, local grip transforms, scale and orientation so the game can reproduce the reviewed placement. Do not join equipment into the character mesh or bake it into the character asset.
- Validate the exported assets together again, attached as they will be in game, to confirm grip and clearance survive export.

### Shared equipment attachment contract (model → rig → animation)

For this project's interchangeable weapons and shields, all three workflows use the same recorded attachment mapping. Read it before work; if absent, establish and hand it off before claiming compatibility. Preserve existing validated names rather than inventing a different convention at each stage.

- **Mapping:** record weapon/shield attachment bone name, parent hand/forearm bone, mounting side, grip configuration, socket rest transform relative to its parent, equipment grip-root transform relative to the socket, and local forward/up axes. Distinguish these two transforms to avoid applying the same offset twice. Keep the mapping with the asset's authoring hand-off so all three stages can read it.
- **Scale and axes:** use metres (1 Blender unit = 1 metre), applied object scale of 1, and the same export axis settings for character and equipment. Character authoring faces Blender −Y with +Z up; equipment local axes follow the recorded grip mapping, not the character's world-facing direction. Preserve plausible equipment dimensions; do not resize every weapon to an identical bounding box. Verify the imported orientation rather than assuming a Blender-to-engine forward-axis conversion.
- **Rig and motion:** retain dedicated weapon and shield attachment bones in the character skeleton, parented to the appropriate hand/forearm. Equipment stays rigidly attached with the recorded local transform during ordinary holds; no spring lag or accidental grip sliding. Intentional regrips require an explicit matching clip and validation. Animate and review with the separate equipment fitted.
- **Export:** character GLB contains the character, skeleton (including attachment bones and their required hierarchy), and intended animation clips; interchangeable equipment meshes are excluded and exported separately. Bake animation to the export skeleton, including animated attachment transforms where used. Bone filters must retain attachment bones even when they have no vertex weights. Character and clips retain the same bone names, hierarchy and rest transforms.
- **Round-trip gate:** re-import character, clips and separate equipment; check attachment names/hierarchy, dimensions, axis orientation and the two local transforms. Assemble using the recorded mapping and review representative clip frames for grip stability and body/armour clearance. Proxies permit authoring but do not prove final-asset compatibility; report missing assets or unverified checks explicitly.
