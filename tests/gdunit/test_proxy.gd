extends BodTestSuite
## tools/serve.py contract: static build + injected proxy flag, and a raw
## WebSocket handshake/tunnel to a fake upstream. All ports are ephemeral.

const ROOT := "user://proxy_test_root"
const NET_SCRIPT := preload("res://scripts/networking/network_manager.gd")

var _pids: Array[int] = []
var _servers: Array[TCPServer] = []
var _peers: Array[StreamPeerTCP] = []
var _nets: Array[Node] = []


func after_test() -> void:
	for net in _nets:
		if is_instance_valid(net):
			net.stop()
			net.queue_free()
	_nets.clear()
	for peer in _peers:
		if peer:
			peer.disconnect_from_host()
	_peers.clear()
	for server in _servers:
		if server:
			server.stop()
	_servers.clear()
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


func test_custom_shell_keeps_boot_and_proxy_hooks() -> void:
	var shell := FileAccess.get_file_as_string("res://web/shell.html")
	expect(shell.contains("$GODOT_URL"), "shell keeps the Godot loader placeholder")
	expect(shell.contains("$GODOT_CONFIG"), "shell keeps the engine config placeholder")
	expect(shell.contains("$GODOT_THREADS_ENABLED"), "shell keeps the thread feature placeholder")
	expect(shell.contains("id=\"status-progress-fill\""), "shell has a styled progress fill")
	expect(shell.contains("@keyframes orbit"), "shell has an animated boot sequence")
	expect(shell.contains("id=\"status-notice\""), "shell keeps the failure notice")
	expect(shell.contains("Click the canvas to capture the mouse"), "shell keeps the capture hint")
	expect(shell.contains("BOD_PROXY_INJECT"), "shell exposes the proxy injection marker")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	expect(
		presets.contains('html/custom_html_shell="res://web/shell.html"'),
		"web export uses the animated custom shell"
	)


func test_static_files_are_served_with_proxy_flag() -> void:
	var root := _write_root()
	var port := _free_port()
	var pid := _start_proxy(root, port, _free_port())
	_pids.append(pid)
	expect(pid > 0, "serve.py starts")
	expect(await _wait_for_port(port), "proxy listens on its ephemeral port")

	var index := await _http_get(port, "/")
	expect(int(index["status"]) == 200, "index.html is served (status %s)" % index["status"])
	expect(String(index["header"]).contains("Content-Type: text/html"), "index has an HTML content type")
	expect(String(index["body"]).contains("BALL OF DUTY static test"), "static body is intact")
	expect(
		String(index["body"]).contains('window.__BOD_PROXY_WS__="/ws"'),
		"proxy flag is injected for main.gd"
	)

	var asset := await _http_get(port, "/data.txt")
	expect(int(asset["status"]) == 200, "extra build files are served")
	expect(String(asset["body"]).contains("payload"), "asset body is intact")
	expect(
		not String(asset["body"]).contains("__BOD_PROXY_WS__"),
		"injection applies only to HTML shells"
	)

	var missing := await _http_get(port, "/nope.js")
	expect(int(missing["status"]) == 404, "unknown files return 404")
	var traversal := await _http_get(port, "/../etc/passwd")
	expect(int(traversal["status"]) == 403 or int(traversal["status"]) == 404,
		"path traversal is refused (%s)" % traversal["status"])


