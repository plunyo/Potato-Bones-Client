extends Node

signal connected
signal disconnected
signal connection_failed
signal received_packet(packet_id: int, data: PackedByteArray)

const CONNECT_TIMEOUT: float = 5.0  # seconds
const BITS_15: int = 1 << 15

var _is_connected: bool = false
var _is_connecting: bool = false
var _connect_deadline: float = 0.0
var _last_status: int = -1

var socket: StreamPeerTCP = StreamPeerTCP.new()
var kick_reason: String = ""
var players: Array[Dictionary] = []
var client_id: int = -1

var incoming_buffer: PackedByteArray = PackedByteArray()

func _ready() -> void:
	received_packet.connect(_on_packet_received_handle_packet)

# -------------------- Connection --------------------

func connect_to_server(ip: String = "pi.plunyo.lol", port: int = 30000) -> void:
	if socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		socket.disconnect_from_host()

	_is_connecting = true
	_is_connected = false
	_connect_deadline = Time.get_ticks_msec() / 1000.0 + CONNECT_TIMEOUT

	var err: Error = socket.connect_to_host(ip, port)
	if err != OK:
		_is_connecting = false
		print("failed to start connect_to_host(): %s:%d (err %s)" % [ip, port, str(err)])
		emit_signal("connection_failed")
		return

	socket.set_no_delay(true)
	print("started connecting to %s:%d" % [ip, port])

func disconnect_from_server() -> void:
	if socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		socket.disconnect_from_host()
	_is_connected = false
	_is_connecting = false
	emit_signal("disconnected")

# -------------------- Process --------------------

func _process(_delta: float) -> void:
	socket.poll()

	var status: int = socket.get_status()
	if status != _last_status:
		_last_status = status

	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not _is_connected:
			_is_connected = true
			_is_connecting = false
			emit_signal("connected")

	elif status == StreamPeerTCP.STATUS_CONNECTING:
		if _is_connecting and (Time.get_ticks_msec() / 1000.0) > _connect_deadline:
			print("connection timed out")
			_handle_disconnect("timeout")
	elif status in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
		_handle_disconnect("error or closed")

	# process incoming bytes safely
	if _is_connected and socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var available: int = socket.get_available_bytes()
		if available > 0:
			_process_incoming()

func _handle_disconnect(reason: String) -> void:
	if _is_connected or _is_connecting:
		print("disconnected: %s" % reason)
		_is_connected = false
		_is_connecting = false
		socket.disconnect_from_host()
		emit_signal("disconnected")

# -------------------- Incoming --------------------

func _process_incoming() -> void:
	# append incoming bytes using helper (not as a method)
	var available: int = socket.get_available_bytes()
	if available > 0:
		var chunk: Array = socket.get_data(available)
		if chunk.size() >= 2 and chunk[0] == OK:
			var chunk_bytes: PackedByteArray = chunk[1]
			incoming_buffer.append_array(chunk_bytes)

	var pos: int = 0

	while true:
		# need at least one byte to read a varint length
		if pos >= incoming_buffer.size():
			break

		var len_res: Array = read_var_int(incoming_buffer, pos)
		# len_res == [value, next_pos, complete?]
		if len_res.size() >= 3 and not bool(len_res[2]):
			# incomplete length varint — wait for more bytes
			break

		var packet_length: int = int(len_res[VALUE])
		pos = int(len_res[1])

		# now we need to ensure the whole payload (packet_length bytes) is available
		if incoming_buffer.size() - pos < packet_length:
			# not enough bytes yet
			break

		# read packet id varint
		var id_res: Array = read_var_int(incoming_buffer, pos)
		if id_res.size() >= 3 and not bool(id_res[2]):
			# this shouldn't normally happen because we already checked packet_length,
			# but be defensive
			break

		var packet_id: int = int(id_res[VALUE])
		# header bytes is size of the packet_id varint
		var header_bytes: int = int(id_res[1]) - int(len_res[1])
		var data_length: int = int(packet_length) - header_bytes
		var data: PackedByteArray = incoming_buffer.slice(int(id_res[1]), int(id_res[1]) + data_length)

		# advance pos to after this packet
		pos = int(id_res[1]) + data_length

		# handle packet
		received_packet.emit(packet_id, data)

	# drop processed bytes
	if pos > 0:
		incoming_buffer = incoming_buffer.slice(pos, incoming_buffer.size())

