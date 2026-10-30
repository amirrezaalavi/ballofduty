extends BodTestSuite
## CP4a wire protocol: roundtrips, budgets, quantization, malformed rejection.

var _budget_bytes: int = 0


func test_join_request_is_sanitized() -> void:
	var join := NetProtocol.encode_join_request("  Alice_99!@#  ")
	var decoded := NetProtocol.decode_join_request(join)
	expect(decoded.get("name") == "Alice_99", "join request sanitizes the name (got '%s')" % decoded.get("name"))
	expect(int(decoded.get("version", 0)) == NetProtocol.PROTOCOL_VERSION,
		"join request carries protocol version %d (got %d)" % [NetProtocol.PROTOCOL_VERSION, int(decoded.get("version", 0))])
	expect(NetProtocol.decode_join_request(PackedByteArray([1, 99])) == {}, "oversized name length rejected")
	expect(NetProtocol.decode_join_request(PackedByteArray([9, 0])) == {}, "wrong message id rejected")
	expect(NetProtocol.decode_join_request(PackedByteArray([1, 2, 3])) == {}, "short join request rejected")
	expect(NetProtocol.decode_join_request(PackedByteArray([1, 2, 5, 0, 65])) == {}, "name length past the end rejected")

	# v1 requests still parse structurally, but the version byte is visibly
	# different so the server can refuse them at the door.
	var legacy := NetProtocol.decode_join_request(NetProtocol.encode_join_request("Alice", 0, 1))
	expect(int(legacy.get("version", -1)) == 1, "v1 join request decodes with version 1")
	expect(int(legacy.get("version", -1)) != NetProtocol.PROTOCOL_VERSION, "v1 version differs from current")
	expect(legacy.get("name") == "Alice", "v1 join request still carries the name")


func test_join_ok_carries_spawn() -> void:
	# Regression for the 22 m spawn mismatch: spawn pose must survive the wire.
	var pkt := NetProtocol.encode_join_ok(3, 4242, Vector3(22.0, 0.3, -15.556), -1.2)
	var join_ok := NetProtocol.decode_join_ok(pkt)
	expect(join_ok.get("id") == 3 and join_ok.get("tick") == 4242, "join ok id/tick roundtrip")
	expect(pkt.size() == 16, "join ok is 16 B (got %d)" % pkt.size())
	expect(int(join_ok.get("version", 0)) == NetProtocol.PROTOCOL_VERSION, "join ok carries the protocol version")
	var spawn: Vector3 = join_ok.get("spawn", Vector3.ZERO)
	expect(spawn.distance_to(Vector3(22.0, 0.3, -15.556)) < 0.005, "join ok spawn roundtrips within 5 mm")
	expect(absf(float(join_ok.get("yaw", 0.0)) - -1.2) < 0.001, "join ok yaw roundtrips")
	expect(NetProtocol.decode_join_ok(PackedByteArray([2, 1, 0, 0, 0, 0])) == {}, "truncated join ok rejected")
	expect(NetProtocol.decode_join_ok(pkt.slice(0, 15)) == {}, "15 B join ok rejected")
	expect(NetProtocol.decode_join_ok(NetProtocol.encode_join_ok(3, 4242, Vector3.ZERO, 0.0, 0, 1)).get("version", 0) == 1,
		"v1 join ok decodes with version 1")


func test_roster_roundtrip() -> void:
	var empty := NetProtocol.decode_roster(NetProtocol.encode_roster([]))
	expect(empty.get("entries", [-1]).is_empty(), "empty roster roundtrips")
	var many: Array = []
	for i in 8:
		many.append({"id": i + 1, "name": "P%d" % i})
	var full := NetProtocol.decode_roster(NetProtocol.encode_roster(many))
	expect(full.get("entries", []).size() == 8, "8-player roster roundtrips")
	var sixteen: Array = []
	for i in 16:
		sixteen.append({"id": i + 1, "name": "P%d" % i})
	var capped := NetProtocol.decode_roster(NetProtocol.encode_roster(sixteen))
	expect(capped.get("entries", []).size() == 16, "16-player roster roundtrips")
	expect(int(capped["entries"][15]["id"]) == 16, "last 16-player roster entry survives")
	expect(NetProtocol.decode_roster(PackedByteArray([4, 17])) == {}, "roster over capacity rejected")


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
	expect(_budget_bytes == 150, "8-player snapshot is %d B (expected 150 B)" % _budget_bytes)
	expect(_budget_bytes <= 300, "8-player snapshot within the 300 B budget")

	var back := NetProtocol.decode_snapshot(snap)
	expect(back.get("tick") == 123456, "snapshot tick roundtrips")
	var first: Dictionary = back.get("entries")[0]
	var rpos: Vector3 = first["pos"]
	var epos: Vector3 = entries[0]["pos"]
	expect(rpos.distance_to(epos) < 0.01, "position quantization < 1 cm")
	expect(absf(float(first["yaw"]) - wrapf(float(entries[0]["yaw"]), -PI, PI)) < 0.002, "snapshot yaw < 12-bit step (0.002 rad)")
	expect(first["state"] == 0 and first["hp"] == 100 and first["ack"] == 5000, "snapshot state/hp/ack roundtrip")
	var rvel: Vector3 = first["vel"]
	expect(rvel.distance_to(Vector3(1.25, -2.5, 7.5)) < 0.02, "velocity roundtrips within 2 cm/s")
	expect(first["on_floor"] == true, "on-floor flag roundtrips")
	expect(back.get("entries")[1]["on_floor"] == false, "airborne flag roundtrips")

	expect(NetProtocol.decode_snapshot(PackedByteArray([6, 1, 2, 3, 4, 9])) == {}, "truncated snapshot rejected")
	var tampered := snap.duplicate()
	tampered.append(0)
	expect(NetProtocol.decode_snapshot(tampered) == {}, "trailing-byte snapshot rejected")


