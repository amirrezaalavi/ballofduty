extends BodTestSuite
## Match wire messages: SCORE (full kills/deaths table) and MATCH (clock/state)
## roundtrip exactly, stay small, and reject malformed packets like every other
## message. Snapshot rows are untouched, so the golden-byte budget still holds.


func test_score_roundtrip_and_budget() -> void:
	var entries: Array = []
	for i in 16:
		entries.append({"id": i + 1, "kills": i * 3, "deaths": i})
	var pkt := NetProtocol.encode_score(entries)
	expect(pkt.size() == 2 + 16 * 5, "16-player score table is %d B (expected 82 B)" % pkt.size())
	expect(pkt[0] == NetProtocol.Msg.SCORE, "score packet carries the SCORE type")
	var back := NetProtocol.decode_score(pkt)
	expect(not back.is_empty(), "score packet decodes")
	expect((back["entries"] as Array).size() == 16, "all 16 rows survive")
	var first: Dictionary = back["entries"][0]
	var last: Dictionary = back["entries"][15]
	expect(int(first["id"]) == 1 and int(first["kills"]) == 0 and int(first["deaths"]) == 0,
		"first row roundtrips")
	expect(int(last["id"]) == 16 and int(last["kills"]) == 45 and int(last["deaths"]) == 15,
		"last row roundtrips")

	var empty := NetProtocol.decode_score(NetProtocol.encode_score([]))
	expect(not empty.is_empty() and (empty["entries"] as Array).is_empty(),
		"empty table is valid (0 rows)")
	expect(NetProtocol.encode_score([]).size() == 2, "empty table is 2 B")


func test_score_clamps_and_rejects() -> void:
	var pkt := NetProtocol.encode_score([{"id": 7, "kills": 99999, "deaths": -3}])
	var back := NetProtocol.decode_score(pkt)
	var row: Dictionary = back["entries"][0]
	expect(int(row["kills"]) == 65535 and int(row["deaths"]) == 0,
		"kills/deaths clamp to u16 (got %d/%d)" % [int(row["kills"]), int(row["deaths"])])

	expect(NetProtocol.decode_score(PackedByteArray([11, 1, 5])) == {},
		"truncated score row rejected")
	var good := NetProtocol.encode_score([{"id": 1, "kills": 2, "deaths": 3}])
	var trailing := good + PackedByteArray([0])
	expect(NetProtocol.decode_score(trailing) == {}, "trailing-byte score rejected")
	var overfull := PackedByteArray([11, 17]) + PackedByteArray()
	overfull.resize(2 + 17 * 5)
	expect(NetProtocol.decode_score(overfull) == {}, "score count above the cap rejected")
	expect(NetProtocol.decode_score(PackedByteArray([10, 1, 2, 3, 4, 5, 6])) == {},
		"wrong message type rejected as score")


func test_match_roundtrip() -> void:
	var pkt := NetProtocol.encode_match(NetProtocol.MatchState.RUNNING, 299)
	expect(pkt.size() == 4, "match packet is 4 B (got %d)" % pkt.size())
	expect(pkt[0] == NetProtocol.Msg.MATCH, "match packet carries the MATCH type")
	var back := NetProtocol.decode_match(pkt)
	expect(int(back["state"]) == NetProtocol.MatchState.RUNNING, "running state roundtrips")
	expect(int(back["seconds_left"]) == 299, "299 s roundtrips")

	var over := NetProtocol.decode_match(
		NetProtocol.encode_match(NetProtocol.MatchState.OVER, 0))
	expect(int(over["state"]) == NetProtocol.MatchState.OVER, "over state roundtrips")
	expect(int(over["seconds_left"]) == 0, "zero seconds roundtrips")

	expect(NetProtocol.decode_match(PackedByteArray([12, 1, 5])) == {},
		"truncated match rejected")
	expect(NetProtocol.decode_match(PackedByteArray([12, 1, 5, 0, 9])) == {},
		"trailing-byte match rejected")
	expect(NetProtocol.MatchState.RUNNING == 1 and NetProtocol.MatchState.OVER == 2,
		"match states are stable wire values (running=1, over=2)")
