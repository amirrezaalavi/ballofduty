class_name NetProtocol
extends RefCounted
## CP4a binary wire protocol. All integers are little-endian, hand-packed so the
## layout is unambiguous across native and web exports.
##
## Snapshot budget: header 6 B + 22 B/player -> 182 B at 8 players (limit 300 B).
## Events are separate TCP messages (one per shot/hit/death/respawn).
## The velocity + on-floor fields exist so CP4b reconciliation can restart the
## replay from authoritative motion state instead of guessing it.
## Input packet: 12 B at 30 Hz upstream (~360 B/s).

enum Msg { JOIN_REQ = 1, JOIN_OK = 2, DENY = 3, ROSTER = 4, INPUT = 5, SNAPSHOT = 6, LEAVE = 7, PING = 8, PONG = 9, EVENT = 10 }
enum DenyReason { FULL = 1 }
enum EventType { SHOT = 1, HIT = 2, DEATH = 3, RESPAWN = 4 }
enum AnimState { STILL = 0, WALK = 1, SPRINT = 2, AIR = 3 }

const MAX_PLAYERS := 8
const CLASS_COUNT := 5
const MAX_NAME_BYTES := 16
const MAX_PACKET_BYTES := 2048
## Positions are quantized in centimetres over +/-327.68 m. 1 cm is well below
## one 30 Hz movement step and covers 150-250 m maps; the 22 B snapshot row and
## 182 B / 8-actor budget are unchanged.
const POS_RANGE := 327.68
const PITCH_RANGE := 1.6
const VEL_RANGE := 327.67


static func sanitize_class(raw: int) -> int:
	return clampi(raw, 0, CLASS_COUNT - 1)


static func sanitize_name(raw: String) -> String:
	var out := ""
	for c in raw.strip_edges().left(MAX_NAME_BYTES):
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-" or c == " ":
			out += c
	out = out.strip_edges()
	return out if out != "" else "Player"


static func encode_join_request(display_name: String, class_id: int = 0) -> PackedByteArray:
	var body := sanitize_name(display_name).to_utf8_buffer().slice(0, MAX_NAME_BYTES)
	var pkt := PackedByteArray([Msg.JOIN_REQ, body.size(), sanitize_class(class_id)])
	pkt.append_array(body)
	return pkt


