extends Node


class PacketID:
	enum Outgoing {
		JOIN =  0x00,
		MOVE = 0x01,
		PING = 0x02,
		PONG = 0x03,
		REQUEST_SYNC = 0x04
	}
	enum Incoming {
		JOIN_ACCEPT = 0x00,
		JOIN_DENY = 0x01,
		PING = 0x02,
		PONG = 0x03,
		UPDATE_PLAYERS = 0x04,
		SYNC_PLAYERS = 0x05
	}

signal connected
signal disconnected
signal connection_failed
signal received_packet(packet_id: PacketID.Incoming, data: PackedByteArray)

const CONNECT_TIMEOUT: float = 5.0  # seconds
const BITS_15: int = 1 << 15

var _is_connected: bool = false
var _is_connecting: bool = false
var _connect_deadline: float = 0.0
var _last_status: int = -1

var socket: StreamPeerTCP = StreamPeerTCP.new()
var players: Array[Dictionary] = []
var client_id: int = -1

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
		var available = socket.get_available_bytes()
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

var incoming_buffer: PackedByteArray = PackedByteArray()

func _process_incoming() -> void:
	# append incoming bytes using helper (not as a method)
	var available := socket.get_available_bytes()
	if available > 0:
		var chunk: Array = socket.get_data(available)
		if chunk[0] == OK:
			incoming_buffer.append_array(chunk[1])

	var pos: int = 0

	while true:
		# need at least one byte to read a varint length
		if pos >= incoming_buffer.size():
			break

		var len_res = read_var_int(incoming_buffer, pos)
		if not len_res.complete:
			# incomplete length varint — wait for more bytes
			break

		var packet_length = len_res.value
		pos = len_res.next_pos

		# now we need to ensure the whole payload (packet_length bytes) is available
		if incoming_buffer.size() - pos < packet_length:
			# not enough bytes yet
			break

		# read packet id varint
		var id_res = read_var_int(incoming_buffer, pos)
		if not id_res.complete:
			# this shouldn't normally happen because we already checked packet_length,
			# but be defensive
			break

		var packet_id = id_res.value
		# header bytes is size of the packet_id varint
		var header_bytes = id_res.next_pos - len_res.next_pos
		var data_length = packet_length - header_bytes
		var data = slice_bytes(incoming_buffer, id_res.next_pos, id_res.next_pos + data_length)

		# advance pos to after this packet
		pos = id_res.next_pos + data_length

		# handle packet
		handle_packet(packet_id, data)

	# drop processed bytes
	if pos > 0:
		incoming_buffer = slice_bytes(incoming_buffer, pos, incoming_buffer.size())

# -------------------- Packet Handling --------------------

func send_packet(packet_id: int, data: PackedByteArray) -> void:
	# build packet: [varint packet_length][varint packet_id][data...]
	var id_bytes: PackedByteArray = write_var_int(packet_id)
	var payload_len: int = id_bytes.size() + data.size()
	var len_bytes: PackedByteArray = write_var_int(payload_len)

	var out: PackedByteArray = PackedByteArray()
	append_array(out, len_bytes)
	append_array(out, id_bytes)
	append_array(out, data)
	socket.put_data(out)

func handle_packet(packet_id: int, data: PackedByteArray) -> void:
	print("id: ", packet_id, ", data: ", data)
	received_packet.emit(packet_id, data)
	match packet_id:
		PacketID.Incoming.JOIN_ACCEPT:  # join accept
			client_id = read_var_int(data, 0).value
		PacketID.Incoming.JOIN_DENY:  # join deny
			var res = read_string(data, 0)
			print("join denied: %s" % res.value)
		PacketID.Incoming.UPDATE_PLAYERS:
			pass
		PacketID.Incoming.SYNC_PLAYERS:
			pass
		_:
			print("unknown packet id: %s (data size %d)" % [packet_id, data.size()])

# -------------------- Data Readers --------------------
# all return a dictionary: { "value": <parsed>, "next_pos": <int> }

