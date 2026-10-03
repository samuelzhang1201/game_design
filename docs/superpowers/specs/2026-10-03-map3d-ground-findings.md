# 3D 地图地面（草地）观感调查：发现与方案

日期：2026-10-03
范围：`tools/map3d/build_terrain.gd`、`assets/3D/terrain/beria/world.tscn`、`assets/3D/terrain/beria/terrain_assets.tres`、`tools/map3d/bake_world.py`、`tools/map3d/pack_aerial.py`、`scripts/map3d/map3d_ground_tint.gd`
性质：只读调查，未改任何代码或资源。本环境没有 Godot，也没有 GPU，所以**没有截图验证**，结论都来自读代码和构建产物。

---

## 1. 背景：CK3、文明这类游戏的地面为什么好看

战略视角下，地面主要不靠一根根草，而是靠下面五层：

1. **整片手绘的宏观颜色图**（最重要）。CK3 在 `gfx/map/terrain/` 下有一张覆盖全世界的 `colormap`，美术参照卫星图，把冷暖、干湿、青黄过渡都画在这一张图上。细节纹理只负责近处的颗粒感，颜色由它定。
2. **多材质按高度混合**。每个像素记几种地表材质及其权重（CK3 的 `detail_index` / `detail_intensity`），交界处按每张纹理自带的高度通道决定谁盖住谁：草长在石缝里，泥积在低洼处。线性混合会得到一片发灰的糊边。
3. **防重复**：同一纹理用多种尺度采样后混合（近细远粗）；每块随机旋转或偏移 UV；用大尺度噪声扰动颜色和亮度。
4. **光照与后期**：法线贴图配偏低偏暖的太阳、环境光遮蔽（AO）、大气雾，最后用一张调色表（LUT）统一色调。
5. **近景 3D 植被**：树、灌木、石头是实体模型，按密度图批量撒出来，**按缩放分级**显隐。拉远后交给颜色图表现。

此外，这几家都有专门的地图美术参照卫星图逐区域手调。程序生成负责打底，好看的部分大多是手调出来的。

---

## 2. 我们的现状

| 层 | 现状 | 评价 |
|---|---|---|
| 宏观颜色 | `bake_world.py` 程序烘焙 `color.rgba8`（每 20 m 一个顶点）：湿润、干燥色调，庄园色调，田地 | 有，但全是程序生成，没有手调的一层 |
| 高度混合 | 航拍贴图的 alpha 通道里写了高度（`pack_aerial.py:191-201`，用局部明暗生成）；`blend_sharpness` 为 0.85；控制图记录主、副材质和过渡值，并加了抖动（`bake_world.py:341-347, 1342-1343`） | ✅ 已经正确开启 |
| 防重复：每种材质随机旋转 | `detiling_rotation` 在 0.1–0.22 之间（`build_terrain.gd:23-34`） | ✅ 有 |
| 防重复：宏观变色 | `macro_variation1/2` 是 (0.9,0.92,0.95) 和 (0.95,0.92,0.85)，几乎是白色 | 很弱，不过颜色图已经承担了色调 |
| 防重复：双尺度采样 | **没有生效**，见 §3 | ❌ bug |
| 防重复：每顶点 UV 旋转、缩放 | 控制图里没写这几位 | 未使用 |
| 光照与后期 | 日照循环、补光、AgX 色调映射、调色曲线、各画质档的 SSAO/SSIL、深度雾 | ✅ 已经做了很多 |
| 近景植被 | 树木用照片卡片（`Map3DLayerTrees`）；没有灌木和树篱 | 部分 |

当前各地表材质的平铺尺度（`terrain_assets.tres`）：

| id | 材质 | 每块平铺（米） |
|---|---|---|
| 0 | aerial_cliff | 160 |
| 1 | aerial_meadow（草地） | 120 |
| 2 | dry_decay_leaves | 160 |
| 3 | dirt_floor | 180 |
| 4 | aerial_upland | 200 |
| 5 | excavated_soil_wall | 240 |
| 6 | sand_03 | 120 |
| 7 | aerial_canopy | 170 |
| 8 | aerial_snow | 180 |
| 9 | aerial_crop | 140 |

---

## 3. 发现一（bug）：双尺度采样从来没生效

`tools/map3d/build_terrain.gd:119-122`：

```gdscript
terrain.material.auto_shader = false
for key: String in SHADER_PARAMS:
	terrain.material.set_shader_param(key, SHADER_PARAMS[key])
terrain.material.dual_scaling = true
```

脚本**先**写入 shader 参数，**后**打开 `dual_scaling`。写参数的时候 shader 里还没有双尺度相关的 uniform，这几个值就丢了。构建产物 `assets/3D/terrain/beria/world.tscn:31-48` 里它们全是 `null`：

```
"dual_scale_far": null,
"dual_scale_near": null,
"dual_scale_reduction": null,
"dual_scale_texture": null,
"tri_scale_reduction": null
```

设计意图（`build_terrain.gd:42-46`）：

