extends BodTestSuite
## Protocol v2 version gate: a v1 JOIN_REQ must be refused at the door (no
## peer_joined, one rejected packet, pending join erased), while a
## current-version JOIN_REQ is accepted. No socket is opened.

const NET_SCRIPT := preload("res://scripts/networking/network_manager.gd")

var _net: Node
var _joined: Array = []


func after_test() -> void:
	if is_instance_valid(_net):
		_net.stop()
	_net = null
	_joined.clear()


func _on_peer_joined(peer_id: int, player_name: String, class_id: int) -> void:
	_joined.append({"peer_id": peer_id, "name": player_name, "class_id": class_id})


func test_server_rejects_stale_protocol_version() -> void:
	_net = NET_SCRIPT.new()
	add_child(_net)
	_net.mode = NET_SCRIPT.Mode.SERVER
	_net.peer_joined.connect(_on_peer_joined)

	# A v1 peer would misread the 18 B snapshot rows as v1's 22 B rows, so the
	# server must deny it before the roster ever sees the peer.
	_net._pending_joins[7] = Time.get_ticks_msec()
	var old_pkt := NetProtocol.encode_join_request("Old", 0, 1)
	_net._route_server(7, NetProtocol.msg_type(old_pkt), old_pkt)
	expect(_joined.is_empty(), "v1 join does not emit peer_joined")
	expect(_net.packets_rejected == 1,
		"v1 join counts as one rejected packet (got %d)" % _net.packets_rejected)
	expect(not _net._pending_joins.has(7), "v1 pending join is erased")

	var new_pkt := NetProtocol.encode_join_request("New", 0, NetProtocol.PROTOCOL_VERSION)
	_net._route_server(8, NetProtocol.msg_type(new_pkt), new_pkt)
	expect(_joined.size() == 1, "current-version join emits peer_joined once (got %d)" % _joined.size())
	expect(int(_joined[0]["peer_id"]) == 8, "peer_joined carries peer 8")
	expect(String(_joined[0]["name"]) == "New", "peer_joined carries the name")

	# The version-deny path schedules a 0.3 s disconnect; let it fire while the
	# node is alive so the callback cannot outlive this test.
	await get_tree().create_timer(0.4).timeout
