extends BodTestSuite
## Browser QA Bug 1 + Bug 4: the connect path must not let wall-clock retry
## timers close a WebSocket handshake that only advances when polled (1 FPS on
## software WebGL), the join ack wait must scale with the frame rate, and RTT
## samples must not include the client's own stalls.

const NET_SCRIPT := preload("res://scripts/networking/network_manager.gd")

var _nets: Array[Node] = []
var _silent_server: TCPServer


func after_test() -> void:
	for net in _nets:
		if is_instance_valid(net):
			net.stop()
			net.queue_free()
	_nets.clear()
	if _silent_server != null:
		_silent_server.stop()
		_silent_server = null


func _new_net() -> Node:
	var net := NET_SCRIPT.new()
	add_child(net)
	_nets.append(net)
	return net


## Bind port 0, read the assigned port, then release it. Same tiny race as the
## other net suites: fine for local tests.
func _free_port() -> int:
	var probe := TCPServer.new()
	var err := probe.listen(0, "127.0.0.1")
	expect(err == OK, "ephemeral port probe binds")
	var port := probe.get_local_port()
	probe.stop()
	return port


## Accepts the TCP connection (kernel backlog) but never answers the WebSocket
## upgrade, so a real client stays CONNECTION_CONNECTING deterministically.
func _silent_tcp_server() -> int:
	_silent_server = TCPServer.new()
	var err := _silent_server.listen(0, "127.0.0.1")
	expect(err == OK, "silent TCP server binds")
	return _silent_server.get_local_port()


# --- Bug 1: handshake must survive the attempt timer ---------------------

func test_connecting_attempt_inside_the_window_is_kept() -> void:
	expect(
		not NET_SCRIPT.should_abandon_attempt(MultiplayerPeer.CONNECTION_CONNECTING, 0),
		"a fresh connecting attempt is kept"
	)
	expect(
		not NET_SCRIPT.should_abandon_attempt(
			MultiplayerPeer.CONNECTION_CONNECTING, NET_SCRIPT.ATTEMPT_TIMEOUT_MSEC),
		"a connecting attempt at the attempt timeout is still kept"
	)
	expect(
		not NET_SCRIPT.should_abandon_attempt(MultiplayerPeer.CONNECTION_CONNECTING, 60000),
		"a connecting attempt is never abandoned on the per-attempt timer"
	)


func test_connecting_peer_past_the_total_budget_is_abandoned() -> void:
	var net := _new_net()
	var failures: Array = []
	net.connection_failed.connect(func() -> void: failures.append(true))
	expect(net.start_client("127.0.0.1", _silent_tcp_server()) == OK, "client starts")
	await wait_for(
		func() -> bool: return net.connection_status() == MultiplayerPeer.CONNECTION_CONNECTING,
		300
	)
	expect(
		net.connection_status() == MultiplayerPeer.CONNECTION_CONNECTING,
		"TCP accepted, WebSocket upgrade still pending"
	)
	# The per-attempt timer alone must not close a handshake that is still
	# opening; this is the 1 FPS regression.
	net._attempt_started_msec = Time.get_ticks_msec() - 5000
	await get_tree().process_frame
	await get_tree().process_frame
	expect(net.mode == net.Mode.CLIENT, "a still-connecting handshake survives the attempt timer")
	expect(failures.is_empty(), "no failure while the handshake is progressing")
	# The total budget remains the hard stop.
	net._client_started_msec = Time.get_ticks_msec() - 7000
	await get_tree().process_frame
	await get_tree().process_frame
	expect(net.mode == net.Mode.OFFLINE, "the total budget abandons the attempt")
	expect(net.last_error.contains("timed out"), "budget failure reports a timeout")
	expect(failures.size() == 1, "budget failure is reported exactly once")


