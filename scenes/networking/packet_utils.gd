class_name PacketUtils

enum Outgoing {
	JOIN =  0x00,
	MOVE = 0x01,
	PING = 0x02,
	PONG = 0x03,
	REQUEST_SYNC = 0x04,
	REQUEST_LOBBY_LIST = 0x06,
	CREATE_LOBBY = 0x07,
	KICK_PLAYER = 0x08,
	CHANGE_HOST = 0x09,
	LEAVE_LOBBY = 0x0A,
	REQUEST_LOBBY_SYNC = 0x0B
}

enum Incoming {
	JOIN_ACCEPT = 0x00,
	JOIN_DENY = 0x01,
	PING = 0x02,
	PONG = 0x03,
	UPDATE_PLAYERS = 0x04,
	SYNC_PLAYERS = 0x05,
	KICK_PLAYER = 0x06,
	CLIENT_ID = 0x07,
	LOBBY_LIST = 0x08,
	LOBBY_SYNC = 0x09
}

const BITS_15: int = 2 << 15

# -------------------- data readers --------------------
# all return an Array: [value, next_pos]
#region

enum  { VALUE, NEXT_POS, FULLY_READ }

static func read_var_int(bytes: PackedByteArray, start_pos: int = 0) -> Array:
	var num: int = 0
	var shift: int = 0
	var pos: int = start_pos

	while pos < bytes.size():
		var b: int = bytes[pos]
		num |= (b & 0x7F) << shift
		pos += 1
		if (b & 0x80) == 0:
			return [num, pos, true]
		shift += 7
		if shift > 35:
			break

	return [num, pos, false]

# helper for reading counts
static func read_count(bytes: PackedByteArray, start_pos: int = 0) -> Dictionary:
	var res: Array = read_var_int(bytes, start_pos)
	return {"count": int(res[VALUE]), "pos": int(res[NEXT_POS])}

# generic reader for multiple items
static func read_multiple(bytes: PackedByteArray, start_pos: int, read_item_func: Callable) -> Array:
	var count_res: Dictionary = read_count(bytes, start_pos)
	var items: Array = []
	var pos: int = count_res.pos
	for i: int in range(count_res.count):
		var item_res: Array = read_item_func.call(bytes, pos)
		items.append(item_res[VALUE])
		pos = item_res[NEXT_POS]
	return [items, pos]

static func read_string(bytes: PackedByteArray, start_pos: int = 0) -> Array:
	var len_res: Array = read_var_int(bytes, start_pos)
	var length: int = len_res[VALUE]
	var pos: int = len_res[NEXT_POS]
	var str_bytes: PackedByteArray = bytes.slice(pos, pos + length)
	return [str_bytes.get_string_from_utf8(), pos + length]

static func read_position(bytes: PackedByteArray, start_pos: int = 0) -> Array:
	var pos: int = start_pos
	if pos + 4 > bytes.size():
		return [Vector2.ZERO, pos]
	var x: int = (bytes[pos] << 8) | bytes[pos + 1]
	var y: int = (bytes[pos + 2] << 8) | bytes[pos + 3]
	return [Vector2(x - BITS_15, y - BITS_15), pos + 4]

static func read_boolean(bytes: PackedByteArray, start_pos: int = 0) -> Array:
	return [bool(bytes[start_pos]), start_pos + 1]

static func read_player_update(bytes: PackedByteArray, start_pos: int = 0) -> Array:
	var read_player_item: Callable = func(b: PackedByteArray, p: int) -> Array:
		var id_res: Array = read_var_int(b, p)
		var player_id: int = id_res[VALUE]
		var pos: int = id_res[NEXT_POS]
		var pos_res: Array = read_position(b, pos)
		return [{"id": player_id, "position": pos_res[VALUE]}, pos_res[NEXT_POS]]
	return read_multiple(bytes, start_pos, read_player_item)

static func read_player_names(bytes: PackedByteArray, start_pos: int = 0) -> Array:
	return read_multiple(bytes, start_pos, read_string)

