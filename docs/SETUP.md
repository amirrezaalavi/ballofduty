# Local setup (Linux)

Pinned engine: **Godot 4.7.2-stable**, standard (non-.NET) build.

The workspace install used here is local to the user (no sudo):

```bash
mkdir -p /srv/opencode/pkg/godot-4.7.2
cd /srv/opencode/pkg/godot-4.7.2
curl -fLO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip Godot_v4.7.2-stable_linux.x86_64.zip
chmod +x Godot_v4.7.2-stable_linux.x86_64

# export templates (1.3 GB download)
curl -fLO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
mkdir -p ~/.local/share/godot/export_templates/4.7.2.stable
unzip -q Godot_v4.7.2-stable_export_templates.tpz
mv templates/* ~/.local/share/godot/export_templates/4.7.2.stable/
rmdir templates
```

Repo commands use `tools/godot`, which defaults to the path above. Override with
`GODOT_BIN=/path/to/godot` on any machine.

Verify:

```bash
tools/godot --version                     # 4.7.2.stable.official...
tools/check.sh                            # full pipeline
tools/check.sh --skip-export              # imports + headless boots + tests
tools/serve.sh                            # serve build/web on :8099
```

## Web export notes (Godot 4.7, Compatibility)

- `variant/thread_support=false` → no COOP/COEP headers needed on the host.
- Custom shell at `web/index.html`; Godot replaces the `$GODOT_*` placeholders at export time.
- Serve `index.wasm` as `application/wasm`, and pre-compress `.wasm`, `.pck`, `.js` with Brotli/gzip.
- Production uses WSS behind Caddy/Nginx on the same origin as the static build.
