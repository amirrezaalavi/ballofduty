extends Node
## CP4a transport: raw binary packets over WebSocketMultiplayerPeer, polled
## manually every frame (never bound to the SceneTree MultiplayerAPI, so no
## engine handshake packets pollute the wire). One instance is the autoload;
## GameManager owns everything above the packet layer.
##
## Simulated latency (--sim-latency MS --sim-jitter MS) delays outbound packets
## through a deliver-at queue, in both directions, for honest local testing.

signal server_started(port: int)
signal server_stopped
signal connected_to_server
signal disconnected_from_server
signal join_accepted(player_id: int, spawn: Dictionary)
signal join_denied(reason: int)
signal roster_updated(entries: Array)
signal snapshot_received(tick: int, entries: Array)
signal event_received(event: Dictionary)
signal remote_input(peer_id: int, frame: Dictionary)
signal peer_joined(peer_id: int, player_name: String, class_id: int)
signal peer_left(peer_id: int)
signal ping_updated(rtt_ms: int)
signal connection_failed
## Emitted whenever a retry is scheduled. `delay_msec` is the backoff before
## the next socket attempt; `attempt` starts at 1 for the first retry.
signal reconnect_started(attempt: int, delay_msec: int)
## Emitted when a socket that had dropped is joined again.
signal reconnected

enum Mode { OFFLINE, SERVER, CLIENT }

const JOIN_TIMEOUT_SEC := 5.0
const PING_INTERVAL_TICKS := 30
const MAX_DRAIN_PER_FRAME := 64
## Total time an initial connection may spend retrying before the UI gets a
## hard failure. Keeping this at 6 s preserves the Phase 0 timeout contract.
const CONNECT_BUDGET_MSEC := 6000
## One socket attempt is abandoned after this long, then retried with backoff.
const ATTEMPT_TIMEOUT_MSEC := 3000
const RETRY_BASE_DELAY_MSEC := 350
const RETRY_MAX_DELAY_MSEC := 2400
## After a socket drops mid-match we keep retrying for this window (showing
## "reconnecting…") before falling back to offline with a clear error.
const RECONNECT_GRACE_MSEC := 8000

var mode: Mode = Mode.OFFLINE
var latency_ms: int = 0
var jitter_ms: int = 0
## Optional WebSocket request path (for one-origin proxies, e.g. "/ws").
## Kept as a property so the frozen start_client(host, port) API still works.
var client_path: String = ""
## Force wss:// (the web build also auto-detects an https page).
var client_tls: bool = false

var snapshots_processed: int = 0
var snapshots_dropped: int = 0
var packets_rejected: int = 0
var last_snapshot_bytes: int = 0
var rtt_ms: int = -1
var server_tick_estimate: int = -1
## Last client-side failure reason. Kept after stop() so the UI can explain why
## the socket died; cleared by the next start_client().
var last_error: String = ""

var _peer: WebSocketMultiplayerPeer
var _delayed: Array = [] # {deliver_msec: int, target: int, bytes: PackedByteArray}
var _pending_joins: Dictionary = {} # peer_id -> connected msec
var _known_peers: Dictionary = {} # server-side peer_id -> true
var _ping_tick: int = 0
var _last_ping_sent_msec: int = 0
var _join_requested_msec: int = 0
var _client_started_msec: int = 0
var _intentional_stop: bool = false

# Client reconnect state.
var _client_host: String = ""
var _client_port: int = 0
var _client_path_cached: String = ""
var _client_tls_cached: bool = false
var _attempt_started_msec: int = 0
var _next_retry_msec: int = 0
var _retry_scheduled: bool = false
var _retry_attempt: int = 0
var _had_connection: bool = false
var _needs_rejoin: bool = false
var _join_name: String = ""
var _join_class: int = 0
var _grace_deadline_msec: int = 0
var _reconnecting: bool = false
var _closing_peer: bool = false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var latency_index := args.find("--sim-latency")
	if latency_index >= 0 and latency_index + 1 < args.size():
		latency_ms = maxi(0, int(args[latency_index + 1]))
	var jitter_index := args.find("--sim-jitter")
	if jitter_index >= 0 and jitter_index + 1 < args.size():
		jitter_ms = maxi(0, int(args[jitter_index + 1]))
	_read_web_sim_params()