func test_websocket_handshake_uses_fake_upstream() -> void:
	var root := _write_root()
	var upstream := TCPServer.new()
	_servers.append(upstream)
	expect(upstream.listen(0, "127.0.0.1") == OK, "fake upstream binds")
	var upstream_port := upstream.get_local_port()
	var port := _free_port()
	_pids.append(_start_proxy(root, port, upstream_port))
	expect(await _wait_for_port(port), "proxy listens for the tunnel test")

	var client := await _connect_tcp(port)
	expect(client != null, "test client connects to the proxy")
	if client == null:
		return
	var request := (
		"GET /ws HTTP/1.1\r\n"
		+ "Host: 127.0.0.1:%d\r\n" % port
		+ "Upgrade: websocket\r\n"
		+ "Connection: Upgrade\r\n"
		+ "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
		+ "Sec-WebSocket-Version: 13\r\n\r\n"
	)
	client.put_data(request.to_utf8_buffer())

	var upstream_peer := await _accept(upstream)
	expect(upstream_peer != null, "proxy dials the fake upstream")
	if upstream_peer == null:
		return
	var forwarded := await _read_until_text(upstream_peer, "\r\n\r\n")
	expect(forwarded.get_string_from_utf8().contains("GET /ws HTTP/1.1"), "upgrade path is forwarded")
	expect(forwarded.get_string_from_utf8().contains("Upgrade: websocket"), "upgrade headers are forwarded")
	expect(
		forwarded.get_string_from_utf8().contains("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=="),
		"handshake key is not rewritten"
	)

	var accept := (
		"HTTP/1.1 101 Switching Protocols\r\n"
		+ "Upgrade: websocket\r\n"
		+ "Connection: Upgrade\r\n"
		+ "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"
	)
	upstream_peer.put_data(accept.to_utf8_buffer())
	var response := await _read_until_text(client, "\r\n\r\n")
	expect(response.get_string_from_utf8().contains("101 Switching Protocols"), "101 is relayed to the browser")

	# A raw frame must survive both directions byte-for-byte.
	var frame := PackedByteArray([0x81, 0x03, 0x61, 0x62, 0x63])
	client.put_data(frame)
	var framed := await _read_exact(upstream_peer, frame.size())
	expect(framed == frame, "client frame reaches the upstream unchanged")
	upstream_peer.put_data(framed)
	var echoed := await _read_exact(client, frame.size())
	expect(echoed == frame, "upstream frame reaches the client unchanged")


func test_real_godot_client_joins_through_one_origin_proxy() -> void:
	var root := _write_root()
	var upstream_port := _free_port()
	var proxy_port := _free_port()
	var server := NET_SCRIPT.new()
	add_child(server)
	_nets.append(server)
	expect(server.start_server(upstream_port) == OK, "real Godot authority starts")
	var joins: Array = []
	server.peer_joined.connect(func(_peer_id: int, player_name: String) -> void:
		joins.append(player_name))

	_pids.append(_start_proxy(root, proxy_port, upstream_port))
	expect(await _wait_for_port(proxy_port), "proxy listens in front of Godot")
	var client := NET_SCRIPT.new()
	add_child(client)
	_nets.append(client)
	client.client_path = "/ws"
	expect(client.start_client("127.0.0.1", proxy_port) == OK, "client starts with the proxy path")
	await wait_for(func() -> bool: return client.connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 300)
	expect(client.connection_status() == MultiplayerPeer.CONNECTION_CONNECTED,
		"WebSocket upgrade through the proxy reaches Godot")
	client.send_join_request("Proxy")
	await wait_for(func() -> bool: return joins.size() == 1, 300)
	expect(joins.size() == 1, "JOIN_REQ reaches the authority through one port")
	expect(String(joins[0]) == "Proxy", "callsign survives the tunnel")


func test_wrong_path_is_not_tunnelled() -> void:
	var root := _write_root()
	var upstream := TCPServer.new()
	_servers.append(upstream)
	expect(upstream.listen(0, "127.0.0.1") == OK, "fake upstream binds")
	var port := _free_port()
	_pids.append(_start_proxy(root, port, upstream.get_local_port()))
	expect(await _wait_for_port(port), "proxy listens")
	var client := await _connect_tcp(port)
	if client == null:
		expect(false, "test client connects")
		return
	client.put_data((
		"GET /not-ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n"
		+ "Connection: Upgrade\r\nSec-WebSocket-Key: abc\r\n"
		+ "Sec-WebSocket-Version: 13\r\n\r\n"
	).to_utf8_buffer())
	var raw := await _read_until_text(client, "\r\n\r\n")
	expect(raw.get_string_from_utf8().contains("404"), "upgrade on an unknown path gets 404")
	expect(not upstream.is_connection_available(), "unknown path never reaches upstream")


func _write_root() -> String:
	var root := ProjectSettings.globalize_path(ROOT)
	DirAccess.make_dir_recursive_absolute(root)
	var index := FileAccess.open(root.path_join("index.html"), FileAccess.WRITE)
	index.store_string(
		"<!DOCTYPE html><html><head><!-- BOD_PROXY_INJECT --></head>"
		+ "<body>BALL OF DUTY static test</body></html>"
	)
	index.close()
	var asset := FileAccess.open(root.path_join("data.txt"), FileAccess.WRITE)
	asset.store_string("payload")
	asset.close()
	return root


