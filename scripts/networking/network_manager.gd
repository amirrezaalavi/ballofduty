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
signal peer_joined(peer_id: int, player_name: String)
signal peer_left(peer_id: int)
signal ping_updated(rtt_ms: int)
signal connection_failed

enum Mode { OFFLINE, SERVER, CLIENT }

const JOIN_TIMEOUT_SEC := 5.0
const PING_INTERVAL_TICKS := 30
const MAX_DRAIN_PER_FRAME := 64

var mode: Mode = Mode.OFFLINE
var latency_ms: int = 0
var jitter_ms: int = 0

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

func start_client(host: String, port: int) -> int:
	stop()
	last_error = ""
	_peer = WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d" % [host, port]
	var err := _peer.create_client(url)
	if err != OK:
		push_error("NetworkManager: WebSocket client failed for %s: %s" % [url, err])
		_peer = null
		last_error = "invalid host or port"
		return err
	mode = Mode.CLIENT
	_join_requested_msec = 0
	_client_started_msec = Time.get_ticks_msec()
	return OK


func client_send(pkt: PackedByteArray) -> void:
	_send_to(1, pkt)


# --- shared ---------------------------------------------------------------

func stop() -> void:
	if _peer == null and mode == Mode.OFFLINE:
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
	mode = Mode.OFFLINE
	server_stopped.emit()
	disconnected_from_server.emit()
	_intentional_stop = false


func send_join_request(display_name: String) -> void:
	if mode != Mode.CLIENT:
		return
	_join_requested_msec = Time.get_ticks_msec()
	_pending_joins[1] = _join_requested_msec
	client_send(NetProtocol.encode_join_request(display_name))


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
		if not _intentional_stop:
			last_error = "connection lost"
		stop()


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	_flush_delayed()
	_drain()
	_expire_pending_joins()
	_check_client_connection()
	_tick_ping()


## A WebSocket that never opens has no JOIN_REQ pending, so the existing join
## timeout cannot see it. Detect the dead socket here instead of sitting in a
## cosmetic-only CLIENT state forever.
func _check_client_connection() -> void:
	if mode != Mode.CLIENT or _peer == null:
		return
	var elapsed := Time.get_ticks_msec() - _client_started_msec
	var status := _peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTING and elapsed > 6000:
		last_error = "connection timed out"
		connection_failed.emit()
		stop()
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED and elapsed > 500:
		last_error = "connection refused — check host and port"
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
			peer_joined.emit(sender, req["name"])
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
			join_accepted.emit(int(ok["id"]), {"pos": ok["spawn"], "yaw": float(ok["yaw"]), "tick": int(ok["tick"])})
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
			last_error = "join timed out"
			stop()


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
