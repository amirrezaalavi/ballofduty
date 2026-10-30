# Deployment (planned, CP5)

Single origin: static Godot web build + `wss://host/ws` reverse-proxied to the headless server.
Single-threaded export means no COOP/COEP headers are required.

## Caddy

```caddy
arena.example.com {
    root * /var/www/ballofduty
    encode zstd gzip

    @immutable path *.wasm *.pck *.data
    header @immutable {
        Cache-Control "public, max-age=31536000, immutable"
        Content-Type application/wasm
    }

    @entry path *.html *.json
    header @entry Cache-Control "no-cache, no-store, must-revalidate"

    @websocket {
        path /ws
        header Connection *Upgrade*
        header Upgrade websocket
    }
    reverse_proxy @websocket 127.0.0.1:9180

    file_server {
        precompressed br gzip
    }
}
```

## Notes

- `WebSocketMultiplayerPeer.create_client("wss://host/ws")` accepts a subpath; Caddy upgrades each
  browser connection independently, so Godot still sees one peer per client.
- Pre-compress `.wasm`, `.pck`, `.js` with Brotli and gzip; Caddy serves them from `file_server`.
- 30 Hz traffic keeps the socket active; only lobby/loading screens need a heartbeat or a longer
  proxy read timeout.
- Client URL should derive `ws(s)://<location.host>/ws` so dev, staging and production need no
  rebuild. The current `?join=1` path still defaults to `<page host>:9180` for local testing.
- Not yet implemented; this file records the CP5 target configuration.
