# Hermes mflux image-gen plugin (backup)

The live copy lives at `~/.hermes/plugins/image_gen/mflux/` (Hermes user
plugin, kind=backend). This directory is the version-controlled backup.

Restore:

```bash
mkdir -p ~/.hermes/plugins/image_gen/mflux
cp plugin.yaml __init__.py ~/.hermes/plugins/image_gen/mflux/
# config.yaml: plugins.enabled += image_gen/mflux; image_gen.provider: mflux; image_gen.model: flux2-klein-4b
```
