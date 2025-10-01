extends Node

# ----------------------- signals -----------------------
signal connected
signal connection_failed
signal disconnected(reason: String)
signal received_packet(packet_id: int, data: PackedByteArray)
signal client_id_set()

# ----------------------- nodes -----------------------
@onready var poll_timer: Timer = $PollTimer
@onready var deadline_timer: Timer = $DeadlineTimer

# ----------------------- variables -----------------------
var stream: StreamPeerTCP = StreamPeerTCP.new()
var client_id: int
var lobby_info: Dictionary

var _incoming_buffer: PackedByteArray = PackedByteArray()
var _buffer_pos: int = 0
var _has_connected: bool = false

# ----------------------- connection management -----------------------
func connect_to_server(address: String, port: int) -> void:
	if stream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		stream.disconnect_from_host()

	var error: Error = stream.connect_to_host(address, port)
	if error != OK:
		connection_failed.emit()
		return

	poll_timer.start()
	deadline_timer.start()
	stream.set_no_delay(true)


func disconnect_from_server(reason: String) -> void:
	stream.disconnect_from_host()
	poll_timer.stop()
	disconnected.emit(reason)
	_has_connected = false
	get_tree().change_scene_to_file("uid://lp435bqgilpb")


# ----------------------- packet handling -----------------------
func send_packet(packet_id: int, ...data: Array) -> void:
	var id_bytes: PackedByteArray = PacketUtils.write_var_int(packet_id)
	var packet_length: int = id_bytes.size()

	for chunk in data:
		packet_length += PackedByteArray(chunk).size()

	var length_bytes: PackedByteArray = PacketUtils.write_var_int(packet_length)
	var packet: PackedByteArray = PackedByteArray()
	packet.append_array(length_bytes)
	packet.append_array(id_bytes)

	var output_data: PackedByteArray = PackedByteArray()
	for data_chunk: PackedByteArray in data:
		output_data.append_array(data_chunk)

	packet.append_array(output_data)
	stream.put_data(packet)


func _process_incoming_packets(available: int) -> void:
	var chunk: Array = stream.get_data(available)
	if chunk.size() == 2 and chunk[0] == OK:
		_incoming_buffer.append_array(chunk[1])

	while _buffer_pos < _incoming_buffer.size():
		var length_res: Array = PacketUtils.read_var_int(_incoming_buffer, _buffer_pos)
		if not length_res[PacketUtils.FULLY_READ]:
			break

		var packet_length: int = length_res[PacketUtils.VALUE]
		var pos: int = length_res[PacketUtils.NEXT_POS]

		if _incoming_buffer.size() - pos < packet_length:
			break

		var packet_id_res: Array = PacketUtils.read_var_int(_incoming_buffer, pos)
		if not packet_id_res[PacketUtils.FULLY_READ]:
			break

		var packet_id: int = packet_id_res[PacketUtils.VALUE]
		var data_length: int = packet_length - (packet_id_res[PacketUtils.NEXT_POS] - length_res[PacketUtils.NEXT_POS])

		var data: PackedByteArray = _incoming_buffer.slice(
			packet_id_res[PacketUtils.NEXT_POS],
			packet_id_res[PacketUtils.NEXT_POS] + data_length
		)

		received_packet.emit(packet_id, data)
		_buffer_pos = packet_id_res[PacketUtils.NEXT_POS] + data_length

	if _buffer_pos > 0:
		_incoming_buffer = _incoming_buffer.slice(_buffer_pos, _incoming_buffer.size())
		_buffer_pos = 0


# ----------------------- signal callbacks -----------------------
func _on_received_packet(packet_id: int, data: PackedByteArray) -> void:
	match packet_id:
		PacketUtils.Incoming.JOIN_ACCEPT:
			var client_id_res: Array = PacketUtils.read_var_int(data)
			client_id = client_id_res[PacketUtils.VALUE]
			client_id_set.emit()

		PacketUtils.Incoming.JOIN_DENY:
			var deny_reason_res: Array = PacketUtils.read_string(data)
			disconnect_from_server("Join denied: %s" % deny_reason_res[PacketUtils.VALUE])

		PacketUtils.Incoming.PING:
			send_packet(PacketUtils.Outgoing.PONG, data)

		PacketUtils.Incoming.KICK_PLAYER:
			var kick_reason_res: Array = PacketUtils.read_string(data)
			get_tree().change_scene_to_file("uid://lp435bqgilpb")


func _on_poll_timer_timeout() -> void:
	stream.poll()

	match stream.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			if not _has_connected:
				connected.emit()
				_has_connected = true

			var available: int = stream.get_available_bytes()
			if available > 0:
				_process_incoming_packets(available)

		StreamPeerTCP.STATUS_ERROR:
			disconnect_from_server("Connection error occurred. Please try again.")

		StreamPeerTCP.STATUS_NONE:
			disconnect_from_server(
				"Unable to connect: server may not be running or network is unreachable."
			)


func _on_deadline_timer_timeout() -> void:
	if stream.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		disconnect_from_server("Connection timed out")