func test_sixteen_actor_snapshot_roundtrip() -> void:
	var entries: Array = []
	for i in 16:
		entries.append({
			"id": i + 1, "pos": Vector3(-60.0 + i * 7.5, 0.25 + i * 0.05, 80.0 - i * 9.0),
			"yaw": -PI + i * (2.0 * PI / 16.0), "state": i % 4,
			"vel": Vector3(1.5 - i * 0.2, -3.0 + i * 0.1, 6.0),
			"on_floor": i % 2 == 0,
			"hp": 127 - i, "ack": 60000 + i,
		})
	var snap := NetProtocol.encode_snapshot(987654, entries)
	print("  snapshot 16-player bytes=%d" % snap.size())
	expect(snap.size() == 294, "16-player snapshot is %d B (expected 294 B)" % snap.size())
	expect(snap.size() <= 300, "16-player snapshot within the 300 B budget")
	var back := NetProtocol.decode_snapshot(snap)
	expect(not back.is_empty(), "16-player snapshot decodes")
	expect(int(back.get("tick", 0)) == 987654, "16-player tick roundtrips")
	var rows: Array = back.get("entries", [])
	expect(rows.size() == 16, "all 16 rows decode")
	for i in 16:
		var got: Dictionary = rows[i]
		var want: Dictionary = entries[i]
		expect(int(got["id"]) == int(want["id"]), "row %d id roundtrips" % i)
		expect((got["pos"] as Vector3).distance_to(want["pos"]) < 0.01, "row %d position < 1 cm" % i)
		expect(absf(float(got["yaw"]) - wrapf(float(want["yaw"]), -PI, PI)) < 0.002, "row %d yaw < 12-bit step" % i)
		expect(int(got["state"]) == int(want["state"]), "row %d state roundtrips" % i)
		expect(bool(got["on_floor"]) == bool(want["on_floor"]), "row %d on-floor roundtrips" % i)
		expect(int(got["hp"]) == int(want["hp"]), "row %d hp roundtrips" % i)
		expect((got["vel"] as Vector3).distance_to(want["vel"]) < 0.02, "row %d velocity < 2 cm/s" % i)
		expect(int(got["ack"]) == int(want["ack"]), "row %d ack roundtrips" % i)


func test_ping_pong_and_transport_cap() -> void:
	expect(NetProtocol.decode_ping(NetProtocol.encode_ping(999)) == {"client_msec": 999}, "ping roundtrips")
	var pong := NetProtocol.decode_pong(NetProtocol.encode_pong(999, 77))
	expect(pong == {"client_msec": 999, "server_tick": 77}, "pong roundtrips")
	expect(NetProtocol.MAX_PACKET_BYTES == 2048, "transport cap is 2048 B")


func test_combat_input_bits() -> void:
	var input := NetProtocol.decode_input(
		NetProtocol.encode_input(77, Vector2.ZERO, false, false, false, 0.5, -0.2, true, true)
	)
	expect(input.get("fire") == true, "fire bit roundtrips")
	expect(input.get("reload") == true, "reload bit roundtrips")
	var quiet := NetProtocol.decode_input(
		NetProtocol.encode_input(78, Vector2.ZERO, false, false, false, 0.0, 0.0, false, false)
	)
	expect(quiet.get("fire") == false and quiet.get("reload") == false, "idle input has no combat bits")