func test_disconnected_peer_is_retried() -> void:
	expect(
		not NET_SCRIPT.should_abandon_attempt(MultiplayerPeer.CONNECTION_DISCONNECTED, 10),
		"a just-refused socket gets its short grace"
	)
	expect(
		NET_SCRIPT.should_abandon_attempt(
			MultiplayerPeer.CONNECTION_DISCONNECTED,
			NET_SCRIPT.ATTEMPT_DISCONNECT_GRACE_MSEC + 1),
		"a disconnected socket is retried"
	)
	var net := _new_net()
	var retries: Array = []
	net.reconnect_started.connect(func(attempt: int, _delay: int) -> void: retries.append(attempt))
	expect(net.start_client("127.0.0.1", _free_port()) == OK, "client starts against a closed port")
	await wait_for(func() -> bool: return net.retry_attempt() >= 1, 300)
	expect(net.retry_attempt() >= 1, "a refused connection is retried")
	expect(not retries.is_empty(), "the retry is announced to the UI")


func test_connect_poll_budget_is_bounded() -> void:
	expect(
		NET_SCRIPT.CONNECT_POLLS_PER_FRAME > 1,
		"a connecting frame polls more than once"
	)
	expect(
		NET_SCRIPT.CONNECT_POLL_BUDGET_MSEC > 0 and NET_SCRIPT.CONNECT_POLL_BUDGET_MSEC <= 16,
		"the extra polling slice stays inside a 60 FPS frame"
	)
	expect(
		NET_SCRIPT.should_poll_again(MultiplayerPeer.CONNECTION_CONNECTING, 0, 0),
		"a connecting peer is polled again"
	)
	expect(
		not NET_SCRIPT.should_poll_again(
			MultiplayerPeer.CONNECTION_CONNECTING, NET_SCRIPT.CONNECT_POLLS_PER_FRAME, 0),
		"the poll count is capped"
	)
	expect(
		not NET_SCRIPT.should_poll_again(
			MultiplayerPeer.CONNECTION_CONNECTING, 1, NET_SCRIPT.CONNECT_POLL_BUDGET_MSEC),
		"the per-frame time slice is capped"
	)
	expect(
		not NET_SCRIPT.should_poll_again(MultiplayerPeer.CONNECTION_CONNECTED, 0, 0),
		"an open peer is polled once per frame"
	)
	expect(
		not NET_SCRIPT.should_poll_again(MultiplayerPeer.CONNECTION_DISCONNECTED, 0, 0),
		"a dead peer is not polled again"
	)
	# Frozen clock: only the poll cap can stop the loop, so it cannot spin forever.
	var polls := 0
	while NET_SCRIPT.should_poll_again(MultiplayerPeer.CONNECTION_CONNECTING, polls, 0):
		polls += 1
		if polls > 1000:
			break
	expect(
		polls == NET_SCRIPT.CONNECT_POLLS_PER_FRAME,
		"the loop stops on the poll cap even if the clock never advances"
	)


# --- Bug 1 follow-up: the join-ack wait is frame-gated too ----------------

func test_client_join_deadline_extends_with_slow_frames() -> void:
	expect(
		NET_SCRIPT.join_deadline_msec(0) == 5000,
		"at full speed the join deadline is the 5 s baseline"
	)
	expect(
		NET_SCRIPT.join_deadline_msec(-5) == 5000,
		"a bogus frame gap never shortens the baseline"
	)
	expect(
		NET_SCRIPT.join_deadline_msec(1000) == 8000,
		"at 1 FPS the join gets three extra frames (8 s)"
	)
	var slow: int = NET_SCRIPT.join_deadline_msec(2000)
	expect(slow > 8000, "a 2 s frame buys even more join time (got %d ms)" % slow)
	expect(
		NET_SCRIPT.join_deadline_msec(100000) == NET_SCRIPT.JOIN_HARD_TIMEOUT_MSEC,
		"the join deadline never passes the hard ceiling"
	)


