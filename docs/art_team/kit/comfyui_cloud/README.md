# Comfy Cloud 版锁定工作流

本地电脑跑不动 Qwen 时用这一套（owner 2026-10-01）。和 `../comfyui/` 的同名工作流只差一处：Qwen 的模型换成 Comfy Cloud 上的原版全精度 `qwen_image_2512_bf16.safetensors`（本地用的 Q6_K 就是从它量化来的；Cloud 没有 GGUF 加载器）。风格、画幅、负面词、尺寸、步数、种子都一样；Z-Image 的工作流完全相同。

**第一次用之前**：Qwen 的 8 步加速 LoRA 不在 Comfy Cloud 的公共模型库里，要导入到自己的 Cloud 账户一次——从 Hugging Face 的 `lightx2v/Qwen-Image-2512-Lightning` 导入 `Qwen-Image-2512-Lightning-8steps-V1.0-bf16.safetensors`，文件名不要改（Apache 2.0，可商用）。导入不了就告诉开发。

同一个种子在云端和本地出的图不会逐像素相同（量化不同），但风格一致；同一个资源的候选图请在同一边出完。