func test_events_roundtrip() -> void:
	var origin := Vector3(1.25, 0.6, -3.5)
	var direction := Vector3(0.0, 0.1, -0.995).normalized()
	var shot := NetProtocol.decode_event(NetProtocol.encode_event_shot(3, origin, direction))
	expect(shot.get("type") == NetProtocol.EventType.SHOT, "shot event type")
	expect(int(shot.get("shooter_id", -1)) == 3, "shot shooter id")
	expect((shot.get("origin", Vector3.ZERO) as Vector3).distance_to(origin) < 0.01, "shot origin within 1 cm")
	expect((shot.get("direction", Vector3.ZERO) as Vector3).distance_to(direction) < 0.001, "shot direction quantized")

	var hit := NetProtocol.decode_event(NetProtocol.encode_event_hit(
		2, 3, 34, true, Vector3(2.0, 0.9, 0.0)
	))
	expect(hit.get("type") == NetProtocol.EventType.HIT, "hit event type")
	expect(int(hit.get("target_id", -1)) == 2 and int(hit.get("shooter_id", -1)) == 3, "hit ids")
	expect(int(hit.get("damage", 0)) == 34, "hit damage")
	expect(bool(hit.get("killed")), "hit killed flag")
	expect(not hit.has("headshot"), "hit events carry no headshot flag")

	var death := NetProtocol.decode_event(NetProtocol.encode_event_death(2, 3, Vector3(2, 0, 0)))
	expect(death.get("type") == NetProtocol.EventType.DEATH, "death event type")
	expect(int(death.get("victim_id", -1)) == 2 and int(death.get("killer_id", -1)) == 3, "death ids")

	var respawn := NetProtocol.decode_event(NetProtocol.encode_event_respawn(2, Vector3(4, 0.2, 4), -1.2))
	expect(respawn.get("type") == NetProtocol.EventType.RESPAWN, "respawn event type")
	expect((respawn.get("position", Vector3.ZERO) as Vector3).distance_to(Vector3(4, 0.2, 4)) < 0.01, "respawn position")
	expect(absf(float(respawn.get("yaw", 0.0)) - -1.2) < 0.001, "respawn yaw")

	expect(NetProtocol.decode_event(PackedByteArray([10, 1, 1])) == {}, "truncated event rejected")
	expect(NetProtocol.decode_event(PackedByteArray([10, 99, 1])) == {}, "unknown event rejected")


func test_class_id_roundtrip() -> void:
	var req := NetProtocol.decode_join_request(NetProtocol.encode_join_request("Mage", 4))
	expect(int(req.get("class_id", -1)) == 4, "join request carries class 4")
	var clamped := NetProtocol.decode_join_request(NetProtocol.encode_join_request("X", 99))
	expect(int(clamped.get("class_id", -1)) == NetProtocol.CLASS_COUNT - 1, "class id is clamped")
	var ok := NetProtocol.decode_join_ok(NetProtocol.encode_join_ok(2, 10, Vector3.ZERO, 0.0, 3))
	expect(int(ok.get("class_id", -1)) == 3, "join ok carries class 3")
	var roster := NetProtocol.decode_roster(NetProtocol.encode_roster([
		{"id": 1, "name": "A", "class_id": 2},
		{"id": 2, "name": "B", "class_id": 4},
	]))
	expect(int(roster["entries"][0]["class_id"]) == 2, "roster class 2")
	expect(int(roster["entries"][1]["class_id"]) == 4, "roster class 4")


func test_long_range_positions_roundtrip() -> void:
	# A 150-250 m map needs absolute positions far outside the old +/-32.768 m
	# window. 1 cm quantization must survive the full range, and only values
	# beyond the new +/-327.68 m limit may clamp.
	var points := [
		Vector3(0.0, 0.0, 0.0),
		Vector3(40.0, 3.0, -40.0),
		Vector3(-69.0, 5.0, 69.0),
		Vector3(124.995, 12.0, -124.995),
		Vector3(-327.67, 0.0, 327.67),
	]
	for point in points:
		var snap := NetProtocol.encode_snapshot(7, [{
			"id": 1, "pos": point, "yaw": 0.0, "state": 0,
			"vel": Vector3.ZERO, "on_floor": true, "hp": 100, "ack": 0,
		}])
		var back := NetProtocol.decode_snapshot(snap)
		expect(not back.is_empty(), "long-range snapshot decodes")
		if back.is_empty():
			continue
		var got: Vector3 = back["entries"][0]["pos"]
		expect(got.distance_to(point) < 0.01,
			"position %s roundtrips within 1 cm (got %s)" % [point, got])
		expect(snap.size() == 24, "one actor stays 24 B at long range")

	var far := NetProtocol.encode_snapshot(7, [{
		"id": 1, "pos": Vector3(400.0, 0.0, -400.0), "yaw": 0.0, "state": 0,
		"vel": Vector3.ZERO, "on_floor": true, "hp": 100, "ack": 0,
	}])
	var clamped: Vector3 = NetProtocol.decode_snapshot(far)["entries"][0]["pos"]
	expect(clamped.x <= 327.68 and clamped.z >= -327.68,
		"positions beyond the range clamp to the new limit (got %s)" % clamped)


