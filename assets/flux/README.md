# assets/flux — Flux 批量出图模板

把 `development/Visuals/中世纪大战略游戏_AI美术Prompt库.md` 的 284 条资源 prompt 喂给本地 ComfyUI 的 Flux 批量生成。**不手写任何 prompt**：每条都是 `STYLE_CORE + 主体 + 画幅片段` 自动拼出来的（库 §0.1 / §10.8）。

## 文件

| 文件 | 作用 |
|---|---|
| `STYLE_CORE.txt` | 库附录 A 逐字复制，人物 / 事件插图 / UI 的唯一真相来源。改风格只改这里。 |
| `STYLE_CORE_map_sepia.txt` + `NEGATIVE_map_sepia.txt` + `NEGATIVE_map_sepia_natural.txt` | 地图符号专用风格核（库 §6.9，owner 2026-09-12 定）：单色深褐、手绘故事书地图风、平侧立面。**负面词必须另立一份**——默认那份把 `sepia` / `aged paper` / `antique print` 全禁了，正是这套要的东西。`generate.py` 按文件名自动配对（`STYLE_CORE_<x>.txt` ↔ `NEGATIVE_<x>.txt`），也可以用 `--negative-file` 手动指定。**自然件（树/山/田/沼泽）必须手动指定 `NEGATIVE_map_sepia_natural.txt`**——否则模型会往每张图里塞教堂和城堡，见库 §6.9 的说明。 |
| `NEGATIVE.txt` | 库附录 B。Flux 没有负面 prompt 通道，先留档；将来换带 CFG 的模型/工作流时接上。 |
| `CC Flux Bulk T2I.workflow.json` / `CC Flux2 Klein Bulk T2I.workflow.json` / `CC Post Cutout.workflow.json` / `CC Sepia Map Mark T2I.workflow.json` / `CC Post Sepia Alpha.workflow.json` | 五张图的 ComfyUI 界面格式副本，已放进本机 ComfyUI 的 `user/default/workflows/`，侧栏 Workflows 里同名，可以打开看结构、手动试一张。 |
| `flux_template.json` | Flux.1 的 API 格式图（schnell）：UNETLoader → DualCLIPLoader(T5+CLIP-L) → CLIPTextEncode → FluxGuidance → KSampler → VAEDecode → SaveImage。没有负面通道。 |
| `flux2_klein_template.json` | Flux.2 [klein] 4B base 的 API 格式图：UNETLoader → CLIPLoader(Qwen3) → 正/负 CLIPTextEncode → CFGGuider → Flux2Scheduler + SamplerCustomAdvanced → VAEDecode → SaveImage。CFG 生效，`NEGATIVE.txt` 真正接上。每张图顶部的 `_slots` 声明脚本要填的字段。 |
| `prompts.csv` | 由库解析出的 284 条：`id, chapter, dir, title, canvas, width, height, subject`。改库后 `--build-csv` 重建，不要手改。 |
| `canvas.json` | 库 §1.3 的 9 个 `[C-…]` 画幅片段。 |
| `generate.py` | 出图驱动脚本，纯标准库，走 `127.0.0.1:8188` 的 HTTP API。 |
| `export_ui_workflows.py` | 把 API 模板图连同各自的 STYLE_CORE / NEGATIVE 导出成 ComfyUI 界面格式，并装进本机的 `user/default/workflows/`。改了风格文本或模板后跑一次，侧栏里的图就是最新的。 |
| `post_cutout_template.json` + `post.py` | 后处理（方案 C，2026-09-11）：BiRefNet 去底 → alpha → lanczos 缩放。`full` 档高 660 透明全身像（对应 `assets/portraits/full/`），`chip` 档 96×96 头像（对应 `assets/portraits/`，游戏按 48 设计像素显示）。输出到 `out/game/<tier>/<ID>.png`，不直接覆盖游戏资产。需要 `models/background_removal/birefnet.safetensors`（Comfy-Org/BiRefNet，423 MB）。 |
| `sepia_alpha_template.json` | `D-` 地图符号的去底图（2026-09-12）：蓝通道（白纸 1.0、深褐墨 ~0.15）→ InvertMask 得墨迹覆盖率 → MaskComposite 自加一次（×2 并 clamp，淡色平涂转不透明、纸底仍全透）→ InvertMask（`JoinImageWithAlpha` 读 1 为透明）→ **ImageCrop 按画面自身的包围盒裁掉空边** → ImageScale（width 0，保裁切后的比例，按高度定尺寸）。**不走 BiRefNet**：线稿没有剪影可抠，而且 ×2 覆盖率能把笔触毛边留成半透明。裁切不是可选项：侧立面符号在方画框里只占 47%–77% 的高，不裁的话决定它在地图上多大的是空白边距而不是画本身（大都会会画得比集镇还矮）。`post.py` 纯标准库解 PNG 扫蓝通道算包围盒（`ink_bounds`，阈值由图里那条 alpha 公式反推成蓝 ≤ 243），`--no-trim` 可关。 |
| `post.py --tone` | **统一色温**（2026-09-12）：把成品白平衡到库 §1.4 的唯一纸底色 Cream Laid `#EDE3CE`（§10.5 原本要求人工并排目检这一条）。量源图最亮的 10% 当作纸底，求逐通道增益，clamp 到 0.75–1.35 再乘上去；增益是**乘法**不是加法，所以暗墨不会被抬灰，alpha 不动。**在源图上量、在成品上改**——去底会把纸抠掉，拿成品去量会测到主体本身（蜡封量出来的「纸底」是 `#775951`，增益顶到上限去提亮蜡）。源图最亮处亮度不到 150 就判定没有纸，整件跳过。默认关，要加 `--tone` 才生效。 |
| `install_map_art.py` | 把某一章的出图变成游戏资产：去底 → 缩放 → （地图符号还要）去色 + 提亮 → 按 `<code>.png` 装进目标目录。`goods` 走 `assets/goods/`（灰度，引擎按货物类别染色），`cast` 走 `assets/portraits/`（保留颜色，立绘是用来看的不是用来染的）。映射表是 `goods_art.csv` / `cast_art.csv`（流水线用，不是运行时数据）。 |
| `out/<chapter>/` | 产出，按 §0.3 的目录分：characters / cast / map / terrain / icons / decor / goods / tactical / events / ui。文件名 `ID_slug_<model>_s<seed>.png`（同一 ID 不同模型的结果并排保存，便于对比）。 |