func _start_proxy(root: String, port: int, upstream_port: int) -> int:
	var script := ProjectSettings.globalize_path("res://tools/serve.py")
	return OS.create_process("python3", [
		script,
		"--root", root,
		"--bind", "127.0.0.1",
		"--port", str(port),
		"--upstream", "127.0.0.1:%d" % upstream_port,
		"--ws-path", "/ws",
	])


func _free_port() -> int:
	var probe := TCPServer.new()
	var err := probe.listen(0, "127.0.0.1")
	expect(err == OK, "ephemeral port probe binds")
	var port := probe.get_local_port()
	probe.stop()
	return port


func _wait_for_port(port: int, frames: int = 300) -> bool:
	for _i in frames:
		var peer := StreamPeerTCP.new()
		if peer.connect_to_host("127.0.0.1", port) == OK:
			peer.poll()
			var status := peer.get_status()
			peer.disconnect_from_host()
			if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
				return true
		await get_tree().process_frame
	return false


func _connect_tcp(port: int, frames: int = 300) -> StreamPeerTCP:
	for _i in frames:
		var peer := StreamPeerTCP.new()
		if peer.connect_to_host("127.0.0.1", port) == OK:
			for _j in 30:
				peer.poll()
				match peer.get_status():
					StreamPeerTCP.STATUS_CONNECTED:
						_peers.append(peer)
						return peer
					StreamPeerTCP.STATUS_ERROR:
						break
				await get_tree().process_frame
		await get_tree().process_frame
	return null


func _accept(server: TCPServer, frames: int = 300) -> StreamPeerTCP:
	for _i in frames:
		if server.is_connection_available():
			var peer := server.take_connection()
			if peer:
				_peers.append(peer)
				return peer
		await get_tree().process_frame
	return null


func _read_until_text(peer: StreamPeerTCP, needle: String, frames: int = 300) -> PackedByteArray:
	var buf := PackedByteArray()
	for _i in frames:
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk := peer.get_data(available)
			if int(chunk[0]) == OK:
				buf.append_array(chunk[1])
		if buf.get_string_from_utf8().contains(needle):
			return buf
		await get_tree().process_frame
	return buf


func _read_exact(peer: StreamPeerTCP, count: int, frames: int = 300) -> PackedByteArray:
	var buf := PackedByteArray()
	for _i in frames:
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk := peer.get_data(available)
			if int(chunk[0]) == OK:
				buf.append_array(chunk[1])
		if buf.size() >= count:
			return buf.slice(0, count)
		await get_tree().process_frame
	return buf


func _http_get(port: int, path: String) -> Dictionary:
	var peer := await _connect_tcp(port)
	if peer == null:
		return {"status": 0, "header": "", "body": ""}
	peer.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n" % [path, port]).to_utf8_buffer())
	var buf := PackedByteArray()
	for _i in 300:
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			var available := peer.get_available_bytes()
			if available > 0:
				var chunk := peer.get_data(available)
				if int(chunk[0]) == OK:
					buf.append_array(chunk[1])
		elif status != StreamPeerTCP.STATUS_CONNECTING:
			# Closed/errored: stop before asking an invalid socket for bytes.
			break
		var text := buf.get_string_from_utf8()
		var header_end := text.find("\r\n\r\n")
		if header_end >= 0:
			var header_text := text.substr(0, header_end)
			var length := _content_length(header_text)
			if length >= 0 and buf.size() >= header_end + 4 + length:
				break
		await get_tree().process_frame
	var raw := buf.get_string_from_utf8()
	var split := raw.find("\r\n\r\n")
	if split < 0:
		return {"status": 0, "header": raw, "body": ""}
	var header := raw.substr(0, split)
	var body := raw.substr(split + 4)
	var code := 0
	var parts := header.split(" ", false, 2)
	if parts.size() >= 2:
		code = int(parts[1])
	return {"status": code, "header": header, "body": body}


func _content_length(header: String) -> int:
	for line in header.split("\r\n"):
		var bits := line.split(":", true, 1)
		if bits.size() == 2 and bits[0].strip_edges().to_lower() == "content-length":
			return int(bits[1].strip_edges())
	return -1