func _read_web_sim_params() -> void:
	if not OS.has_feature("web"):
		return
	var bridge := Engine.get_singleton("JavaScriptBridge") if Engine.has_singleton("JavaScriptBridge") else null
	if bridge == null:
		return
	var query := str(bridge.eval("window.location.search", true))
	for part in query.trim_prefix("?").split("&"):
		if part.begins_with("sim="):
			var bits := part.trim_prefix("sim=").split(",")
			if bits.size() >= 1:
				latency_ms = maxi(0, int(bits[0]))
			if bits.size() >= 2:
				jitter_ms = maxi(0, int(bits[1]))


func is_online() -> bool:
	return mode != Mode.OFFLINE


func jitter_ticks() -> int:
	return 1 if jitter_ms > 0 else 0


# --- server ---------------------------------------------------------------

func start_server(port: int) -> int:
	stop()
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_server(port)
	if err != OK:
		push_error("NetworkManager: WebSocket server failed on port %d: %s" % [port, err])
		_peer = null
		return err
	mode = Mode.SERVER
	_known_peers.clear()
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	server_started.emit(port)
	return OK


func server_peer_ids() -> Array:
	if mode != Mode.SERVER:
		return []
	return _known_peers.keys()


func connection_status() -> int:
	if _peer == null:
		return MultiplayerPeer.CONNECTION_DISCONNECTED
	return _peer.get_connection_status()


func server_send(peer_id: int, pkt: PackedByteArray) -> void:
	_send_to(peer_id, pkt)


func server_broadcast(pkt: PackedByteArray) -> void:
	for pid in server_peer_ids():
		_send_to(pid, pkt)


func server_disconnect(peer_id: int) -> void:
	if mode == Mode.SERVER and _peer != null:
		_peer.disconnect_peer(peer_id)


# --- client ---------------------------------------------------------------

func start_client(host: String, port: int, path: String = "") -> int:
	stop()
	last_error = ""
	_client_host = host.strip_edges()
	_client_port = port
	_client_path_cached = path if path.strip_edges() != "" else client_path
	_client_tls_cached = client_tls or _web_page_is_secure()
	_client_started_msec = Time.get_ticks_msec()
	_attempt_started_msec = _client_started_msec
	_next_retry_msec = 0
	_retry_scheduled = false
	_retry_attempt = 0
	_had_connection = false
	_needs_rejoin = false
	_join_name = ""
	_grace_deadline_msec = 0
	_reconnecting = false
	return _open_client_socket()


## Build the exact URL the transport uses. One-origin proxy mode appends the
## request path (for example ws://host:8099/ws) while the legacy two-port path
## stays ws://host:port.
static func build_ws_url(host: String, port: int, path: String, secure: bool) -> String:
	var request_path := path.strip_edges()
	if request_path != "" and not request_path.begins_with("/"):
		request_path = "/" + request_path
	return "%s://%s:%d%s" % ["wss" if secure else "ws", host, port, request_path]


func client_url() -> String:
	if _client_host == "":
		return ""
	return build_ws_url(_client_host, _client_port, _client_path_cached, _client_tls_cached)


func is_reconnecting() -> bool:
	return mode == Mode.CLIENT and _reconnecting


func reconnect_remaining_msec() -> int:
	if not _reconnecting or _grace_deadline_msec == 0:
		return 0
	return maxi(0, _grace_deadline_msec - Time.get_ticks_msec())


func retry_attempt() -> int:
	return _retry_attempt


func _open_client_socket() -> int:
	if _client_host == "" or _client_port <= 0:
		last_error = "invalid host or port"
		return ERR_INVALID_PARAMETER
	_peer = WebSocketMultiplayerPeer.new()
	var url := build_ws_url(
		_client_host, _client_port, _client_path_cached, _client_tls_cached
	)
	var err := _peer.create_client(url)
	if err != OK:
		push_error("NetworkManager: WebSocket client failed for %s: %s" % [url, err])
		_peer = null
		last_error = "invalid host or port"
		return err
	mode = Mode.CLIENT
	_attempt_started_msec = Time.get_ticks_msec()
	_join_requested_msec = 0
	_pending_joins.clear()
	return OK