## 用法

```bash
python3 assets/flux/generate.py --ids C-01,T-01,I-04          # 指定 ID
python3 assets/flux/generate.py --chapter T --variants 5      # 全部地形贴图，每张 5 个 seed（§5 要求 4–6 变体）
python3 assets/flux/generate.py --chapter I --small           # 图标小尺寸档（§6：追加简化后缀）
python3 assets/flux/generate.py --chapter C --limit 5         # 库 §0.2 第一步：先出前 5 个人物看风格
python3 assets/flux/generate.py --ids C-01 --canvas C-FULL --pose P-05        # 全身档（档案栏）：外貌 + P- 姿态
python3 assets/flux/generate.py --ids C-01 --canvas C-BUST --expression E-08  # 头肩档（头像格）：外貌 + E- 表情
python3 assets/flux/post.py assets/flux/out/characters/C-01_*_c-full_*.png   # 去底缩放成游戏资产
python3 assets/flux/generate.py --chapter D --style-file STYLE_CORE_map_sepia.txt   # 库 §6.9 手绘地图符号（31 条：装饰件 + 聚落五档）
python3 assets/flux/generate.py --ids I-04 --canvas C-MAPMARK --style-file STYLE_CORE_map_sepia.txt  # 已有 I- 主体换这套风格重出
python3 assets/flux/post.py assets/flux/out/decor/D-*.png                     # 白底转 alpha，256 px 地图贴图
python3 assets/flux/generate.py --ids V-01 --dry-run          # 只打印拼好的 prompt
python3 assets/flux/generate.py --build-csv                   # 库改了之后重建 prompts.csv
```

- `--model klein|schnell`（默认 klein，2026-09-11 对比后定的）：
  - `schnell` = Flux.1 schnell，Apache 2.0 可商用，4 步蒸馏，忽略 guidance，无负面词。
  - `klein` = Flux.2 [klein] 4B **base**，Apache 2.0 可商用，未蒸馏，20 步、CFG 4.0（`--cfg` 可调，库建议 3.5–4.5），负面词生效。模型文件：`diffusion_models/flux-2-klein-base-4b.safetensors`、`text_encoders/qwen_3_4b.safetensors`、`vae/flux2-vae.safetensors`（Comfy-Org 的 HF 仓库 `flux2-klein` / `flux2-dev`）。
  - **不要用 Flux.1 dev、Flux.2 dev、klein 9B**：都是非商用许可，不能做游戏资产的生产底模。