```gdscript
# dual scale: grass far away at 0.3x its tile, near/far past the rig's 800 m
"dual_scale_far": 4000.0,
"dual_scale_near": 1200.0,
"dual_scale_reduction": 0.3,
"dual_scale_texture": 1,      # aerial_meadow
```

也就是草地在 1.2–4 km 之外渐变为 0.3 倍的大尺度纹理（每块约 400 m），用来消除远处的棋盘格。

**实际运行**：这几个参数取 Terrain3D shader 的默认值。按我的记忆，默认值是材质 0（**悬崖**）、近处约 100 m、远处约 170 m，这需要在编辑器里核实。所以双尺度很可能作用在悬崖上，草地在任何距离都按 120 m 一块平铺。重复最明显的应该是中景（视距 1–10 km）。

**历史**：这个顺序问题从地形构建提交进仓库那一次（`43d7782`）就存在，主人在画面上**从来没见过**双尺度生效后的样子。

**状态（2026-10-04）：已修复，`93aab60`。**
- 新增 `build_terrain.gd` 的 `apply_material`：先开双尺度，再写参数；新增 `apply_tiles`。
- 新增 `build_world.gd --material-only`：不需要本机原始烘焙文件，直接把材质和平铺尺度重新写进已提交的构建。
- `world.tscn` 里的 5 个参数已填成设计值。草地在 1.2–4 km 之间渐变为 0.3 倍。
- 悬崖的平铺尺度从 160 m 改为 160 / 0.3 ≈ 533 m，保持主人认可时的大小。当时悬崖实际上一直按默认的 0.3 倍双尺度绘制：相机最近 400 m，最近可见的地面约 210 m，已超出默认的 170 m 远端。
- 新增测试 `tests/map3d/test_map3d_build_material.gd`，守住参数顺序、已提交构建里没有 null 参数，以及平铺尺度与 `TEXTURES` 表一致。

---

## 4. 发现二：高度混合已正确开启

- `pack_aerial.py` 把每张图的局部明暗（减去邻域平均）归一化后写进 alpha 通道当作高度，`--height-gain` 控制强度；
- `blend_sharpness` 为 0.85（Terrain3D 的锐度 = 8 + 56 × 0.85 ≈ 56），偏锐利；
- `blend_byte` 取权重最高的两种材质，用 smoothstep 让过渡更陡，再加抖动防止色带。

这部分暂时不用动。如果交界处看着糊，先查对应贴图的 `--height-gain`，而不是这里。

---

## 5. 发现三：防重复只用了一半

- 已经在用：每种材质的 `detiling_rotation`，以及很淡的宏观变色。
- 没用到：Terrain3D 的控制图允许**每个顶点单独设置 UV 旋转和缩放**（控制图位格式里的 uv angle 和 uv scale 位），`bake_world.py:1343` 只写了主材质、副材质和过渡值。用低频噪声把这几位填上，可以在不换贴图的情况下打散重复。

---

## 6. 更正：近景 3D 草丛不可行

- 最近缩放 `map3d_zoom_min_m` 是 400 m，近处俯仰 −22°，视场 45°。在 1080p 下，目标点处一个屏幕像素约 0.3 m，前景更粗。
- 一簇 1 m 的草只有 2–3 个像素，看不出来，所以**不做草丛**。
- 在这个尺度上能看出来的是 3–10 m 的东西：**田埂上的树篱、灌木丛、林缘的矮树**，有 10–30 个像素。可以沿用树木的照片卡片做法（`tree_card.gdshader` + 图集）。

---

## 7. 方案（按投入产出排序）

| # | 做什么 | 规模 | 需要什么 |
|---|---|---|---|
| 1 | ✅ 已完成（`93aab60`）**修复双尺度**：把 `build_terrain.gd` 里的 `dual_scaling = true` 移到参数循环之前；把 `world.tscn` 里 5 个 `null` 填成设计值（效果等同重建，因为重建需要只在本机的原始烘焙文件 `height.r32` / `control.r32` / `color.rgba8`） | 小 | 在编辑器里确认 `dual_scale_far` 4000 不被 hint_range 截断；按视觉审查流程在中景截图对比 |
| 2 | **每顶点 UV 噪声**：在 `bake_world.py` 写控制图时，用低频噪声填 uv angle 和 uv scale 位，参数放进 `map3d_bake.csv` | 中 | 本机跑 `tools/map3d/build_pack.sh` 重建，截图对比 |
| 3 | **可手画的宏观色调覆盖层**（CK3 颜色图的做法）：一张覆盖整个地图包的低分辨率 PNG，由美术或 AI 按区域画冷暖、干湿，在烘焙时乘进 `color.rgba8` | 中到大 | 主人定方向：画什么、谁来画 |
| 4 | **树篱、灌木**：沿田埂（`sow_patchwork` 里的田块边界）和林缘撒照片卡片，按距离淡出 | 大 | 主人拍板（属于新加内容），再生成卡片素材 |

不做：3D 草丛（理由见 §6）；光照与后期（已经调过很多轮，不是瓶颈）。

#1 已完成，下一步建议做 #2（每顶点 UV 噪声），它需要在本机重建地形。
