# 本地文生图（image-gen）

方案 v2.2 新增能力：本地 text-to-image，与三档 LLM 互不冲突（用完即释放，不常驻内存）。

## 选型（2026-07-22）

| 角色 | 模型 | 引擎 | 磁盘 | 峰值内存 | 实测速度 |
|------|------|------|------|----------|----------|
| **主力** | FLUX.2 Klein 4B（mflux 4bit） | mflux (MLX) | 4.3GB | **7.96GB** | 768×768 ×4步 ≈ **3.2s**（首次含加载 ~7s） |
| 备选（写实向） | Z-Image-Turbo 6B（mflux 4bit） | mflux (MLX) | 5.5GB | **7.58GB** | 768×768 ×9步 ≈ **9.3s**（含加载 ~15s） |

- **为什么 FLUX.2 Klein 而不是 FLUX.1 Schnell**：Klein 是 2026-01 新一代，4B 比 Schnell 12B 小 3 倍、质量更好、原生支持编辑（flux2-edit）；外部推荐清单里的 FLUX.1 Schnell 已是 legacy（mflux 官方表格标注 "No (legacy)"）。
- **为什么 mflux 而不是 Draw Things**：Draw Things 需 App Store 交互安装（`mas` 要 sudo 密码）；mflux 是纯 CLI（MLX 原生，M 系优化），`uv tool install mflux` 即装，可脚本化、可被 Agent 调用。需要 GUI 时再装 Draw Things 不冲突。

## 安装（已完成，可复现）

```bash
uv tool install mflux        # 32 个 CLI 入口（mflux-generate-flux2 等）
```

权重（本机 huggingface.co 直连不通 → hf-mirror.com 下载到本地目录）：

```bash
# 存放地：~/Downloads/image-gen-models/（不在本仓库，遵守"权重不进仓库"规则）
~/Downloads/image-gen-models/FLUX.2-klein-4B-mflux-4bit/   # 4.3GB
~/Downloads/image-gen-models/Z-Image-Turbo-mflux-4bit/     # 5.9GB
```

重下（任一文件损坏时）：`scripts/pull-image-model.sh`（见下）。

## 出图

```bash
# 主力：FLUX.2 Klein 4B，4 步即可出好图
mflux-generate-flux2 \
  --model ~/Downloads/image-gen-models/FLUX.2-klein-4B-mflux-4bit \
  --base-model flux2-klein-4b \
  --prompt "A cute orange kitten wearing tiny glasses" \
  --width 768 --height 768 --steps 4 --seed 42 \
  --output ~/Pictures/gen/out.png

# 备选：Z-Image-Turbo（写实向，9 步）
mflux-generate-z-image-turbo \
  --model ~/Downloads/image-gen-models/Z-Image-Turbo-mflux-4bit \
  --prompt "..." --width 1024 --height 768 --steps 9 --output out.png

# 图生图/编辑（FLUX.2 原生支持）
mflux-generate-flux2-edit --model ~/Downloads/image-gen-models/FLUX.2-klein-4B-mflux-4bit \
  --base-model flux2-klein-4b --image-path in.png --prompt "make it watercolor" --output out.png
```

常用参数：`--steps 4`（Klein distilled 甜点）、`--quantize` 不需要（权重已 4bit）、`--low-ram`（与大 LLM 同驻时用）、`--metadata`（旁存生成参数 json）。

## 内存法则（48GB）

- FLUX.2 Klein 4B 峰值 ~8GB：**可与 main 档 LLM（23GB）同时运行**，合计 ~31GB，安全。
- 与 deep 档（29GB）同跑会顶到 37GB 上限 → 出图时加 `--low-ram` 或暂停 deep。
- 出图进程结束即释放内存，无常驻。

## 坑（实测记录，2026-07-22）

1. **mflux/huggingface_hub 走 `HF_ENDPOINT=https://hf-mirror.com` 会报 `FileMetadataError: Distant resource does not seem to be on huggingface.co`** —— hf-mirror 的重定向 URL 不匹配 hub 客户端的域名校验，`hf_hub_download`/`snapshot_download` 全挂。**解法**：不走 hub 客户端，直接 `curl -sL hf-mirror.com/<repo>/resolve/main/<file>` 逐文件下载到本地目录，然后 `--model <本地路径>`（mflux 原生支持本地路径）。
2. `mas install` 需要 sudo 密码，Agent 无人值守装不了 App Store 应用。
3. 模型目录必须保持 HF 仓库的子目录结构（`transformer/ text_encoder/ tokenizer/ vae/` + 各自 index.json），缺 tokenizer 会报 `Failed to download tokenizer files`。

## 观察名单

| 模型 | 理由 |
|------|------|
| FLUX.2 Klein 9B（4bit ~9GB） | 质量更高，速度换质量的升级路径 |
| Ideogram 4 9B | 排版/文字渲染特化（2026-06，mflux 已支持） |
| Draw Things (App Store) | 需要 GUI 交互调参时安装 |
