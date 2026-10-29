extends BodTestSuite
## CP4a wire protocol: roundtrips, budgets, quantization, malformed rejection.

var _budget_bytes: int = 0


func test_join_request_is_sanitized() -> void:
	var join := NetProtocol.encode_join_request("  Alice_99!@#  ")
	var decoded := NetProtocol.decode_join_request(join)
	expect(decoded.get("name") == "Alice_99", "join request sanitizes the name (got '%s')" % decoded.get("name"))
	expect(NetProtocol.decode_join_request(PackedByteArray([1, 99])) == {}, "oversized name length rejected")
	expect(NetProtocol.decode_join_request(PackedByteArray([9, 0])) == {}, "wrong message id rejected")


func test_join_ok_carries_spawn() -> void:
	# Regression for the 22 m spawn mismatch: spawn pose must survive the wire.
	var join_ok := NetProtocol.decode_join_ok(
		NetProtocol.encode_join_ok(3, 4242, Vector3(22.0, 0.3, -15.556), -1.2)
	)
	expect(join_ok.get("id") == 3 and join_ok.get("tick") == 4242, "join ok id/tick roundtrip")
	var spawn: Vector3 = join_ok.get("spawn", Vector3.ZERO)
	expect(spawn.distance_to(Vector3(22.0, 0.3, -15.556)) < 0.005, "join ok spawn roundtrips within 5 mm")
	expect(absf(float(join_ok.get("yaw", 0.0)) - -1.2) < 0.001, "join ok yaw roundtrips")
	expect(NetProtocol.decode_join_ok(PackedByteArray([2, 1, 0, 0, 0, 0])) == {}, "truncated join ok rejected")


func test_roster_roundtrip() -> void:
	var empty := NetProtocol.decode_roster(NetProtocol.encode_roster([]))
	expect(empty.get("entries", [-1]).is_empty(), "empty roster roundtrips")
	var many: Array = []
	for i in 8:
		many.append({"id": i + 1, "name": "P%d" % i})
	var full := NetProtocol.decode_roster(NetProtocol.encode_roster(many))
	expect(full.get("entries", []).size() == 8, "8-player roster roundtrips")
	expect(NetProtocol.decode_roster(PackedByteArray([4, 9])) == {}, "roster over capacity rejected")


func test_input_quantization() -> void:
	var yaw_in := 1.234
	var pitch_in := -0.321
	var input := NetProtocol.decode_input(
		NetProtocol.encode_input(4242, Vector2(0.3, -0.9), true, false, true, yaw_in, pitch_in)
	)
	expect(input.get("seq") == 4242, "input seq survives u32 wrap range")
	var rmove: Vector2 = input.get("move")
	expect(rmove.distance_to(Vector2(0.3, -0.9)) < 0.01, "move quantization < 0.01")
	expect(input.get("jump") and not input.get("sprint") and input.get("scoped"), "input flags roundtrip")
	expect(absf(float(input.get("yaw")) - yaw_in) < 0.001, "yaw quantization < 1 mrad")
	expect(absf(float(input.get("pitch")) - pitch_in) < 0.001, "pitch quantization < 1 mrad")
	expect(NetProtocol.decode_input(PackedByteArray([5, 1, 2])) == {}, "truncated input rejected")


func test_snapshot_budget_and_rejection() -> void:
	var entries: Array = []
	for i in 8:
		entries.append({
			"id": i + 1, "pos": Vector3(-29.5 + i, 0.4, 12.25 - i * 3.0),
			"yaw": -PI + i * 0.8, "state": i % 4,
			"vel": Vector3(1.25 - i * 0.1, -2.5, 7.5),
			"on_floor": i % 2 == 0,
			"hp": 100 - i, "ack": 5000 + i,
		})
	var snap := NetProtocol.encode_snapshot(123456, entries)
	_budget_bytes = snap.size()
	print("  snapshot 8-player bytes=%d" % _budget_bytes)
	expect(_budget_bytes == 182, "8-player snapshot is %d B (expected 182 B)" % _budget_bytes)
	expect(_budget_bytes <= 300, "8-player snapshot within the 300 B budget")

	var back := NetProtocol.decode_snapshot(snap)
	expect(back.get("tick") == 123456, "snapshot tick roundtrips")
	var first: Dictionary = back.get("entries")[0]
	var rpos: Vector3 = first["pos"]
	var epos: Vector3 = entries[0]["pos"]
	expect(rpos.distance_to(epos) < 0.002, "position quantization < 2 mm")
	expect(absf(float(first["yaw"]) - wrapf(float(entries[0]["yaw"]), -PI, PI)) < 0.001, "snapshot yaw < 1 mrad")
	expect(first["state"] == 0 and first["hp"] == 100 and first["ack"] == 5000, "snapshot state/hp/ack roundtrip")
	var rvel: Vector3 = first["vel"]
	expect(rvel.distance_to(Vector3(1.25, -2.5, 7.5)) < 0.02, "velocity roundtrips within 2 cm/s")
	expect(first["on_floor"] == true, "on-floor flag roundtrips")
	expect(back.get("entries")[1]["on_floor"] == false, "airborne flag roundtrips")

	expect(NetProtocol.decode_snapshot(PackedByteArray([6, 1, 2, 3, 4, 9])) == {}, "truncated snapshot rejected")
	var tampered := snap.duplicate()
	tampered.append(0)
	expect(NetProtocol.decode_snapshot(tampered) == {}, "trailing-byte snapshot rejected")


func test_ping_pong_and_transport_cap() -> void:
	expect(NetProtocol.decode_ping(NetProtocol.encode_ping(999)) == {"client_msec": 999}, "ping roundtrips")
	var pong := NetProtocol.decode_pong(NetProtocol.encode_pong(999, 77))
	expect(pong == {"client_msec": 999, "server_tick": 77}, "pong roundtrips")
	expect(NetProtocol.MAX_PACKET_BYTES == 2048, "transport cap is 2048 B")
