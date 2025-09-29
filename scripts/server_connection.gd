extends Node

signal connected
signal disconnected
signal connection_failed

const CONNECT_TIMEOUT: float = 5.0  # seconds

var socket: StreamPeerTCP = StreamPeerTCP.new()
var _is_connected: bool = false
var _is_connecting: bool = false
var _connect_deadline: float = 0.0
var _last_status: int = -1

# -------------------- Connection --------------------

func connect_to_server(ip: String = "pi.plunyo.lol", port: int = 30000) -> void:
	if socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		socket.disconnect_from_host()

	_is_connecting = true
	_is_connected = false
	_connect_deadline = Time.get_ticks_msec() / 1000.0 + CONNECT_TIMEOUT

	var err: Error = socket.connect_to_host(ip, port)
	if err != Error.OK:
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

# -------------------- Process --------------------

func _process(_delta: float) -> void:
	socket.poll()

	var status: int = socket.get_status()
	if status != _last_status:
		print("socket status:", status)
		_last_status = status

	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not _is_connected:
			_is_connected = true
			_is_connecting = false
			print("connected")
			emit_signal("connected")

			# send handshake / initial packet
			var out := PackedByteArray([0x01, 0x00])
			socket.put_data(out)

	elif status == StreamPeerTCP.STATUS_CONNECTING:
		if _is_connecting and (Time.get_ticks_msec() / 1000.0) > _connect_deadline:
			print("connection timed out")
			_is_connecting = false
			socket.disconnect_from_host()
			emit_signal("connection_failed")

	elif status == StreamPeerTCP.STATUS_ERROR:
		if _is_connecting or _is_connected:
			_is_connecting = false
			_is_connected = false
			print("connection failed (status error)")
			emit_signal("connection_failed")

	# process incoming bytes
	if _is_connected and socket.get_available_bytes() > 0:
		_process_incoming()

# -------------------- Incoming --------------------

func _process_incoming() -> void:
	while socket.get_available_bytes() > 0:
		var b: int = socket.get_u8()
		# handle packet parsing here
		print("received byte:", b)

# -------------------- Data Readers --------------------

const BITS_15: int = pow(2, 15)

func read_var_int() -> int:
	var num: int = 0
	var shift: int = 0
	while true:
		var byte: int = socket.get_u8()
		num |= (byte & 0x7F) << shift
		if (byte & 0x80) == 0:
			break
		shift += 7
	return num

func read_string() -> String:
	var length: int = read_var_int()
	var bytes: PackedByteArray = socket.get_data(length)
	return bytes.get_string_from_utf8()

func read_position() -> Vector2:
	var bytes: PackedByteArray = socket.get_data(4)
	var x: int = (bytes[0] << 8) | bytes[1]
	var y: int = (bytes[2] << 8) | bytes[3]
	return Vector2(x - BITS_15, y - BITS_15)

func read_boolean() -> bool:
	return socket.get_u8() != 0
