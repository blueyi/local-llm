# Hermes mflux image-gen plugin (backup)

源文件真身：`~/.hermes/plugins/image_gen/mflux/`（Hermes user plugin，kind=backend）。
此处为版本化备份。恢复：

```bash
mkdir -p ~/.hermes/plugins/image_gen/mflux
cp plugin.yaml __init__.py ~/.hermes/plugins/image_gen/mflux/
# config.yaml: plugins.enabled += image_gen/mflux; image_gen.provider: mflux; image_gen.model: flux2-klein-4b
```