func read_var_int(bytes: PackedByteArray, start_pos: int) -> Dictionary:
	var num: int = 0
	var shift: int = 0
	var pos: int = start_pos
	var complete: bool = false

	while pos < bytes.size():
		var byte: int = bytes[pos]
		num |= (byte & 0x7F) << shift
		pos += 1
		if (byte & 0x80) == 0:
			complete = true
			break
		shift += 7
		# guard against overly large/invalid varints
		if shift > 35:
			break

	return {"value": num, "next_pos": pos, "complete": complete}

func slice_bytes(bytes: PackedByteArray, start: int, end_exclusive: int) -> PackedByteArray:
	var out := PackedByteArray()
	if start < 0:
		start = 0
	if end_exclusive > bytes.size():
		end_exclusive = bytes.size()
	for i in range(start, end_exclusive):
		out.append(bytes[i])
	return out

func read_string(bytes: PackedByteArray, start_pos: int) -> Dictionary:
	var len_res = read_var_int(bytes, start_pos)
	var length = len_res.value
	var pos = len_res.next_pos
	var str_bytes = slice_bytes(bytes, pos, pos + length)
	return {"value": str_bytes.get_string_from_utf8(), "next_pos": pos + length}

func read_player_update(bytes: PackedByteArray, start_pos: int) -> Dictionary:
	var len_res = read_var_int(bytes, start_pos)
	var count = len_res.value
	var pos = len_res.next_pos
	
	for i in range(count):
		# read client id
		var id_res = read_var_int(bytes, pos)
		var other_player_client_id = id_res.value
		pos = id_res.next_pos

		# read position
		var pos_res = read_position(bytes, pos)
		var position = pos_res.value
		pos = pos_res.next_pos
		
		players.append({
			"id": other_player_client_id,
			"position": position
		})
	
	return {"value": players, "next_pos": pos}

func read_player_sync(bytes: PackedByteArray, start_pos: int) -> Dictionary:
	var len_res = read_var_int(bytes, start_pos)
	var count = len_res.value
	var pos = len_res.next_pos
	
	for i in range(count):
		# read client id
		var id_res = read_var_int(bytes, pos)
		var other_player_client_id = id_res.value
		pos = id_res.next_pos
		
		# read username
		var name_res = read_string(bytes, pos)
		var username = name_res.value
		pos = name_res.next_pos
		
		# read position
		var pos_res = read_position(bytes, pos)
		var position = pos_res.value
		pos = pos_res.next_pos
		
		players.append({
			"id": other_player_client_id,
			"username": username,
			"position": position
		})
	
	return {"value": players, "next_pos": pos}


func read_position(bytes: PackedByteArray, start_pos: int) -> Dictionary:
	var pos = start_pos
	if pos + 4 > bytes.size():
		return {"value": Vector2.ZERO, "next_pos": pos} # defensive
	var x = (bytes[pos] << 8) | bytes[pos + 1]
	var y = (bytes[pos + 2] << 8) | bytes[pos + 3]
	pos += 4
	return {"value": Vector2(x - BITS_15, y - BITS_15), "next_pos": pos}

func read_boolean_from_bytes(bytes: PackedByteArray, start_pos: int) -> Dictionary:
	return {"value": bytes[start_pos] != 0, "next_pos": start_pos + 1}

# -------------------- Data Writers --------------------
# each returns a PackedByteArray that contains the encoded data

func write_var_int(value: int) -> PackedByteArray:
	var v: int = value
	var out := PackedByteArray()
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
	var out := PackedByteArray()
	var len_bytes = write_var_int(text_bytes.size())
	append_array(out, len_bytes)
	append_array(out, text_bytes)
	return out

func write_position(value: Vector2) -> PackedByteArray:
	# encode x and y as unsigned 16-bit (offset by BITS_15)
	var xi: int = int(value.x) + BITS_15
	var yi: int = int(value.y) + BITS_15
	var out := PackedByteArray()
	out.append((xi >> 8) & 0xFF)
	out.append(xi & 0xFF)
	out.append((yi >> 8) & 0xFF)
	out.append(yi & 0xFF)
	return out

func write_boolean(value: bool) -> PackedByteArray:
	var out := PackedByteArray()
	out.append(1 if value else 0)
	return out

# -------------------- Helpers --------------------

func append_array(dest: PackedByteArray, src: PackedByteArray) -> void:
	for i in range(src.size()):
		dest.append(src[i])
