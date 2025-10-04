extends Node

# ----------------------- enums -----------------------
enum { TCP, UDP }

# ----------------------- signals -----------------------
signal connected
signal connection_failed
signal disconnected(reason: String)
signal received_packet(packet_id: int, data: PackedByteArray)

# ----------------------- nodes -----------------------
@onready var poll_timer: Timer = $PollTimer
@onready var deadline_timer: Timer = $DeadlineTimer

# ----------------------- variables -----------------------
var tcp_stream: StreamPeerTCP = StreamPeerTCP.new()
var udp_socket: PacketPeerUDP = PacketPeerUDP.new()
var lobby_info: Dictionary
var session_id: String
var client_id: int

var _incoming_buffer: PackedByteArray = PackedByteArray()
var _has_connected: bool = false

# ----------------------- connection management -----------------------
func connect_to_server(address: String, port: int) -> void:
	udp_socket.set_dest_address(address, port)
	var err = udp_socket.bind(0)
	if err != OK:
		push_error("failed to bind udp socket: %s" % err)

	if tcp_stream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		tcp_stream.disconnect_from_host()

	var error: Error = tcp_stream.connect_to_host(address, port)
	if error != OK:
		connection_failed.emit()
		return

	poll_timer.start()
	deadline_timer.start()
	tcp_stream.set_no_delay(true)

func disconnect_from_server(reason: String) -> void:
	tcp_stream.disconnect_from_host()
	poll_timer.stop()
	disconnected.emit(reason)
	print("reason: ", reason)
	_has_connected = false
	get_tree().change_scene_to_file("res://scenes/menus/connect/connect_screen.tscn")

# ----------------------- packet handling -----------------------
func send_packet(protocol: int, packet_id: int, ...data: Array) -> void:
	# build id + payload
	var id_bytes: PackedByteArray = PacketUtils.write_var_int(packet_id)
	var packet_length: int = id_bytes.size()

	for chunk in data:
		packet_length += PackedByteArray(chunk).size()

	var length_bytes: PackedByteArray = PacketUtils.write_var_int(packet_length)

	# if UDP we prefix session_id bytes (your original intent). keep it clear.
	var packet: PackedByteArray = PackedByteArray()
	if protocol == UDP:
		if session_id == null:
			push_error("send_packet: session_id is null when sending UDP")
		else:
			packet.append_array(PacketUtils.write_string(session_id))

	packet.append_array(length_bytes)
	packet.append_array(id_bytes)

	var output_data: PackedByteArray = PackedByteArray()
	for d in data:
		output_data.append_array(PackedByteArray(d))

	packet.append_array(output_data)

	match protocol:
		TCP:
			var err = tcp_stream.put_data(packet)
			if err != OK:
				push_error("tcp put_data failed: %s" % err)
		UDP:
			var err = udp_socket.put_packet(packet)
			if err != OK:
				push_error("udp put_packet failed: %s" % err)


func _process_packet(packet: PackedByteArray) -> void:
	# make sure we start at 0
	var buffer_pos: int = 0

	while buffer_pos < packet.size():
		var length_res = PacketUtils.read_var_int(packet, buffer_pos)
		if not length_res.is_fully_read():
			break

		var packet_length = length_res.value
		var pos = length_res.next_pos

		# not enough bytes for the declared length
		if packet.size() - pos < packet_length:
			break

		var packet_id_res = PacketUtils.read_var_int(packet, pos)
		if not packet_id_res.is_fully_read():
			break

		var packet_id = packet_id_res.value
		var data_length = packet_length - (packet_id_res.next_pos - length_res.next_pos)
		var data = packet.slice(packet_id_res.next_pos, packet_id_res.next_pos + data_length)

		received_packet.emit(packet_id, data)
		buffer_pos = packet_id_res.next_pos + data_length


func _process_incoming_packets(available: int) -> void:
	if available > 0:
		var chunk = tcp_stream.get_data(available)
		if typeof(chunk) == TYPE_ARRAY and chunk.size() == 2 and chunk[0] == OK:
			_incoming_buffer.append_array(chunk[1])
			# only clear if processing consumed everything
			var before_size = _incoming_buffer.size()
			_process_packet(_incoming_buffer)
			# if everything parsed, clear buffer
			# (this is heuristic; keep leftover data if we didn't consume all bytes)
			if _incoming_buffer.size() == before_size:
				_incoming_buffer.clear()
		else:
			# either no data or error
			if typeof(chunk) == TYPE_ARRAY:
				push_error("tcp get_data error: %s" % chunk[0])

# ----------------------- signal callbacks -----------------------
func _on_received_packet(packet_id: int, data: PackedByteArray) -> void:
	match packet_id:
		PacketUtils.Incoming.JOIN_ACCEPT:
			var client_id_res: PacketUtils.ReadResult = PacketUtils.read_var_int(data)
			client_id = client_id_res.value

		PacketUtils.Incoming.SESSION_ID:
			var session_id_res: PacketUtils.ReadResult = PacketUtils.read_string(data)
			session_id = session_id_res.value

		PacketUtils.Incoming.JOIN_DENY:
			var deny_reason_res: PacketUtils.ReadResult = PacketUtils.read_string(data)
			disconnect_from_server("Join denied: %s" % deny_reason_res.value)

		PacketUtils.Incoming.PING:
			send_packet(TCP, PacketUtils.Outgoing.PONG, data)

		PacketUtils.Incoming.KICK_PLAYER:
			var kick_reason_res: PacketUtils.ReadResult = PacketUtils.read_string(data)
			print(kick_reason_res.value)
			get_tree().change_scene_to_file("uid://lp435bqgilpb")


func _on_poll_timer_timeout() -> void:
	# --- UDP ---
	while udp_socket.get_available_packet_count() > 0:
		var packet: PackedByteArray = udp_socket.get_packet()
		_process_packet(packet)

	# TCP
	tcp_stream.poll()

	match tcp_stream.get_status():
		StreamPeerTCP.STATUS_CONNECTED:
			if not _has_connected:
				connected.emit()
				_has_connected = true

			var available: int = tcp_stream.get_available_bytes()
			if available > 0:
				_process_incoming_packets(available)

		StreamPeerTCP.STATUS_ERROR:
			disconnect_from_server("Connection error occurred. Please try again.")

		StreamPeerTCP.STATUS_NONE:
			disconnect_from_server(
				"Unable to connect: server may not be running or network is unreachable."
			)


func _on_deadline_timer_timeout() -> void:
	if tcp_stream.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		disconnect_from_server("Connection timed out")
