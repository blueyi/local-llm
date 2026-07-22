# 运维与排障

## 日常

```bash
./scripts/status.sh          # 版本、已装模型、磁盘提示
./scripts/sync-registry.sh   # 刷新 models-registry 中 Ollama 列表
ollama ps                    # 当前已加载模型
```

卸载 Ollama 模型：`ollama rm <name>`，并更新 registry + changelog。

## 更新模型

1. `ollama pull <name>` 或 LM Studio 下载新量化
2. 更新 `docs/models-registry.md`
3. 若默认 Agent 模型变了：改 `docs/agent-integration.md`
4. 写 `docs/changelog.md`

## 磁盘

- 权重统一在 `~/models/`（ollama/ gguf/ image-gen/），**不要**放进本仓库；`~/.ollama/models` 是 symlink
- 三档齐备约 80–100 GB；用 `du -sh ~/models` 检查

## 故障排查

| 现象 | 检查 |
|------|------|
| &lt;25 tok/s 或卡顿 | 是否加载了第二个大模型；上下文是否过大；Ollama 是否够新（MLX） |
| Agent 连不上 | `ollama serve` / `curl :11434/api/tags`；Base URL 是否带 `/v1` |
| OOM / 换页狂转 | 卸模型；降低上下文；A 档不要与 VL 同开 |
| VL 很慢 | 确认 LM Studio 使用 MLX；减少图分辨率与张数 |

## 内存纪律（48GB）

- 只常驻一个大模型
- A 档运行时减少其它重应用
- 超长文档优先 RAG，不要硬塞 128K+
