#!/usr/bin/env python3
"""One-origin static + WebSocket proxy for the exported Ball of Duty web build.

    python3 tools/serve.py --root build/web --port 8099 \
        --upstream 127.0.0.1:9180 --ws-path /ws

Only the web port has to be exposed. Static files come from --root; a WebSocket
upgrade on --ws-path is tunnelled byte-for-byte to the Godot server, so the
browser's origin, handshake, and frames all stay intact.

The served index.html is patched with:

    window.__BOD_PROXY_WS__ = "/ws";

main.gd reads that flag and joins via the page origin/path instead of opening a
second direct ws://host:port connection. Any other static server leaves the flag
unset, so the legacy two-port mode keeps working.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import mimetypes
import os
import posixpath
import sys
import urllib.parse
from pathlib import Path

MAX_HEAD_BYTES = 64 * 1024
BUFFER_BYTES = 64 * 1024

MIME_OVERRIDES = {
    ".html": "text/html; charset=utf-8",
    ".htm": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".data": "application/octet-stream",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".ico": "image/x-icon",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".ttf": "font/ttf",
}


def log(message: str) -> None:
    print(f"serve: {message}", flush=True)


def parse_upstream(value: str) -> tuple[str, int]:
    host, sep, port = value.rpartition(":")
    if not sep or not host:
        raise argparse.ArgumentTypeError("--upstream must be host:port")
    try:
        return host, int(port)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("--upstream port must be an integer") from exc


def content_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix in MIME_OVERRIDES:
        return MIME_OVERRIDES[suffix]
    guessed, _ = mimetypes.guess_type(path.name)
    return guessed or "application/octet-stream"


def proxy_injection(ws_path: str) -> bytes:
    payload = json.dumps(ws_path)
    return (
        f'<script>window.__BOD_PROXY_WS__={payload};'
        "window.__BOD_PROXY_UPSTREAM__=true;</script>"
    ).encode("utf-8")


def inject_proxy_flag(body: bytes, ws_path: str) -> bytes:
    marker = b"<!-- BOD_PROXY_INJECT -->"
    script = proxy_injection(ws_path)
    if marker in body:
        return body.replace(marker, script, 1)
    if b"</head>" in body:
        return body.replace(b"</head>", script + b"</head>", 1)
    return body


async def read_header_block(reader: asyncio.StreamReader) -> tuple[bytes, bytes]:
    """Read one HTTP header block and any bytes already buffered after it."""
    buf = bytearray()
    while b"\r\n\r\n" not in buf:
        chunk = await reader.read(4096)
        if not chunk:
            break
        buf.extend(chunk)
        if len(buf) > MAX_HEAD_BYTES:
            raise ValueError("HTTP header block too large")
    head, separator, rest = bytes(buf).partition(b"\r\n\r\n")
    if not separator:
        return b"", b""
    return head + b"\r\n\r\n", rest


def parse_request(head: bytes) -> tuple[str, str, dict[str, str], str]:
    text = head.decode("latin-1", errors="replace")
    lines = text.split("\r\n")
    if not lines or not lines[0]:
        return "", "", {}, ""
    parts = lines[0].split(" ")
    if len(parts) < 3:
        return "", "", {}, ""
    method, target, version = parts[0], parts[1], parts[2]
    headers: dict[str, str] = {}
    for line in lines[1:]:
        name, sep, value = line.partition(":")
        if sep:
            headers[name.strip().lower()] = value.strip()
    return method.upper(), target, headers, version


def is_websocket_upgrade(headers: dict[str, str]) -> bool:
    return (
        headers.get("upgrade", "").lower() == "websocket"
        and "upgrade" in headers.get("connection", "").lower()
    )


def safe_path(root: Path, raw_target: str) -> Path | None:
    target = urllib.parse.unquote(raw_target.split("?", 1)[0])
    if not target.startswith("/"):
        return None
    normalized = posixpath.normpath(target)
    if normalized in (".", "/"):
        normalized = "/index.html"
    if normalized.startswith("/..") or "/../" in normalized or normalized == "..":
        return None
    relative = normalized.lstrip("/")
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        return None
    return candidate


async def send_response(
    writer: asyncio.StreamWriter,
    status: str,
    headers: dict[str, str],
    body: bytes,
    head_only: bool = False,
) -> None:
    lines = [f"HTTP/1.1 {status}"]
    headers = {"Connection": "close", "Content-Length": str(len(body)), **headers}
    for name, value in headers.items():
        lines.append(f"{name}: {value}")
    lines.append("")
    writer.write("\r\n".join(lines).encode("latin-1") + b"\r\n")
    if not head_only and body:
        writer.write(body)
    await writer.drain()


async def serve_static(
    root: Path, ws_path: str, writer: asyncio.StreamWriter, method: str, target: str
) -> None:
    if method not in ("GET", "HEAD"):
        await send_response(writer, "405 Method Not Allowed", {"Allow": "GET, HEAD"}, b"")
        return
    path = safe_path(root, target)
    if path is None:
        await send_response(writer, "403 Forbidden", {"Content-Type": "text/plain"}, b"forbidden\n")
        return
    if path.is_dir():
        path = path / "index.html"
    if not path.is_file():
        await send_response(writer, "404 Not Found", {"Content-Type": "text/plain"}, b"not found\n")
        return
    try:
        body = path.read_bytes()
    except OSError:
        await send_response(writer, "500 Internal Server Error", {"Content-Type": "text/plain"}, b"read error\n")
        return
    if path.name in ("index.html", "index.htm"):
        body = inject_proxy_flag(body, ws_path)
    headers = {
        "Content-Type": content_type(path),
        "Cache-Control": "no-store" if path.suffix.lower() in (".html", ".htm") else "no-cache",
        "X-Content-Type-Options": "nosniff",
    }
    await send_response(writer, "200 OK", headers, body, head_only=(method == "HEAD"))


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while True:
            data = await reader.read(BUFFER_BYTES)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        try:
            await writer.drain()
        except (ConnectionError, RuntimeError):
            pass
        try:
            writer.close()
        except (ConnectionError, RuntimeError):
            pass


async def proxy_websocket(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    head: bytes,
    leftover: bytes,
    upstream_host: str,
    upstream_port: int,
) -> None:
    try:
        upstream_reader, upstream_writer = await asyncio.open_connection(
            upstream_host, upstream_port
        )
    except OSError as exc:
        log(f"websocket upstream {upstream_host}:{upstream_port} refused: {exc}")
        await send_response(writer, "502 Bad Gateway", {"Content-Type": "text/plain"}, b"upstream unavailable\n")
        writer.close()
        return

    try:
        upstream_writer.write(head)
        if leftover:
            upstream_writer.write(leftover)
        await upstream_writer.drain()
        response_head, response_rest = await read_header_block(upstream_reader)
        if not response_head:
            raise ConnectionError("upstream closed during websocket handshake")
        writer.write(response_head)
        if response_rest:
            writer.write(response_rest)
        await writer.drain()

        first_line = response_head.split(b"\r\n", 1)[0].decode("latin-1", errors="replace")
        if " 101 " not in f" {first_line} ":
            log(f"websocket upstream rejected handshake: {first_line}")
            writer.close()
            upstream_writer.close()
            return

        tasks = {
            asyncio.create_task(pipe(reader, upstream_writer)),
            asyncio.create_task(pipe(upstream_reader, writer)),
        }
        done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        for task in done:
            try:
                task.result()
            except (ConnectionError, asyncio.CancelledError):
                pass
    except (ConnectionError, OSError, ValueError) as exc:
        log(f"websocket tunnel closed: {exc}")
    finally:
        try:
            writer.close()
        except (ConnectionError, RuntimeError):
            pass
        try:
            upstream_writer.close()
        except (ConnectionError, RuntimeError):
            pass


async def handle_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    root: Path,
    ws_path: str,
    upstream: tuple[str, int] | None,
) -> None:
    peer = writer.get_extra_info("peername")
    try:
        head, leftover = await read_header_block(reader)
        if not head:
            return
        method, target, headers, _version = parse_request(head)
        if not method:
            await send_response(writer, "400 Bad Request", {"Content-Type": "text/plain"}, b"bad request\n")
            return
        path = urllib.parse.urlsplit(target).path
        if is_websocket_upgrade(headers) and path == ws_path:
            if upstream is None:
                await send_response(writer, "501 Not Implemented", {"Content-Type": "text/plain"}, b"websocket proxy disabled\n")
                return
            log(f"ws tunnel {peer} -> {upstream[0]}:{upstream[1]}{path}")
            await proxy_websocket(
                reader, writer, head, leftover, upstream[0], upstream[1]
            )
            return
        if is_websocket_upgrade(headers):
            await send_response(writer, "404 Not Found", {"Content-Type": "text/plain"}, b"unknown websocket path\n")
            return
        await serve_static(root, ws_path, writer, method, target)
    except (ConnectionError, asyncio.IncompleteReadError):
        pass
    except ValueError as exc:
        try:
            await send_response(writer, "400 Bad Request", {"Content-Type": "text/plain"}, str(exc).encode())
        except ConnectionError:
            pass
    finally:
        try:
            writer.close()
        except (ConnectionError, RuntimeError):
            pass


async def run(args: argparse.Namespace) -> None:
    root = Path(args.root).resolve()
    if not root.is_dir():
        raise SystemExit(f"serve: --root does not exist: {root}")
    upstream = None if args.no_proxy else parse_upstream(args.upstream)
    ws_path = args.ws_path if args.ws_path.startswith("/") else "/" + args.ws_path

    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, root, ws_path, upstream),
        host=args.bind,
        port=args.port,
        limit=MAX_HEAD_BYTES,
    )
    sockets = server.sockets or []
    bound_port = sockets[0].getsockname()[1] if sockets else args.port
    log(f"static root {root}")
    log(f"listening on http://{args.bind}:{bound_port}/")
    if upstream:
        log(f"websocket {ws_path} -> ws://{upstream[0]}:{upstream[1]}{ws_path}")
    else:
        log("websocket proxy disabled (--no-proxy)")
    async with server:
        await server.serve_forever()


def main() -> int:
    parser = argparse.ArgumentParser(description="Serve build/web and tunnel /ws to the game server")
    parser.add_argument("--root", default="build/web", help="static build directory")
    parser.add_argument("--bind", default="127.0.0.1", help="listen address")
    parser.add_argument("--port", type=int, default=8099, help="listen port (0 = ephemeral)")
    parser.add_argument("--upstream", default="127.0.0.1:9180", help="game server host:port")
    parser.add_argument("--ws-path", default="/ws", help="WebSocket upgrade path")
    parser.add_argument("--no-proxy", action="store_true", help="serve static files only")
    args = parser.parse_args()
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