static func decode_join_request(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() < 3 or pkt[0] != Msg.JOIN_REQ:
		return {}
	var name_len := pkt[1]
	if name_len > MAX_NAME_BYTES or pkt.size() != 3 + name_len:
		return {}
	return {
		"name": sanitize_name(pkt.slice(3).get_string_from_utf8()),
		"class_id": sanitize_class(pkt[2]),
	}


static func encode_join_ok(
	player_id: int, server_tick: int, spawn: Vector3 = Vector3.ZERO,
	yaw: float = 0.0, class_id: int = 0
) -> PackedByteArray:
	var pkt := PackedByteArray([Msg.JOIN_OK, player_id & 0xFF]) + _u32(server_tick)
	pkt.append_array(_i16(_quant_pos(spawn.x)))
	pkt.append_array(_i16(_quant_pos(spawn.y)))
	pkt.append_array(_i16(_quant_pos(spawn.z)))
	pkt.append_array(_i16(int(roundf(clampf(wrapf(yaw, -PI, PI) / PI, -1.0, 1.0) * 32767.0))))
	pkt.append(sanitize_class(class_id))
	return pkt


static func decode_join_ok(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() != 15 or pkt[0] != Msg.JOIN_OK:
		return {}
	return {
		"id": pkt[1],
		"tick": _get_u32(pkt, 2),
		"spawn": Vector3(_dequant_pos(_get_i16(pkt, 6)), _dequant_pos(_get_i16(pkt, 8)), _dequant_pos(_get_i16(pkt, 10))),
		"yaw": float(_get_i16(pkt, 12)) / 32767.0 * PI,
		"class_id": sanitize_class(pkt[14]),
	}


static func encode_deny(reason: int) -> PackedByteArray:
	return PackedByteArray([Msg.DENY, reason & 0xFF])


static func encode_roster(entries: Array) -> PackedByteArray:
	# entries: Array of {id: int, class_id: int, name: String}
	var pkt := PackedByteArray([Msg.ROSTER, mini(entries.size(), MAX_PLAYERS)])
	for entry in entries:
		var body := String(entry["name"]).to_utf8_buffer().slice(0, MAX_NAME_BYTES)
		pkt.append(entry["id"] & 0xFF)
		pkt.append(sanitize_class(int(entry.get("class_id", 0))))
		pkt.append(body.size())
		pkt.append_array(body)
	return pkt


static func decode_roster(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() < 2 or pkt[0] != Msg.ROSTER:
		return {}
	var count := pkt[1]
	if count > MAX_PLAYERS:
		return {}
	var entries: Array = []
	var offset := 2
	for _i in count:
		if offset + 3 > pkt.size():
			return {}
		var pid := pkt[offset]
		var class_id := sanitize_class(pkt[offset + 1])
		var name_len := pkt[offset + 2]
		offset += 3
		if name_len > MAX_NAME_BYTES or offset + name_len > pkt.size():
			return {}
		entries.append({
			"id": pid,
			"class_id": class_id,
			"name": sanitize_name(pkt.slice(offset, offset + name_len).get_string_from_utf8()),
		})
		offset += name_len
	if offset != pkt.size():
		return {}
	return {"entries": entries}


static func encode_input(
	seq: int, move: Vector2, jump: bool, sprint: bool, scoped: bool,
	yaw: float, pitch: float, fire: bool = false, reload: bool = false
) -> PackedByteArray:
	var flags := 0
	if jump:
		flags |= 1
	if sprint:
		flags |= 2
	if scoped:
		flags |= 4
	if fire:
		flags |= 8
	if reload:
		flags |= 16
	var pkt := PackedByteArray([Msg.INPUT]) + _u32(seq)
	pkt.append(clampi(int(roundf(clampf(move.x, -1.0, 1.0) * 127.0)), -128, 127) & 0xFF)
	pkt.append(clampi(int(roundf(clampf(move.y, -1.0, 1.0) * 127.0)), -128, 127) & 0xFF)
	pkt.append(flags & 0xFF)
	pkt.append_array(_i16(int(roundf(clampf(wrapf(yaw, -PI, PI) / PI, -1.0, 1.0) * 32767.0))))
	pkt.append_array(_i16(int(roundf(clampf(pitch / PITCH_RANGE, -1.0, 1.0) * 32767.0))))
	return pkt


static func decode_input(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() != 12 or pkt[0] != Msg.INPUT:
		return {}
	var move := Vector2(_s8(pkt[5]) / 127.0, _s8(pkt[6]) / 127.0)
	if move.length_squared() > 1.02:
		return {}
	return {
		"seq": _get_u32(pkt, 1),
		"move": move,
		"jump": (pkt[7] & 1) != 0,
		"sprint": (pkt[7] & 2) != 0,
		"scoped": (pkt[7] & 4) != 0,
		"fire": (pkt[7] & 8) != 0,
		"reload": (pkt[7] & 16) != 0,
		"yaw": float(_get_i16(pkt, 8)) / 32767.0 * PI,
		"pitch": float(_get_i16(pkt, 10)) / 32767.0 * PITCH_RANGE,
	}


static func encode_snapshot(tick: int, entries: Array) -> PackedByteArray:
	# entries: Array of {id, pos, yaw, state, vel, on_floor, hp, ack}
	# One allocation at the final size, then fixed-offset writes: the offsets
	# below are the wire contract (mirrored by decode_snapshot) and are locked
	# by the golden-byte test. The bytes must stay identical to the old
	# append-per-field encoder.
	# The count byte and the row loop must agree. Truncating here turns an
	# oversized roster into a valid packet instead of a 6 + 22 * count mismatch
	# that the decoder rejects as malformed. Raising MAX_PLAYERS is a separate
	# layout decision (NET-02), not something this guard does.
	var count := mini(entries.size(), MAX_PLAYERS)
	var pkt := PackedByteArray()
	pkt.resize(6 + count * 22)
	pkt.encode_u8(0, Msg.SNAPSHOT)
	pkt.encode_u32(1, tick & 0xFFFFFFFF)
	pkt.encode_u8(5, count & 0xFF)
	var offset := 6
	for i in count:
		var entry: Dictionary = entries[i]
		var pos: Vector3 = entry["pos"]
		var vel: Vector3 = entry.get("vel", Vector3.ZERO)
		pkt.encode_u8(offset, entry["id"] & 0xFF)
		pkt.encode_s16(offset + 1, _quant_pos(pos.x))
		pkt.encode_s16(offset + 3, _quant_pos(pos.y))
		pkt.encode_s16(offset + 5, _quant_pos(pos.z))
		pkt.encode_s16(offset + 7, int(roundf(clampf(wrapf(float(entry["yaw"]), -PI, PI) / PI, -1.0, 1.0) * 32767.0)))
		pkt.encode_u8(offset + 9, int(entry["state"]) & 0xFF)
		pkt.encode_s16(offset + 10, _quant_vel(vel.x))
		pkt.encode_s16(offset + 12, _quant_vel(vel.y))
		pkt.encode_s16(offset + 14, _quant_vel(vel.z))
		pkt.encode_u8(offset + 16, 1 if bool(entry.get("on_floor", true)) else 0)
		pkt.encode_u8(offset + 17, clampi(int(entry["hp"]), 0, 255) & 0xFF)
		pkt.encode_u32(offset + 18, int(entry["ack"]) & 0xFFFFFFFF)
		offset += 22
	return pkt


static func decode_snapshot(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() < 6 or pkt[0] != Msg.SNAPSHOT:
		return {}
	var count := pkt[5]
	if count > MAX_PLAYERS or pkt.size() != 6 + count * 22:
		return {}
	var entries: Array = []
	var offset := 6
	for _i in count:
		var flags := pkt[offset + 16]
		entries.append({
			"id": pkt[offset],
			"pos": Vector3(_dequant_pos(_get_i16(pkt, offset + 1)), _dequant_pos(_get_i16(pkt, offset + 3)), _dequant_pos(_get_i16(pkt, offset + 5))),
			"yaw": float(_get_i16(pkt, offset + 7)) / 32767.0 * PI,
			"state": pkt[offset + 9],
			"vel": Vector3(_dequant_vel(_get_i16(pkt, offset + 10)), _dequant_vel(_get_i16(pkt, offset + 12)), _dequant_vel(_get_i16(pkt, offset + 14))),
			"on_floor": (flags & 1) != 0,
			"hp": pkt[offset + 17],
			"ack": _get_u32(pkt, offset + 18),
		})
		offset += 22
	return {"tick": _get_u32(pkt, 1), "entries": entries}


static func encode_ping(client_msec: int) -> PackedByteArray:
	return PackedByteArray([Msg.PING]) + _u32(client_msec)


static func decode_ping(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() != 5 or pkt[0] != Msg.PING:
		return {}
	return {"client_msec": _get_u32(pkt, 1)}


static func encode_pong(client_msec: int, server_tick: int) -> PackedByteArray:
	return PackedByteArray([Msg.PONG]) + _u32(client_msec) + _u32(server_tick)


static func decode_pong(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() != 9 or pkt[0] != Msg.PONG:
		return {}
	return {"client_msec": _get_u32(pkt, 1), "server_tick": _get_u32(pkt, 5)}


## Server -> client gameplay events. Each packet is one event; lossless TCP.
static func encode_event_shot(shooter_id: int, origin: Vector3, direction: Vector3) -> PackedByteArray:
	var pkt := PackedByteArray([Msg.EVENT, EventType.SHOT, shooter_id & 0xFF])
	for axis in [origin.x, origin.y, origin.z]:
		pkt.append_array(_i16(_quant_pos(axis)))
	for axis in [direction.x, direction.y, direction.z]:
		pkt.append_array(_i16(int(roundf(clampf(axis, -1.0, 1.0) * 32767.0))))
	return pkt


static func encode_event_hit(
	target_id: int, shooter_id: int, damage: int,
	killed: bool, position: Vector3
) -> PackedByteArray:
	var flags := 0
	if killed:
		flags |= 1
	var pkt := PackedByteArray([Msg.EVENT, EventType.HIT, target_id & 0xFF, shooter_id & 0xFF])
	pkt.append(clampi(damage, 0, 255) & 0xFF)
	pkt.append(flags)
	for axis in [position.x, position.y, position.z]:
		pkt.append_array(_i16(_quant_pos(axis)))
	return pkt


static func encode_event_death(victim_id: int, killer_id: int, position: Vector3) -> PackedByteArray:
	var pkt := PackedByteArray([Msg.EVENT, EventType.DEATH, victim_id & 0xFF, killer_id & 0xFF])
	for axis in [position.x, position.y, position.z]:
		pkt.append_array(_i16(_quant_pos(axis)))
	return pkt


static func encode_event_respawn(player_id: int, position: Vector3, yaw: float) -> PackedByteArray:
	var pkt := PackedByteArray([Msg.EVENT, EventType.RESPAWN, player_id & 0xFF])
	for axis in [position.x, position.y, position.z]:
		pkt.append_array(_i16(_quant_pos(axis)))
	pkt.append_array(_i16(int(roundf(clampf(wrapf(yaw, -PI, PI) / PI, -1.0, 1.0) * 32767.0))))
	return pkt


static func decode_event(pkt: PackedByteArray) -> Dictionary:
	if pkt.size() < 3 or pkt[0] != Msg.EVENT:
		return {}
	var kind := pkt[1]
	if kind == EventType.SHOT:
		if pkt.size() != 15:
			return {}
		return {
			"type": kind,
			"shooter_id": pkt[2],
			"origin": Vector3(_dequant_pos(_get_i16(pkt, 3)), _dequant_pos(_get_i16(pkt, 5)), _dequant_pos(_get_i16(pkt, 7))),
			"direction": Vector3(_get_i16(pkt, 9) / 32767.0, _get_i16(pkt, 11) / 32767.0, _get_i16(pkt, 13) / 32767.0),
		}
	if kind == EventType.HIT:
		if pkt.size() != 12:
			return {}
		return {
			"type": kind,
			"target_id": pkt[2],
			"shooter_id": pkt[3],
			"damage": pkt[4],
			"killed": (pkt[5] & 1) != 0,
			"position": Vector3(_dequant_pos(_get_i16(pkt, 6)), _dequant_pos(_get_i16(pkt, 8)), _dequant_pos(_get_i16(pkt, 10))),
		}
	if kind == EventType.DEATH:
		if pkt.size() != 10:
			return {}
		return {
			"type": kind,
			"victim_id": pkt[2],
			"killer_id": pkt[3],
			"position": Vector3(_dequant_pos(_get_i16(pkt, 4)), _dequant_pos(_get_i16(pkt, 6)), _dequant_pos(_get_i16(pkt, 8))),
		}
	if kind == EventType.RESPAWN:
		if pkt.size() != 11:
			return {}
		return {
			"type": kind,
			"player_id": pkt[2],
			"position": Vector3(_dequant_pos(_get_i16(pkt, 3)), _dequant_pos(_get_i16(pkt, 5)), _dequant_pos(_get_i16(pkt, 7))),
			"yaw": float(_get_i16(pkt, 9)) / 32767.0 * PI,
		}
	return {}


static func msg_type(pkt: PackedByteArray) -> int:
	return pkt[0] if pkt.size() >= 1 else -1


static func _quant_pos(v: float) -> int:
	return clampi(int(roundf(clampf(v, -POS_RANGE, POS_RANGE - 0.01) * 100.0)), -32768, 32767)


static func _dequant_pos(q: int) -> float:
	return float(q) / 100.0


static func _quant_vel(v: float) -> int:
	return clampi(int(roundf(clampf(v, -VEL_RANGE, VEL_RANGE - 0.001) * 100.0)), -32768, 32767)


static func _dequant_vel(q: int) -> float:
	return float(q) / 100.0


static func _s8(b: int) -> int:
	return b - 256 if b > 127 else b


static func _u32(v: int) -> PackedByteArray:
	var u := v & 0xFFFFFFFF
	return PackedByteArray([u & 0xFF, (u >> 8) & 0xFF, (u >> 16) & 0xFF, (u >> 24) & 0xFF])


static func _get_u32(pkt: PackedByteArray, offset: int) -> int:
	return pkt[offset] | (pkt[offset + 1] << 8) | (pkt[offset + 2] << 16) | (pkt[offset + 3] << 24)


static func _i16(v: int) -> PackedByteArray:
	var u := clampi(v, -32768, 32767) & 0xFFFF
	return PackedByteArray([u & 0xFF, (u >> 8) & 0xFF])


static func _get_i16(pkt: PackedByteArray, offset: int) -> int:
	var u := pkt[offset] | (pkt[offset + 1] << 8)
	return u - 65536 if u > 32767 else u