func _web_page_is_secure() -> bool:
	if not OS.has_feature("web"):
		return false
	var bridge := Engine.get_singleton("JavaScriptBridge") if Engine.has_singleton("JavaScriptBridge") else null
	if bridge == null:
		return false
	return str(bridge.eval("window.location.protocol", true)) == "https:"


func client_send(pkt: PackedByteArray) -> void:
	_send_to(1, pkt)


# --- shared ---------------------------------------------------------------

func stop() -> void:
	if _peer == null and mode == Mode.OFFLINE and not _retry_scheduled:
		return
	_intentional_stop = true
	if _peer != null:
		# close() logs "ready_state != STATE_OPEN" if the socket already dropped,
		# which happens on the peer that did not initiate the disconnect.
		if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			_peer.close()
	_peer = null
	_delayed.clear()
	_pending_joins.clear()
	_known_peers.clear()
	_join_requested_msec = 0
	_retry_scheduled = false
	_retry_attempt = 0
	_next_retry_msec = 0
	_had_connection = false
	_needs_rejoin = false
	_join_name = ""
	_grace_deadline_msec = 0
	_reconnecting = false
	_client_host = ""
	_client_port = 0
	_client_path_cached = ""
	mode = Mode.OFFLINE
	server_stopped.emit()
	disconnected_from_server.emit()
	_intentional_stop = false


func send_join_request(display_name: String, class_id: int = 0) -> void:
	if mode != Mode.CLIENT:
		return
	_join_name = display_name
	_join_class = NetProtocol.sanitize_class(class_id)
	_join_requested_msec = Time.get_ticks_msec()
	_pending_joins[1] = _join_requested_msec
	client_send(NetProtocol.encode_join_request(_join_name, _join_class))


