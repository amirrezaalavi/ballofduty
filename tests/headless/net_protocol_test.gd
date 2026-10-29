extends SceneTree
## CP4a protocol checks: roundtrips, snapshot budget, quantization error,
## malformed/oversized rejection. Run with --script.

var _failures := 0
var _checks := 0


func _init() -> void:
	_run()


func _run() -> void:
	# Join request roundtrip + sanitization.
	var join := NetProtocol.encode_join_request("  Alice_99!@#  ")
	var decoded_join := NetProtocol.decode_join_request(join)
	_check(decoded_join.get("name") == "Alice_99", "join request roundtrips with sanitized name (got '%s')" % decoded_join.get("name"))
	_check(NetProtocol.decode_join_request(PackedByteArray([1, 99])) == {}, "oversized name length rejected")
	_check(NetProtocol.decode_join_request(PackedByteArray([9, 0])) == {}, "wrong message id rejected")

	# Join OK carries the authoritative spawn pose (fixes the 22 m mismatch).
	var join_ok := NetProtocol.decode_join_ok(
		NetProtocol.encode_join_ok(3, 4242, Vector3(22.0, 0.3, -15.556), -1.2)
	)
	_check(join_ok.get("id") == 3 and join_ok.get("tick") == 4242, "join ok id/tick roundtrip")
	var js: Vector3 = join_ok.get("spawn", Vector3.ZERO)
	_check(js.distance_to(Vector3(22.0, 0.3, -15.556)) < 0.005, "join ok spawn roundtrips within 5 mm")
	_check(absf(float(join_ok.get("yaw", 0.0)) - -1.2) < 0.001, "join ok yaw roundtrips")
	_check(NetProtocol.decode_join_ok(PackedByteArray([2, 1, 0, 0, 0, 0])) == {}, "truncated join ok rejected")

	# Roster roundtrip incl. empty and max-size.
	var empty := NetProtocol.decode_roster(NetProtocol.encode_roster([]))
	_check(empty.get("entries", [-1]).is_empty(), "empty roster roundtrips")
	var many: Array = []
	for i in 8:
		many.append({"id": i + 1, "name": "P%d" % i})
	var full := NetProtocol.decode_roster(NetProtocol.encode_roster(many))
	_check(full.get("entries", []).size() == 8, "8-player roster roundtrips")
	_check(NetProtocol.decode_roster(PackedByteArray([4, 9])) == {}, "roster over capacity rejected")

	# Input roundtrip + quantization error.
	var yaw_in := 1.234
	var pitch_in := -0.321
	var input := NetProtocol.decode_input(
		NetProtocol.encode_input(4242, Vector2(0.3, -0.9), true, false, true, yaw_in, pitch_in)
	)
	_check(input.get("seq") == 4242, "input seq survives u32 wrap range")
	var rmove: Vector2 = input.get("move")
	_check(rmove.distance_to(Vector2(0.3, -0.9)) < 0.01, "move quantization < 0.01")
	_check(input.get("jump") and not input.get("sprint") and input.get("scoped"), "input flags roundtrip")
	_check(absf(float(input.get("yaw")) - yaw_in) < 0.001, "yaw quantization < 1 mrad")
	_check(absf(float(input.get("pitch")) - pitch_in) < 0.001, "pitch quantization < 1 mrad")
	_check(NetProtocol.decode_input(PackedByteArray([5, 1, 2])) == {}, "truncated input rejected")

	# Snapshot roundtrip at 8 players + budget.
	var entries: Array = []
	for i in 8:
		entries.append({
			"id": i + 1, "pos": Vector3(-29.5 + i, 0.4, 12.25 - i * 3.0),
			"yaw": -PI + i * 0.8, "state": i % 4, "hp": 100 - i, "ack": 5000 + i,
		})
	var snap := NetProtocol.encode_snapshot(123456, entries)
	print("  snapshot 8-player bytes=%d" % snap.size())
	_check(snap.size() <= 300, "8-player snapshot is %d B (limit 300 B)" % snap.size())
	var back := NetProtocol.decode_snapshot(snap)
	_check(back.get("tick") == 123456, "snapshot tick roundtrips")
	var b0: Dictionary = back.get("entries")[0]
	var rpos: Vector3 = b0["pos"]
	var epos: Vector3 = entries[0]["pos"]
	_check(rpos.distance_to(epos) < 0.002, "position quantization < 2 mm")
	_check(absf(float(b0["yaw"]) - wrapf(float(entries[0]["yaw"]), -PI, PI)) < 0.001, "snapshot yaw < 1 mrad")
	_check(b0["state"] == 0 and b0["hp"] == 100 and b0["ack"] == 5000, "snapshot state/hp/ack roundtrip")
	_check(NetProtocol.decode_snapshot(PackedByteArray([6, 1, 2, 3, 4, 9])) == {}, "truncated snapshot rejected")
	_check(NetProtocol.decode_snapshot(PackedByteArray([6, 1, 2, 3, 4, 9])) == {}, "truncated snapshot rejected")
	var tampered := snap.duplicate()
	tampered.append(0)
	_check(NetProtocol.decode_snapshot(tampered) == {}, "trailing-byte snapshot rejected")

	# Ping/pong.
	_check(NetProtocol.decode_ping(NetProtocol.encode_ping(999)) == {"client_msec": 999}, "ping roundtrips")
	var pong := NetProtocol.decode_pong(NetProtocol.encode_pong(999, 77))
	_check(pong == {"client_msec": 999, "server_tick": 77}, "pong roundtrips")

	# Oversized guard constant vs transport cap.
	_check(NetProtocol.MAX_PACKET_BYTES == 2048, "transport cap is 2048 B")

	_finish()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)


func _finish() -> void:
	print("net_protocol: %d checks, %d failure(s)" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
