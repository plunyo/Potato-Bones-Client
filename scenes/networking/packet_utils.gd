class_name PacketUtils

enum Outgoing {
	JOIN = 0x00,
	MOVE = 0x01,
	PING = 0x02,
	PONG = 0x03,
	REQUEST_PLAYER_SYNC = 0x04,
	REQUEST_LOBBY_LIST = 0x06,
	CREATE_LOBBY = 0x07,
	KICK_PLAYER = 0x08,
	CHANGE_HOST = 0x09,
	LEAVE_LOBBY = 0x0A,
	REQUEST_LOBBY_SYNC = 0x0B,
	REQUEST_SESSION_ID = 0x0C,
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
	LOBBY_SYNC = 0x09,
	SESSION_ID = 0x0A
}

class ReadResult extends Object:
	var value
	var next_pos: int
	var fully_read: bool

	func _init(init_value = null, init_next_pos: int = 0, init_fully_read: bool = true) -> void:
		self.value = init_value
		self.next_pos = init_next_pos
		self.fully_read = init_fully_read

	func is_fully_read() -> bool:
		return self.fully_read

const BITS_16: int = 1 << 16
const BITS_15: int = 1 << 15

# -------------------- data readers --------------------
# all return a ReadResult instance
#region
static func read_var_int(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	var num: int = 0
	var shift: int = 0
	var pos: int = start_pos

	while pos < bytes.size():
		var b: int = bytes[pos]
		num |= (b & 0x7F) << shift
		pos += 1
		if (b & 0x80) == 0:
			return ReadResult.new(num, pos, true)
		shift += 7
		if shift > 35:
			break

	return ReadResult.new(num, pos, false)

# helper for reading counts
static func read_count(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	var res: ReadResult = read_var_int(bytes, start_pos)
	return ReadResult.new(int(res.value), res.next_pos, res.fully_read)

static func read_rotation(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	if start_pos + 2 > bytes.size():
		return ReadResult.new(0.0, start_pos, false)

	var raw: int = (bytes[start_pos] << 8) | bytes[start_pos + 1]
	var angle: float = float(raw) / 65536.0 * TAU
	return ReadResult.new(angle, start_pos + 2, true)

# generic reader for multiple items
static func read_multiple(bytes: PackedByteArray, start_pos: int, read_item_func: Callable) -> ReadResult:
	var count_res: ReadResult = read_count(bytes, start_pos)
	if not count_res.fully_read:
		return ReadResult.new([], count_res.next_pos, false)
	var items: Array = []
	var pos: int = count_res.next_pos
	for i: int in range(count_res.value):
		var item_res: ReadResult = read_item_func.call(bytes, pos)
		items.append(item_res.value)
		pos = item_res.next_pos
		if not item_res.fully_read:
			return ReadResult.new(items, pos, false)
	return ReadResult.new(items, pos, true)

static func read_string(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	var len_res: ReadResult = read_var_int(bytes, start_pos)
	var length: int = len_res.value
	var pos: int = len_res.next_pos
	if pos + length > bytes.size():
		# not enough bytes for the full string
		return ReadResult.new("", pos, false)
	var str_bytes: PackedByteArray = bytes.slice(pos, pos + length)
	return ReadResult.new(str_bytes.get_string_from_utf8(), pos + length, true)

static func read_position(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	var pos: int = start_pos
	if pos + 4 > bytes.size():
		return ReadResult.new(Vector2.ZERO, pos, false)
	var x: int = (bytes[pos] << 8) | bytes[pos + 1]
	var y: int = (bytes[pos + 2] << 8) | bytes[pos + 3]
	return ReadResult.new(Vector2(x - BITS_15, y - BITS_15), pos + 4, true)

static func read_boolean(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	if start_pos >= bytes.size():
		return ReadResult.new(false, start_pos, false)
	return ReadResult.new(bool(bytes[start_pos]), start_pos + 1, true)

static func read_player_update(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	var sequence_res: ReadResult = read_var_int(bytes, start_pos)

	var read_player_item: Callable = func(b: PackedByteArray, p: int) -> ReadResult:

		var id_res: ReadResult = read_var_int(b, p)
		var pos: int = id_res.next_pos

		var pos_res: ReadResult = read_position(b, pos)
		pos = pos_res.next_pos

		var rotation_res: ReadResult = read_rotation(b, pos)
		#print(b.slice(sequence_res.next_pos))

		return ReadResult.new(
			{
				id = id_res.value,
				position = pos_res.value,
				rotation = rotation_res.value
			},
			rotation_res.next_pos
		)

	return read_multiple(bytes, sequence_res.next_pos, read_player_item)

static func read_player_names(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	return read_multiple(bytes, start_pos, read_string)

static func read_lobby_list(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	var read_lobby_item: Callable = func(b: PackedByteArray, p: int) -> ReadResult:
		var id_res: ReadResult = read_var_int(b, p)
		if not id_res.fully_read:
			return ReadResult.new({}, id_res.next_pos, false)
		var lobby_id: int = id_res.value
		var pos: int = id_res.next_pos

		var name_res: ReadResult = read_string(b, pos)
		if not name_res.fully_read:
			return ReadResult.new({}, name_res.next_pos, false)
		var lobby_name: String = name_res.value
		pos = name_res.next_pos

		var host_id_res: ReadResult = read_var_int(b, pos)
		if not host_id_res.fully_read:
			return ReadResult.new({}, host_id_res.next_pos, false)
		var host_id: int = host_id_res.value
		pos = host_id_res.next_pos

		var player_names_res: ReadResult = read_player_names(b, pos)
		if not player_names_res.fully_read:
			return ReadResult.new({}, player_names_res.next_pos, false)
		var player_names: PackedStringArray = player_names_res.value
		pos = player_names_res.next_pos

		return ReadResult.new({"name": lobby_name, "id": lobby_id, "host_id": host_id, "players": player_names}, pos, true)
	return read_multiple(bytes, start_pos, read_lobby_item)

static func read_lobby_sync(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	var in_lobby_res: ReadResult = PacketUtils.read_boolean(bytes, start_pos)
	var in_lobby: bool = in_lobby_res.value
	var pos: int = in_lobby_res.next_pos

	var lobby_id_res: ReadResult = PacketUtils.read_var_int(bytes, pos)
	var lobby_id: int = lobby_id_res.value
	pos = lobby_id_res.next_pos

	var lobby_name_res: ReadResult = PacketUtils.read_string(bytes, pos)
	var lobby_name: String = lobby_name_res.value
	pos = lobby_name_res.next_pos

	var host_id_res: ReadResult = PacketUtils.read_var_int(bytes, pos)
	var host_id: int = host_id_res.value

	ServerConnection.lobby_info = {
		in_lobby = in_lobby,
		lobby_id = lobby_id,
		lobby_name = lobby_name,
		host_id = host_id,
	}

	return ReadResult.new(ServerConnection.lobby_info, host_id_res.next_pos, true)

static func read_player_sync(bytes: PackedByteArray, start_pos: int = 0) -> ReadResult:
	var pos: int = start_pos

	var read_sync_item: Callable = func(b: PackedByteArray, p: int) -> ReadResult:
		var local_pos: int = p

		# read player id
		var id_res: ReadResult = read_var_int(b, local_pos)
		if not id_res.fully_read:
			return ReadResult.new({}, id_res.next_pos, false)
		var player_id: int = id_res.value
		local_pos = id_res.next_pos

		# read player username
		var name_res: ReadResult = read_string(b, local_pos)
		if not name_res.fully_read:
			return ReadResult.new({}, name_res.next_pos, false)
		var username: String = name_res.value
		local_pos = name_res.next_pos

		return ReadResult.new({
			"id": player_id,
			"username": username
		}, local_pos, true)

	var players_res: ReadResult = read_multiple(bytes, pos, read_sync_item)
	return ReadResult.new(players_res.value, players_res.next_pos, players_res.fully_read)


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

static func write_rotation(angle_radians: float) -> PackedByteArray:
	var value: int = int(angle_radians / (2.0 * PI) * 65536.0) & 0xFFFF
	var out: PackedByteArray = PackedByteArray()
	out.append((value >> 8) & 0xFF)
	out.append(value & 0xFF)
	return out

static func write_boolean(value: bool) -> PackedByteArray:
	return PackedByteArray([1 if value else 0])

#endregion