# -------------------- Packet Handling --------------------

func send_packet(packet_id: int, data: PackedByteArray = PackedByteArray()) -> void:
	# build packet: [varint packet_length][varint packet_id][data...]
	var id_bytes: PackedByteArray = write_var_int(packet_id)
	var payload_len: int = id_bytes.size() + data.size()
	var len_bytes: PackedByteArray = write_var_int(payload_len)

	var out: PackedByteArray = PackedByteArray()

	append_array(out, len_bytes)
	append_array(out, id_bytes)
	append_array(out, data)

	socket.put_data(out)

func _on_packet_received_handle_packet(packet_id: int, data: PackedByteArray) -> void:
	# main packet handler
	if packet_id != PacketID.Incoming.UPDATE_PLAYERS:
		print("id: ", packet_id, ", data: ", data)
	match packet_id:
		PacketID.Incoming.JOIN_ACCEPT:  # join accept
			var read_res: Array = read_var_int(data, 0)
			client_id = int(read_res[VALUE])
		PacketID.Incoming.JOIN_DENY:  # join deny
			var res: Array = read_string(data, 0)
			print("join denied: %s" % str(res[VALUE]))
		PacketID.Incoming.KICK_PLAYER:
			var k_res: Array = read_string(data, 0)
			kick_reason = String(k_res[VALUE])
			get_tree().change_scene_to_file("res://scenes/connect_screen.tscn")

# -------------------- Data Readers --------------------
# all return an Array: [value, next_pos]

enum  { VALUE, NEXT_POS }

func read_var_int(bytes: PackedByteArray, start_pos: int) -> Array:
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


func read_string(bytes: PackedByteArray, start_pos: int) -> Array:
	var len_res: Array = read_var_int(bytes, start_pos)
	var length: int = int(len_res[VALUE])
	var pos: int = int(len_res[NEXT_POS])
	var str_bytes: PackedByteArray = bytes.slice(pos, pos + length)
	return [str_bytes.get_string_from_utf8(), pos + length]


func read_player_update(bytes: PackedByteArray, start_pos: int) -> Array:
	var len_res: Array = read_var_int(bytes, start_pos)
	var count: int = int(len_res[VALUE])
	var pos: int = int(len_res[NEXT_POS])

	var result: Array = []
	result.resize(count)

	for i in range(count):
		var id_res: Array = read_var_int(bytes, pos)
		var player_id: int = int(id_res[VALUE])
		pos = int(id_res[1])

		var pos_res: Array = read_position(bytes, pos)
		var position: Vector2 = pos_res[VALUE]
		pos = int(pos_res[1])

		result[i] = {"id": player_id, "position": position}

	return [result, pos]

func read_player_names(bytes: PackedByteArray, start_pos: int) -> Array:
	var len_res: Array = read_var_int(bytes, start_pos)
	var count: int = int(len_res[VALUE])
	var pos: int = int(len_res[1])

	var names: PackedStringArray = PackedStringArray()
	names.resize(count)

	for i in range(count):
		var name_res: Array = read_string(bytes, pos)
		names[i] = String(name_res[VALUE])
		pos = int(name_res[1])

	return [names, pos]