func test_snapshot_golden_bytes() -> void:
	# Locks the wire layout: header 6 B + one 18 B row. If this hex changes, the
	# protocol changed and every client/server build must move together.
	var entry := {
		"id": 7, "pos": Vector3(1.23, -4.56, 7.89), "yaw": 1.0,
		"state": 2, "vel": Vector3(3.21, -0.5, 0.0), "on_floor": true,
		"hp": 87, "ack": 0x0A0B0C0D,
	}
	var snap := NetProtocol.encode_snapshot(0x01020304, [entry])
	var expected := "060403020101077b0038fe15038bea2b4101ceff00000d0c"
	expect(snap.size() == 24, "golden snapshot is 24 B (got %d)" % snap.size())
	expect(snap.hex_encode() == expected,
		"golden snapshot bytes match (got %s)" % snap.hex_encode())

	var back := NetProtocol.decode_snapshot(snap)
	expect(int(back.get("tick", 0)) == 0x01020304, "golden tick roundtrips")
	var row: Dictionary = back.get("entries", [])[0]
	expect(int(row.get("id", 0)) == 7, "golden id roundtrips")
	expect((row.get("pos", Vector3.ZERO) as Vector3).distance_to(Vector3(1.23, -4.56, 7.89)) < 0.01,
		"golden position roundtrips within 1 cm")
	expect(absf(float(row.get("yaw", 0.0)) - 1.0) < 0.002, "golden yaw roundtrips within a 12-bit step")
	expect(int(row.get("state", -1)) == 2, "golden state roundtrips")
	expect((row.get("vel", Vector3.ZERO) as Vector3).distance_to(Vector3(3.21, -0.5, 0.0)) < 0.02,
		"golden velocity roundtrips within 2 cm/s")
	expect(bool(row.get("on_floor", false)), "golden on-floor flag roundtrips")
	expect(int(row.get("hp", -1)) == 87, "golden hp roundtrips")
	expect(int(row.get("ack", 0)) == 0x0C0D, "golden ack roundtrips as its low u16")


func test_snapshot_ack_is_u16() -> void:
	var base := {
		"id": 1, "pos": Vector3.ZERO, "yaw": 0.0, "state": 0,
		"vel": Vector3.ZERO, "on_floor": true, "hp": 100,
	}
	var small := base.duplicate()
	small["ack"] = 5000
	var decoded_small := NetProtocol.decode_snapshot(NetProtocol.encode_snapshot(1, [small]))
	expect(int(decoded_small["entries"][0]["ack"]) == 5000, "ack 5000 roundtrips as u16")

	# 5 minutes at 30 Hz is 9000 frames, but the field is 16 bits: high bits are
	# explicitly truncated so both ends agree on the wrap.
	var large := base.duplicate()
	large["ack"] = 0x12345
	var decoded_large := NetProtocol.decode_snapshot(NetProtocol.encode_snapshot(1, [large]))
	expect(int(decoded_large["entries"][0]["ack"]) == 0x2345,
		"ack 0x12345 decodes to its low 16 bits (got %d)" % int(decoded_large["entries"][0]["ack"]))
	var wrapped := base.duplicate()
	wrapped["ack"] = 65535
	var decoded_wrapped := NetProtocol.decode_snapshot(NetProtocol.encode_snapshot(1, [wrapped]))
	expect(int(decoded_wrapped["entries"][0]["ack"]) == 65535, "ack 65535 roundtrips as u16")


func test_oversized_roster_truncates_instead_of_malforming() -> void:
	# The count byte and the row loop must agree. Passing more entries than
	# MAX_PLAYERS writes a valid 16-actor packet instead of a malformed one.
	var entries: Array = []
	for i in 17:
		entries.append({
			"id": i + 1, "pos": Vector3(float(i), 0.0, 0.0), "yaw": 0.0,
			"state": 0, "vel": Vector3.ZERO, "on_floor": true,
			"hp": 100, "ack": i,
		})
	var snap := NetProtocol.encode_snapshot(9, entries)
	expect(snap.size() == 6 + NetProtocol.MAX_PLAYERS * 18,
		"oversized snapshot stays at the 16-actor size (%d B)" % snap.size())
	expect(snap.size() == 294, "16-actor packet is 294 B")
	expect(int(snap[5]) == NetProtocol.MAX_PLAYERS, "count byte matches the row cap")
	var back := NetProtocol.decode_snapshot(snap)
	expect(not back.is_empty(), "truncated snapshot is valid")
	expect(back["entries"].size() == NetProtocol.MAX_PLAYERS, "only the cap is encoded")
	expect(int(back["entries"][15]["id"]) == 16, "the sixteenth actor is written")
	var ids: Array = []
	for row in back["entries"]:
		ids.append(int(row["id"]))
	expect(not ids.has(17), "the seventeenth actor is absent")