func _on_peer_connected(peer_id: int) -> void:
	if mode == Mode.SERVER:
		_known_peers[peer_id] = true
		_pending_joins[peer_id] = Time.get_ticks_msec()
		print("BALL_OF_DUTY net connect peer=%d" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if mode == Mode.SERVER:
		print("BALL_OF_DUTY net disconnect peer=%d" % peer_id)
	_known_peers.erase(peer_id)
	_pending_joins.erase(peer_id)
	if mode == Mode.SERVER:
		peer_left.emit(peer_id)
	elif mode == Mode.CLIENT:
		if not _intentional_stop and not _closing_peer:
			_schedule_retry("connection lost")


func _process(_delta: float) -> void:
	if _peer != null:
		_peer.poll()
		_flush_delayed()
		_drain()
		_expire_pending_joins()
		_check_client_connection()
		_tick_ping()
	if mode == Mode.CLIENT and _peer == null and _retry_scheduled \
			and Time.get_ticks_msec() >= _next_retry_msec:
		_retry_scheduled = false
		if _open_client_socket() != OK:
			_schedule_retry("connection refused — check host and port")


## A WebSocket that never opens has no JOIN_REQ pending, so the existing join
## timeout cannot see it. Detect dead sockets here and retry with backoff inside
## a bounded budget. Only after that budget expires do we emit a hard failure
## and return to OFFLINE; a dropped mid-match socket gets a longer grace window.
func _check_client_connection() -> void:
	if mode != Mode.CLIENT or _peer == null:
		return
	var now := Time.get_ticks_msec()
	var status := _peer.get_connection_status()
	# Initial-connect budget applies while the socket is not yet open. This is
	# also the field the Phase 0 timeout test fast-forwards.
	if not _had_connection and now - _client_started_msec >= CONNECT_BUDGET_MSEC:
		_fail_connection(_failure_reason(status))
		return
	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		_retry_attempt = 0
		_grace_deadline_msec = 0
		_reconnecting = false
		last_error = ""
		if not _had_connection:
			_had_connection = true
			connected_to_server.emit()
		if _needs_rejoin:
			_needs_rejoin = false
			_join_requested_msec = Time.get_ticks_msec()
			_pending_joins[1] = _join_requested_msec
			client_send(NetProtocol.encode_join_request(_join_name, _join_class))
			reconnected.emit()
		return
	if _retry_scheduled:
		return
	if now - _attempt_started_msec > ATTEMPT_TIMEOUT_MSEC:
		_schedule_retry("connection lost" if _had_connection else _failure_reason(status))
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED \
			and now - _attempt_started_msec > 500:
		_schedule_retry(
			"connection lost" if _had_connection
			else "connection refused — check host and port"
		)


func _failure_reason(status: int) -> String:
	if status == MultiplayerPeer.CONNECTION_CONNECTING:
		return "connection timed out"
	return "connection refused — check host and port"


## Schedule another socket attempt. Initial connects share a 6 s budget; a
## dropped mid-match socket gets an 8 s grace window. Exhaustion is the only
## path to OFFLINE, and it always carries `last_error` for the menu banner.
func _schedule_retry(reason: String) -> void:
	if mode != Mode.CLIENT:
		return
	var now := Time.get_ticks_msec()
	if _had_connection:
		if _grace_deadline_msec == 0:
			_grace_deadline_msec = now + RECONNECT_GRACE_MSEC
		if now >= _grace_deadline_msec:
			_fail_connection("%s — reconnect timed out" % reason)
			return
	elif now - _client_started_msec >= CONNECT_BUDGET_MSEC:
		_fail_connection(reason)
		return
	_close_peer()
	_delayed.clear()
	_pending_joins.clear()
	_join_requested_msec = 0
	_retry_attempt += 1
	var shift := mini(_retry_attempt - 1, 4)
	var delay := mini(RETRY_BASE_DELAY_MSEC * (1 << shift), RETRY_MAX_DELAY_MSEC)
	_next_retry_msec = now + delay
	_retry_scheduled = true
	if _had_connection:
		_needs_rejoin = _join_name != ""
		_reconnecting = true
	reconnect_started.emit(_retry_attempt, delay)


func _close_peer() -> void:
	if _peer == null:
		return
	var peer := _peer
	_peer = null
	_closing_peer = true
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		peer.close()
	_closing_peer = false


func _fail_connection(reason: String) -> void:
	last_error = reason
	_retry_scheduled = false
	_reconnecting = false
	_retry_attempt = 0
	connection_failed.emit()
	stop()


func _send_to(target: int, pkt: PackedByteArray) -> void:
	if _peer == null or pkt.is_empty():
		return
	if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if mode == Mode.SERVER and not _known_peers.has(target):
		return
	if latency_ms <= 0 and jitter_ms <= 0:
		_peer.set_target_peer(target)
		_peer.put_packet(pkt)
		return
	var delay := float(latency_ms)
	if jitter_ms > 0:
		delay += randf_range(-float(jitter_ms), float(jitter_ms))
	_delayed.append({
		"deliver_msec": Time.get_ticks_msec() + int(maxf(0.0, delay)),
		"target": target,
		"bytes": pkt,
	})


func _flush_delayed() -> void:
	if _delayed.is_empty():
		return
	var now := Time.get_ticks_msec()
	var kept: Array = []
	var connected := _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	for item in _delayed:
		if int(item["deliver_msec"]) <= now and connected and _peer != null:
			var target := int(item["target"])
			if mode != Mode.SERVER or _known_peers.has(target):
				_peer.set_target_peer(target)
				_peer.put_packet(item["bytes"])
		else:
			kept.append(item)
	_delayed = kept


func _drain() -> void:
	var drained := 0
	while _peer.get_available_packet_count() > 0:
		if drained >= MAX_DRAIN_PER_FRAME:
			packets_rejected += 1
			break
		drained += 1
		var sender := _peer.get_packet_peer()
		var pkt := _peer.get_packet()
		if pkt.size() > NetProtocol.MAX_PACKET_BYTES:
			packets_rejected += 1
			continue
		_route(sender, pkt)


func _route(sender: int, pkt: PackedByteArray) -> void:
	var msg := NetProtocol.msg_type(pkt)
	if mode == Mode.SERVER:
		_route_server(sender, msg, pkt)
	elif mode == Mode.CLIENT:
		_route_client(msg, pkt)


func _route_server(sender: int, msg: int, pkt: PackedByteArray) -> void:
	match msg:
		NetProtocol.Msg.JOIN_REQ:
			var req := NetProtocol.decode_join_request(pkt)
			if req.is_empty():
				packets_rejected += 1
				return
			_pending_joins.erase(sender)
			peer_joined.emit(sender, req["name"], int(req.get("class_id", 0)))
		NetProtocol.Msg.INPUT:
			var frame := NetProtocol.decode_input(pkt)
			if frame.is_empty():
				packets_rejected += 1
				return
			remote_input.emit(sender, frame)
		NetProtocol.Msg.PING:
			var ping := NetProtocol.decode_ping(pkt)
			if ping.is_empty():
				packets_rejected += 1
				return
			_send_to(sender, NetProtocol.encode_pong(int(ping["client_msec"]), Engine.get_physics_frames()))
		NetProtocol.Msg.LEAVE:
			peer_left.emit(sender)
		_:
			packets_rejected += 1


func _route_client(msg: int, pkt: PackedByteArray) -> void:
	match msg:
		NetProtocol.Msg.JOIN_OK:
			var ok := NetProtocol.decode_join_ok(pkt)
			if ok.is_empty():
				packets_rejected += 1
				return
			_pending_joins.erase(1)
			last_error = ""
			_reconnecting = false
			_grace_deadline_msec = 0
			join_accepted.emit(int(ok["id"]), {
				"pos": ok["spawn"], "yaw": float(ok["yaw"]),
				"tick": int(ok["tick"]), "class_id": int(ok["class_id"]),
			})
		NetProtocol.Msg.DENY:
			join_denied.emit(pkt[1] if pkt.size() > 1 else -1)
		NetProtocol.Msg.ROSTER:
			var roster := NetProtocol.decode_roster(pkt)
			if roster.is_empty():
				packets_rejected += 1
				return
			roster_updated.emit(roster["entries"])
		NetProtocol.Msg.SNAPSHOT:
			var snap := NetProtocol.decode_snapshot(pkt)
			if snap.is_empty():
				snapshots_dropped += 1
				return
			snapshots_processed += 1
			last_snapshot_bytes = pkt.size()
			snapshot_received.emit(int(snap["tick"]), snap["entries"])
		NetProtocol.Msg.EVENT:
			var event := NetProtocol.decode_event(pkt)
			if event.is_empty():
				packets_rejected += 1
				return
			event_received.emit(event)
		NetProtocol.Msg.PONG:
			var pong := NetProtocol.decode_pong(pkt)
			if pong.is_empty():
				packets_rejected += 1
				return
			rtt_ms = Time.get_ticks_msec() - int(pong["client_msec"])
			var ticks_elapsed := int(roundf(float(maxi(rtt_ms, 0)) / 1000.0 * 30.0))
			server_tick_estimate = int(pong["server_tick"]) + ticks_elapsed / 2
			ping_updated.emit(rtt_ms)
		_:
			packets_rejected += 1


func _expire_pending_joins() -> void:
	if mode == Mode.OFFLINE or _pending_joins.is_empty():
		return
	var now := Time.get_ticks_msec()
	var stale: Array = []
	for pid in _pending_joins:
		if now - int(_pending_joins[pid]) > int(JOIN_TIMEOUT_SEC * 1000.0):
			stale.append(pid)
	for pid in stale:
		_pending_joins.erase(pid)
		if mode == Mode.SERVER:
			server_disconnect(pid)
		elif mode == Mode.CLIENT:
			_schedule_retry("join timed out — server did not accept the join")


func _tick_ping() -> void:
	if mode != Mode.CLIENT:
		return
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_ping_tick += 1
	if _ping_tick % PING_INTERVAL_TICKS != 0:
		return
	_last_ping_sent_msec = Time.get_ticks_msec()
	_send_to(1, NetProtocol.encode_ping(_last_ping_sent_msec))