func test_client_join_pending_past_the_baseline_survives_a_slow_frame() -> void:
	var net := _new_net()
	net.mode = net.Mode.CLIENT
	net._client_started_msec = Time.get_ticks_msec()
	net._pending_joins[1] = Time.get_ticks_msec() - 6000
	net._frame_gap_msec = 2000
	net._expire_pending_joins()
	expect(net._pending_joins.has(1), "a 6 s join is kept after a 2 s frame")
	expect(net.retry_attempt() == 0, "no retry while the ack can still arrive")
	# Once frames are fast again the same age is a real timeout.
	net._frame_gap_msec = 16
	net._expire_pending_joins()
	expect(not net._pending_joins.has(1), "a 6 s join on fast frames is expired")
	expect(net.retry_attempt() == 1, "the client retries instead of hanging")


func test_client_join_past_the_hard_ceiling_expires_despite_slow_frames() -> void:
	var net := _new_net()
	net.mode = net.Mode.CLIENT
	net._client_started_msec = Time.get_ticks_msec()
	net._frame_gap_msec = 10000
	net._pending_joins[1] = (
		Time.get_ticks_msec() - (NET_SCRIPT.JOIN_HARD_TIMEOUT_MSEC + 1000)
	)
	net._expire_pending_joins()
	expect(not net._pending_joins.has(1), "the hard ceiling still expires a dead join")
	expect(net.retry_attempt() == 1, "the UI is told to retry")


func test_server_pending_join_expiry_is_unchanged() -> void:
	var net := _new_net()
	net.mode = net.Mode.SERVER
	# A huge client-style frame gap must not extend the server's slot deadline.
	net._frame_gap_msec = 10000
	net._pending_joins[7] = Time.get_ticks_msec() - 6000
	net._pending_joins[8] = Time.get_ticks_msec() - 1000
	net._expire_pending_joins()
	expect(not net._pending_joins.has(7), "a silent server peer is dropped after 5 s")
	expect(net._pending_joins.has(8), "a fresh server peer keeps its slot")


# --- Bug 4: RTT must not include the client's own frame stalls -----------

func test_sanitize_rtt_rejects_stalls_and_clamps() -> void:
	expect(NET_SCRIPT.sanitize_rtt(120, 16) == 120, "a prompt pong is a real sample")
	expect(
		NET_SCRIPT.sanitize_rtt(120, NET_SCRIPT.RTT_STALE_FRAME_GAP_MSEC - 1) == 120,
		"just under the frame-gap threshold is kept"
	)
	expect(
		NET_SCRIPT.sanitize_rtt(120, NET_SCRIPT.RTT_STALE_FRAME_GAP_MSEC) == -1,
		"a pong read after a long frame is not a sample"
	)
	expect(
		NET_SCRIPT.sanitize_rtt(99999, 16) == NET_SCRIPT.RTT_MAX_MSEC,
		"an absurd round trip is clamped"
	)
	expect(NET_SCRIPT.sanitize_rtt(-5, 16) == -1, "a negative sample is dropped")


func test_pong_after_frame_stall_keeps_last_good_rtt() -> void:
	var net := _new_net()
	net.mode = net.Mode.CLIENT
	net.rtt_ms = 42
	var pings: Array = []
	net.ping_updated.connect(func(rtt: int) -> void: pings.append(rtt))
	# A 1 s frame: the pong is seconds old by the time it is read.
	net._frame_gap_msec = 1000
	net._route_client(
		NetProtocol.Msg.PONG, NetProtocol.encode_pong(Time.get_ticks_msec() - 3000, 10))
	expect(net.rtt_ms == 42, "a stalled frame does not overwrite the RTT")
	expect(net.rtt_stale, "the sample is flagged stale")
	expect(not pings.is_empty() and int(pings[-1]) == 42, "the UI keeps the last good value")
	# A normal frame clears the flag and stores the fresh sample.
	net._frame_gap_msec = 16
	net._route_client(
		NetProtocol.Msg.PONG, NetProtocol.encode_pong(Time.get_ticks_msec() - 30, 10))
	expect(not net.rtt_stale, "a prompt sample clears the stale flag")
	expect(
		net.rtt_ms >= 0 and net.rtt_ms <= NET_SCRIPT.RTT_MAX_MSEC,
		"a prompt sample is stored and clamped"
	)