- **不要把 `generate.py` 的输出接进管道**（2026-09-13 两次踩到）：`head` 收够行数就关管道，`generate.py` 吃到 SIGPIPE 提前退出，图在 ComfyUI 里生成了却没下载；`tail` 更阴险，它既把 `FAILED` 那几行滚掉了，又把**整条管道的退出码换成了 tail 自己的 0**——任务报成功，实际少了两张。**重定向到文件再看**：`python3 generate.py ... > run.log 2>&1`，跑完 `grep -c saved run.log` 对一下张数。
- seed 固定为 `--seed`（默认 954159497，与地图同源）+ 变体序号，同一 ID 重跑结果可复现；表情差分（E-）务必锁 seed 只换表情词。
- **地图上的图标**：聚落贴图（`assets/settlements/`，`settlement_art.csv`）和兴趣点图标（`assets/markers/`，`marker_art.csv` 把地图包的 29 种标记类型映射到 13 个库图标）都来自这条流水线：`generate.py --ids I-xx` → `post.py --tier icon --size N --out-dir …` → 复制进 assets。聚落按档 256→136 px，兴趣点 64 px（地图上按 `map_marker_px` 固定 16 屏幕像素画）。
- **地图符号单色化（2026-09-12 决定，已上线）**：`assets/settlements/` 六张贴图已换成 `D-27`~`D-31` 的单色版（`settlement_art.csv` 的 notes 同步），配合改成羊皮纸的地图底。**换完 PNG 必须跑一次 `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --import`**，否则 Godot 用的还是 `.godot/imported/` 里的旧 `.ctex`，游戏里看不到变化。owner 选了手绘单色深褐的故事书地图风（参考 `development/exmaples/`），只作用在地图符号上——`D-01`~`D-31`（库 §6.9：散布装饰件 `D-01`~`D-26` 是针叶/阔叶树丛、丘陵、山脉、条田、路牌、枯树、城门楼、帆船、沉船、海怪、棕榈、波纹记号…，`D-27`~`D-31` 是平侧立面重写的聚落五档）以及用 `--canvas C-MAPMARK` 重出的单体 `I-` 条目。**聚落五档不要复用 `I-01`~`I-05`**：那五条主体是当年为 `[C-ICON]` 的俯视 3/4 角写的，本身就在描述立体沙盘，换画幅压不住（2026-09-12 首批试图验证过）。人物和事件插图不受影响，继续走下面的方案 C 彩铅风。`[C-MAPMARK]` 的**纯白底是硬要求**，`sepia_alpha_template.json` 靠它抠透明；生成时底一旦带羊皮纸色或画框，去底就会连着底一起留下。产出在 `out/decor/` 和 `out/game/mark/`，**不覆盖 `assets/settlements/`**。
- **方案 C（2026-09-11 决定）**：人物和事件插图走彩铅风；人物按 `[C-FULL]`（全身，档案栏）和 `[C-BUST]`（头肩，头像格）两档生成再经 `post.py` 去底缩放；地图和 UI 维持现状，只统一调色板（待定）。库默认的 `[C-PORTRAIT]` 半身像只用来定风格。
- 全身/头肩两档用库里人物条目下的 `**外貌**` 行（只有长相和衣着）拼 prompt，再加 `--pose P-xx` / `--expression E-xx` 片段；没有 `**外貌**` 行的人物会退回用主 prompt（会带道具，效果差）。给一个人物补 `**外貌**` 行后 `--build-csv` 重建即可。目前只有 C-01、C-04 有。
- `E-` / `P-` 行是片段（表情/姿态），不是独立资源，脚本会跳过；做差分时把片段接到对应 `C-` 的主体后面。
- `M-` 地图底图按库 §4 需要 ControlNet 喂 GIS 线稿；这里的模板只是纯文生图，跑 M- 只能看画风，不要拿它当地图。
- 图标 §6 要求三档尺寸分别生成：大档直接跑，小档加 `--small`，缩放到 256/128/64 在引擎外处理。

## 尺寸（库 §10.7，按 1024 级生成后再缩）

| 画幅 | 生成尺寸 |
|---|---|
| C-PORTRAIT / C-BUST / C-ICON / C-TILE / C-SYMBOL / C-MAPMARK | 1024×1024 |
| C-FULL | 1024×1536 |
| C-SCENE / C-MAP | 1536×1024 |

## 质检

跑完一批对着库 §10.5 的清单看：纸底色是否统一 `#EDE3CE`（这一条现在可以让 `post.py --tone` 直接做掉，不用靠眼睛）、有没有调色板外的色相、铅笔颗粒是否还在、有没有偷偷加墨线、光照是否顶光偏左。

`D-` 另有一份：底是不是纯白（不是米色、不是羊皮纸）、有没有第二个色相混进来、有没有画出地台或投影、阴影是不是一律落在右下、缩到 32 px 还认不认得出。