static func read_lobby_list(bytes: PackedByteArray, start_pos: int = 0) -> Array:
	var read_lobby_item: Callable = func(b: PackedByteArray, p: int) -> Array:
		var id_res: Array = read_var_int(b, p)
		var lobby_id: int = id_res[VALUE]
		var pos: int = id_res[NEXT_POS]

		var name_res: Array = read_string(b, pos)
		var lobby_name: String = name_res[VALUE]
		pos = name_res[NEXT_POS]

		var host_id_res: Array = read_var_int(b, pos)
		var host_id: int = host_id_res[VALUE]
		pos = host_id_res[NEXT_POS]

		var player_names_res: Array = read_player_names(b, pos)
		var player_names: PackedStringArray = player_names_res[VALUE]
		pos = player_names_res[NEXT_POS]

		return [{"name": lobby_name, "id": lobby_id, "host_id": host_id, "players": player_names}, pos]
	return read_multiple(bytes, start_pos, read_lobby_item)

static func read_lobby_sync(bytes: PackedByteArray, start_pos: int = 0) -> Array:
	var in_lobby_res: Array = PacketUtils.read_boolean(bytes, start_pos)
	var in_lobby: bool = in_lobby_res[VALUE]
	var pos: int = in_lobby_res[NEXT_POS]

	var lobby_id_res: Array = PacketUtils.read_var_int(bytes, pos)
	var lobby_id: int = lobby_id_res[VALUE]
	pos = lobby_id_res[NEXT_POS]

	var lobby_name_res: Array = PacketUtils.read_string(bytes, pos)
	var lobby_name: String = lobby_name_res[VALUE]
	pos = lobby_name_res[NEXT_POS]

	var host_id_res: Array = PacketUtils.read_var_int(bytes, pos)
	var host_id: int = host_id_res[VALUE]

	ServerConnection.lobby_info = {
		in_lobby = in_lobby,
		lobby_id = lobby_id,
		lobby_name = lobby_name,
		host_id = host_id,
	}

	return [ServerConnection.lobby_info, host_id_res[NEXT_POS]]

static func read_player_sync(bytes: PackedByteArray, start_pos: int = 0) -> Array:
	var pos: int = start_pos

	var read_sync_item: Callable = func(b: PackedByteArray, p: int) -> Array:
		var local_pos: int = p
		var id_res: Array = read_var_int(b, local_pos)
		var player_id: int = id_res[VALUE]
		local_pos = id_res[NEXT_POS]

		var name_res: Array = read_string(b, local_pos)
		var username: String = name_res[VALUE]
		local_pos = name_res[NEXT_POS]

		var pos_res: Array = read_position(b, local_pos)
		return [{"id": player_id, "username": username, "position": pos_res[VALUE]}, pos_res[NEXT_POS]]

	var players_res: Array = read_multiple(bytes, pos, read_sync_item)
	return [players_res[VALUE], players_res[NEXT_POS]]

#endregion

# -------------------- writers --------------------
# each returns a PackedByteArray that contains the encoded data
#region

static func write_var_int(value: int) -> PackedByteArray:
	var v: int = value
	var out: PackedByteArray = PackedByteArray()
	while true:
		var byte: int = v & 0x7F
		v >>= 7
		if v != 0:
			byte |= 0x80
		out.append(byte)
		if v == 0:
			break
	return out

static func write_string(value: String) -> PackedByteArray:
	var text_bytes: PackedByteArray = value.to_utf8_buffer()
	var out: PackedByteArray = PackedByteArray()
	out.append_array(write_var_int(text_bytes.size()))
	out.append_array(text_bytes)
	return out

static func write_position(value: Vector2) -> PackedByteArray:
	var xi: int = int(value.x) + BITS_15
	var yi: int = int(value.y) + BITS_15
	var out: PackedByteArray = PackedByteArray()
	out.append((xi >> 8) & 0xFF)
	out.append(xi & 0xFF)
	out.append((yi >> 8) & 0xFF)
	out.append(yi & 0xFF)
	return out

static func write_boolean(value: bool) -> PackedByteArray:
	return PackedByteArray([1 if value else 0])

#endregion