func read_lobby_list(bytes: PackedByteArray, start_pos: int) -> Array:
	var len_res: Array = read_var_int(bytes, start_pos)
	var count: int = int(len_res[VALUE])
	var pos: int = int(len_res[1])

	var lobbies: Array = []
	lobbies.resize(count)

	for i in range(count):
		var id_res: Array = read_var_int(bytes, pos)
		var id: int = int(id_res[VALUE])
		pos = int(id_res[1])

		var name_res: Array = read_string(bytes, pos)
		var lobby_name: String = String(name_res[VALUE])
		pos = int(name_res[1])

		var host_id_res: Array = read_var_int(bytes, pos)
		var host_id: int = host_id_res[VALUE]
		pos = host_id_res[NEXT_POS]

		var player_names_res: Array = read_player_names(bytes, pos)
		var player_names: PackedStringArray = player_names_res[VALUE]
		pos = player_names_res[NEXT_POS]

		lobbies[i] = {
			"name": lobby_name,
			"id": id,
			"host_id": host_id,
			"players": player_names
		}

	return [lobbies, pos]


func read_player_sync(bytes: PackedByteArray, start_pos: int) -> Array:
	var host_id_res: Array = read_var_int(bytes, start_pos)
	var host_id: int = host_id_res[VALUE]
	var pos: int = int(host_id_res[NEXT_POS])

	var len_res: Array = read_var_int(bytes, pos)
	var count: int = int(len_res[VALUE])
	pos = int(len_res[NEXT_POS])

	var result: Array = []
	result.resize(count)

	for i in range(count):
		var id_res: Array = read_var_int(bytes, pos)
		var player_id: int = int(id_res[VALUE])
		pos = int(id_res[1])

		var name_res: Array = read_string(bytes, pos)
		var username: String = String(name_res[VALUE])
		pos = int(name_res[1])

		var pos_res: Array = read_position(bytes, pos)
		var position: Vector2 = pos_res[VALUE]
		pos = int(pos_res[1])

		result[i] = {"id": player_id, "username": username, "position": position}

	return [{"players": result, "host_id": host_id}, pos]


func read_position(bytes: PackedByteArray, start_pos: int) -> Array:
	var pos: int = int(start_pos)
	if pos + 4 > bytes.size():
		return [Vector2.ZERO, pos]

	var x: int = (bytes[pos] << 8) | bytes[pos + 1]
	var y: int = (bytes[pos + 2] << 8) | bytes[pos + 3]
	pos += 4
	return [Vector2(x - BITS_15, y - BITS_15), pos]


func read_boolean_from_bytes(bytes: PackedByteArray, start_pos: int) -> Array:
	return [bytes[int(start_pos)] != 0, int(start_pos) + 1]

# -------------------- Data Writers --------------------
# each returns a PackedByteArray that contains the encoded data

func write_var_int(value: int) -> PackedByteArray:
	var v: int = int(value)
	var out: PackedByteArray = PackedByteArray()
	while true:
		var byte: int = v & 0x7F
		v = v >> 7
		if v != 0:
			byte |= 0x80
		out.append(byte)
		if v == 0:
			break
	return out

func write_string(value: String) -> PackedByteArray:
	var text_bytes: PackedByteArray = value.to_utf8_buffer()
	var out: PackedByteArray = PackedByteArray()
	var len_bytes: PackedByteArray = write_var_int(text_bytes.size())
	append_array(out, len_bytes)
	append_array(out, text_bytes)
	return out

func write_position(value: Vector2) -> PackedByteArray:
	# encode x and y as unsigned 16-bit (offset by BITS_15)
	var xi: int = int(value.x) + BITS_15
	var yi: int = int(value.y) + BITS_15
	var out: PackedByteArray = PackedByteArray()
	out.append((xi >> 8) & 0xFF)
	out.append(xi & 0xFF)
	out.append((yi >> 8) & 0xFF)
	out.append(yi & 0xFF)
	return out

func write_boolean(value: bool) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.append(1 if value else 0)
	return out

# -------------------- Helpers --------------------

func append_array(dest: PackedByteArray, src: PackedByteArray) -> void:
	for i in range(src.size()):
		dest.append(src[i])
