# 运行时栈

| 角色 | 工具 | 用途 |
|------|------|------|
| 主 | **Ollama 0.32.1**（Homebrew + MLX） | 编程 / Agent / OpenAI 兼容 API |
| 辅 | **LM Studio** | GUI、多模态；更新目标 **0.4.19-2** |
| 可选 | `mlx-lm` | 仅 LoRA / 脚本批处理 |

## 当前安装状态

| 组件 | 版本 | 备注 |
|------|------|------|
| Ollama | **0.32.1** | `brew services` 已启动 |
| MLX (brew) | 0.32.0 | Ollama 依赖 |
| LM Studio | **0.4.19+2** | 已从 0.4.2 升级；App 在 `/Applications` |
| 已装模型 | qwen3.6 35B Q4（新主力）+ coder Q8（退役待删） | 见 `models-registry.md` |

推荐环境变量：

```bash
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KV_CACHE_TYPE=q8_0
```

## API

- OpenAI 兼容：`http://127.0.0.1:11434/v1`
- 权重：`~/.ollama/`（约 93GB，含缓存/部分下载）
