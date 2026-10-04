# 美术合作工具包

《王冠与议会》的美术由一位不写代码的美术用 AI 工具制作（owner 2026-10-01）：2D 在她自己电脑上的本地 ComfyUI 里用 **Z-Image Turbo** 和 **Qwen-Image-2512** 出图（不用任何 Flux 模型），3D 在 **Tripo**（owner 的付费账户）生成、在 **Blender** 里减面、拆材质、做骨骼和动作，导出 GLB 交给开发。

完整的合作手册（分工、交接、风格圣经、交付规格、版权）在 Claude Docs：<https://claude.ai/code/artifact/0d99243e-edbb-4ff7-869a-96ed208d47db>

## 给美术

| 文件 | 用途 |
| --- | --- |
| `kit/comfyui/*.json` | 一类资源一个**锁定工作流**。拖进 ComfyUI 画布即可打开，只改「② 主体（只改这里）」和「④ 文件名」里的「编号」。说明见 `kit/comfyui/README.md` |
| `kit/comfyui_cloud/*.json` | 同一套工作流的 **Comfy Cloud 版**：她的电脑跑不动 Qwen 时用（owner 2026-10-01）。只有 Qwen 的模型换成云端的全精度原版，其余一样；第一次要把 8 步 LoRA 导入自己的 Cloud 账户，见 `kit/comfyui_cloud/README.md` |
| `kit/blender/cc_art_check.zip` | Blender 插件「美术自检」：编辑 › 偏好设置 › 插件 › 右上角下拉菜单 › 从磁盘安装，选这个 zip。装好后在 3D 视图按 N，侧栏「王冠与议会」 |
| `需求卡模板.md` | 开发给每个资源写的需求卡长这样 |
| `任务表.csv` | 共享任务表的表头和第一周的试跑条目（导入到共享表格里用） |

本地 ComfyUI 需要（48–64 GB 统一内存的 Mac，或 24 GB 以上显存的 N 卡；不够就改用 Comfy Cloud）：ComfyUI-GGUF 节点，以及 `assets/flux/download_models.sh` 列出的这些文件，一字不差：

- `diffusion_models/qwen-image-2512-Q6_K.gguf`、`text_encoders/qwen_2.5_vl_7b.safetensors`、`vae/qwen_image_vae.safetensors`、`loras/Qwen-Image-2512-Lightning-8steps-V1.0-bf16.safetensors`
- `diffusion_models/z_image_turbo_bf16.safetensors`、`text_encoders/qwen_3_4b.safetensors`、`vae/ae.safetensors`

## 给开发

- `python3 tools/art_kit/build_kit.py` — 重建 `kit/`（工作流和插件 zip）。改了任何 `assets/flux/STYLE_CORE*` / `NEGATIVE*`、`canvas.json`、模板或预设之后都要重跑。
- `python3 tools/art_kit/extract_specs.py`（需要 `pip install bpy`，或 `blender -b --python`）— 从 `data/map3d_houses.csv` 和游戏现用的兵种 GLB 重写插件的 `specs.json`（面数上限、材质名、骨架、动作）。改了房屋表或兵种骨架之后先跑它，再跑 `build_kit.py`。
- 插件源码在 `tools/art_kit/blender/cc_art_check/`；它的检查和游戏自己的测试同一套口径（`tests/map3d/test_map3d_houses_meshes.gd` 的破洞统计、运行时要的 `head` 骨骼和动作名、`tools/map3d/blender_houses/kit.py` 的导出规则）。
- 收到交付后：2D 原图进 `assets/flux/out/` 再跑 `install_map_art.py`。GLB 放进 `assets/3D/{buildings,units}/<名字>/`：每个房屋、兵种在游戏里是继承它的场景（`scenes/models/buildings/`、`scenes/models/units/`），场景按物体名找网格、按顺序挂材质、按图像名找导入时拆出的贴图。插件导出时会写成游戏现用的名字（房屋物体 `<类型>_export`、贴图 `<类型>_atlas`；兵种骨架 `inf_rig` / `cavalry_rig` / `courier_rig`、网格 `<兵种>`、贴图 `<兵种>_atlas` `_atlas_n` `_atlas_mr`，记在 `specs.json`，由 `glb_names.py` 从游戏现用的 GLB 读出），并读回文件核对，所以已有模型的新版本直接覆盖 GLB 即可，场景自动跟上；新类型才要在编辑器里新建继承场景、设材质、选进 `house_models.tres` / `army_models.tres`。新类型的 `.glb.import` 要带 `meshes/force_disable_compression=true` 和 `gltf/embedded_image_handling=1`（拆出贴图），兵种的循环动作在 `.import` 里设 loop；房屋尺寸写回 `data/map3d_houses.csv`（插件报告里有量好的宽、深、高），兵种的 `stride_m` 写进 `data/army_art.csv`；然后 `tools/map3d/build_pack.sh`，在开局缩放和最近缩放各截一张图。
