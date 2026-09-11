# assets/flux — Flux 批量出图模板

把 `assets/GameArts/中世纪大战略游戏_AI美术Prompt库.md` 的 249 条资源 prompt 喂给本地 ComfyUI 的 Flux 批量生成。**不手写任何 prompt**：每条都是 `STYLE_CORE + 主体 + 画幅片段` 自动拼出来的（库 §0.1 / §10.8）。

## 文件

| 文件 | 作用 |
|---|---|
| `STYLE_CORE.txt` | 库附录 A 逐字复制，唯一真相来源。改风格只改这里。 |
| `NEGATIVE.txt` | 库附录 B。Flux 没有负面 prompt 通道，先留档；将来换带 CFG 的模型/工作流时接上。 |
| `CC Flux Bulk T2I.workflow.json` / `CC Flux2 Klein Bulk T2I.workflow.json` / `CC Post Cutout.workflow.json` | 三张图的 ComfyUI 界面格式副本，已放进本机 ComfyUI 的 `user/default/workflows/`，侧栏 Workflows 里同名，可以打开看结构、手动试一张。 |
| `flux_template.json` | Flux.1 的 API 格式图（schnell）：UNETLoader → DualCLIPLoader(T5+CLIP-L) → CLIPTextEncode → FluxGuidance → KSampler → VAEDecode → SaveImage。没有负面通道。 |
| `flux2_klein_template.json` | Flux.2 [klein] 4B base 的 API 格式图：UNETLoader → CLIPLoader(Qwen3) → 正/负 CLIPTextEncode → CFGGuider → Flux2Scheduler + SamplerCustomAdvanced → VAEDecode → SaveImage。CFG 生效，`NEGATIVE.txt` 真正接上。每张图顶部的 `_slots` 声明脚本要填的字段。 |
| `prompts.csv` | 由库解析出的 249 条：`id, chapter, dir, title, canvas, width, height, subject`。改库后 `--build-csv` 重建，不要手改。 |
| `canvas.json` | 库 §1.3 的 8 个 `[C-…]` 画幅片段。 |
| `generate.py` | 出图驱动脚本，纯标准库，走 `127.0.0.1:8188` 的 HTTP API。 |
| `export_ui_workflows.py` | 把三张 API 模板图连同当前的 STYLE_CORE / NEGATIVE 导出成 ComfyUI 界面格式，并装进本机的 `user/default/workflows/`。改了风格文本或模板后跑一次，侧栏里的图就是最新的。 |
| `post_cutout_template.json` + `post.py` | 后处理（方案 C，2026-09-11）：BiRefNet 去底 → alpha → lanczos 缩放。`full` 档高 660 透明全身像（对应 `assets/portraits/full/`），`chip` 档 96×96 头像（对应 `assets/portraits/`，游戏按 48 设计像素显示）。输出到 `out/game/<tier>/<ID>.png`，不直接覆盖游戏资产。需要 `models/background_removal/birefnet.safetensors`（Comfy-Org/BiRefNet，423 MB）。 |
| `out/<chapter>/` | 产出，按 §0.3 的目录分：characters / map / terrain / icons / tactical / events / ui。文件名 `ID_slug_<model>_s<seed>.png`（同一 ID 不同模型的结果并排保存，便于对比）。 |

## 用法

```bash
python3 assets/flux/generate.py --ids C-01,T-01,I-04          # 指定 ID
python3 assets/flux/generate.py --chapter T --variants 5      # 全部地形贴图，每张 5 个 seed（§5 要求 4–6 变体）
python3 assets/flux/generate.py --chapter I --small           # 图标小尺寸档（§6：追加简化后缀）
python3 assets/flux/generate.py --chapter C --limit 5         # 库 §0.2 第一步：先出前 5 个人物看风格
python3 assets/flux/generate.py --ids C-01 --canvas C-FULL --pose P-05        # 全身档（档案栏）：外貌 + P- 姿态
python3 assets/flux/generate.py --ids C-01 --canvas C-BUST --expression E-08  # 头肩档（头像格）：外貌 + E- 表情
python3 assets/flux/post.py assets/flux/out/characters/C-01_*_c-full_*.png   # 去底缩放成游戏资产
python3 assets/flux/generate.py --ids V-01 --dry-run          # 只打印拼好的 prompt
python3 assets/flux/generate.py --build-csv                   # 库改了之后重建 prompts.csv
```

- `--model klein|schnell`（默认 klein，2026-09-11 对比后定的）：
  - `schnell` = Flux.1 schnell，Apache 2.0 可商用，4 步蒸馏，忽略 guidance，无负面词。
  - `klein` = Flux.2 [klein] 4B **base**，Apache 2.0 可商用，未蒸馏，20 步、CFG 4.0（`--cfg` 可调，库建议 3.5–4.5），负面词生效。模型文件：`diffusion_models/flux-2-klein-base-4b.safetensors`、`text_encoders/qwen_3_4b.safetensors`、`vae/flux2-vae.safetensors`（Comfy-Org 的 HF 仓库 `flux2-klein` / `flux2-dev`）。
  - **不要用 Flux.1 dev、Flux.2 dev、klein 9B**：都是非商用许可，不能做游戏资产的生产底模。
- seed 固定为 `--seed`（默认 954159497，与地图同源）+ 变体序号，同一 ID 重跑结果可复现；表情差分（E-）务必锁 seed 只换表情词。
- **方案 C（2026-09-11 决定）**：人物和事件插图走彩铅风；人物按 `[C-FULL]`（全身，档案栏）和 `[C-BUST]`（头肩，头像格）两档生成再经 `post.py` 去底缩放；地图和 UI 维持现状，只统一调色板（待定）。库默认的 `[C-PORTRAIT]` 半身像只用来定风格。
- 全身/头肩两档用库里人物条目下的 `**外貌**` 行（只有长相和衣着）拼 prompt，再加 `--pose P-xx` / `--expression E-xx` 片段；没有 `**外貌**` 行的人物会退回用主 prompt（会带道具，效果差）。给一个人物补 `**外貌**` 行后 `--build-csv` 重建即可。目前只有 C-01、C-04 有。
- `E-` / `P-` 行是片段（表情/姿态），不是独立资源，脚本会跳过；做差分时把片段接到对应 `C-` 的主体后面。
- `M-` 地图底图按库 §4 需要 ControlNet 喂 GIS 线稿；这里的模板只是纯文生图，跑 M- 只能看画风，不要拿它当地图。
- 图标 §6 要求三档尺寸分别生成：大档直接跑，小档加 `--small`，缩放到 256/128/64 在引擎外处理。

## 尺寸（库 §10.7，按 1024 级生成后再缩）

| 画幅 | 生成尺寸 |
|---|---|
| C-PORTRAIT / C-BUST / C-ICON / C-TILE / C-SYMBOL | 1024×1024 |
| C-FULL | 1024×1536 |
| C-SCENE / C-MAP | 1536×1024 |

## 质检

跑完一批对着库 §10.5 的清单看：纸底色是否统一 `#EDE3CE`、有没有调色板外的色相、铅笔颗粒是否还在、有没有偷偷加墨线、光照是否顶光偏左。
