extends BodTestSuite
## Network resilience: initial timeout/retry, mid-match grace, and a real
## drop-and-rejoin over the WebSocket transport.

const NET_SCRIPT := preload("res://scripts/networking/network_manager.gd")

var _nets: Array[Node] = []


func after_test() -> void:
	for net in _nets:
		if is_instance_valid(net):
			net.stop()
			net.queue_free()
	_nets.clear()


func test_initial_connect_retries_then_fails_cleanly() -> void:
	var net := _new_net()
	var failures: Array = []
	net.connection_failed.connect(func() -> void: failures.append(true))
	var port := _free_port()
	expect(net.start_client("127.0.0.1", port) == OK, "socket attempt starts")
	# Advance past the whole initial budget: the manager must leave CLIENT.
	net._client_started_msec = Time.get_ticks_msec() - 7000
	await get_tree().process_frame
	await get_tree().process_frame
	expect(net.mode == net.Mode.OFFLINE, "exhausted initial budget falls back to offline")
	expect(net.last_error.contains("connection"), "offline state carries a clear reason")
	expect(failures.size() == 1, "failure is reported exactly once")
	expect(not net.is_reconnecting(), "initial failure is not left retrying forever")


func test_retry_backoff_is_bounded_and_explicit() -> void:
	var net := _new_net()
	var port := _free_port()
	expect(net.start_client("127.0.0.1", port) == OK, "socket attempt starts")
	var started := Time.get_ticks_msec()
	net._schedule_retry("connection refused — check host and port")
	expect(net.retry_attempt() == 1, "first retry is attempt 1")
	expect(net.mode == net.Mode.CLIENT, "retrying keeps the client state")
	var first_delay: int = int(net._next_retry_msec) - started
	net._schedule_retry("connection refused — check host and port")
	expect(net.retry_attempt() == 2, "second retry increments the attempt")
	var second_delay: int = int(net._next_retry_msec) - Time.get_ticks_msec()
	expect(second_delay > first_delay, "backoff grows between attempts")
	# Budget exhaustion is the only path to OFFLINE and must set last_error.
	net._client_started_msec = Time.get_ticks_msec() - 7000
	net._schedule_retry("connection timed out")
	expect(net.mode == net.Mode.OFFLINE, "retry budget exhaustion returns offline")
	expect(net.last_error.contains("timed out"), "timeout reason survives stop()")


func test_dropped_socket_gets_grace_before_failure() -> void:
	var net := _new_net()
	var failures: Array = []
	net.connection_failed.connect(func() -> void: failures.append(true))
	# Simulate a joined client losing its socket.
	net.mode = net.Mode.CLIENT
	net._had_connection = true
	net._join_name = "Alice"
	net._on_peer_disconnected(1)
	expect(net.mode == net.Mode.CLIENT, "a drop stays CLIENT during the grace window")
	expect(net.is_reconnecting(), "the UI can show reconnecting…")
	expect(net.last_error == "", "grace window is not a hard error yet")
	expect(net.reconnect_remaining_msec() > 0, "grace countdown is visible")
	expect(net.retry_attempt() == 1, "drop schedules the first retry")
	# Force the grace deadline past, then let the next drop decision run.
	net._grace_deadline_msec = Time.get_ticks_msec() - 1
	net._schedule_retry("connection lost")
	expect(net.mode == net.Mode.OFFLINE, "grace exhaustion falls back to offline")
	expect(net.last_error.contains("reconnect timed out"), "grace failure names the timeout")
	expect(failures.size() == 1, "grace failure is reported to the UI")


func test_real_drop_reconnects_and_rejoins() -> void:
	var port := _free_port()
	var server := _new_net()
	var client := _new_net()
	expect(server.start_server(port) == OK, "server listens on an ephemeral port")
	var joins: Array = []
	server.peer_joined.connect(func(peer_id: int, player_name: String, _class_id: int) -> void:
		joins.append({"peer": peer_id, "name": player_name}))

	expect(client.start_client("127.0.0.1", port) == OK, "client connects")
	await wait_for(func() -> bool: return client.connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 300)
	expect(client.retry_attempt() == 0, "healthy connection has no retries")
	client.send_join_request("Rejoin")
	await wait_for(func() -> bool: return joins.size() == 1, 300)
	expect(joins.size() == 1, "first join reaches the server")
	expect(String(joins[0]["name"]) == "Rejoin", "join carries the callsign")

	# Kill the server side of the socket and confirm the client enters grace.
	server.stop()
	await wait_for(func() -> bool: return client.is_reconnecting(), 300)
	expect(client.is_reconnecting(), "client notices the dropped socket")
	expect(client.mode == client.Mode.CLIENT, "client is not silently offline")

	# Bring the authority back on the same port inside the grace window.
	await get_tree().create_timer(0.2).timeout
	expect(server.start_server(port) == OK, "server restarts on the same port")
	await wait_for(func() -> bool: return joins.size() >= 2, 600)
	expect(joins.size() >= 2, "client reconnects and automatically re-sends JOIN_REQ")
	expect(String(joins[1]["name"]) == "Rejoin", "rejoin keeps the callsign")
	expect(not client.is_reconnecting(), "reconnecting flag clears after success")


func _new_net() -> Node:
	var net := NET_SCRIPT.new()
	add_child(net)
	_nets.append(net)
	return net


## Bind port 0, read the assigned port, then release it. The tiny race is fine
## for local tests and avoids clashing with other worktrees/live servers.
func _free_port() -> int:
	var probe := TCPServer.new()
	var err := probe.listen(0, "127.0.0.1")
	expect(err == OK, "ephemeral port probe binds")
	var port := probe.get_local_port()
	probe.stop()
	return port
