extends BodTestSuite
## Browser QA Bug 1: the connect path must not let wall-clock retry timers close
## a WebSocket handshake that only advances when polled (1 FPS on software
## WebGL), and the extra polling must stay bounded per frame.

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

