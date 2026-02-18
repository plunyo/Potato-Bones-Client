extends Control

const ERROR_MESSAGE_SCENE: PackedScene = preload("uid://k12a7effdqt1")
const CONNECTING_TO_SERVER_MESSAGE: String = "Connecting to server..."
const CONNECTED_TO_SERVER_MESSAGE: String = "Connected!"

@export var ip_line_edit: LineEdit
@export var port_line_edit: LineEdit

@onready var error_message_container: VBoxContainer = $ErrorMessageContainer
@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	ServerConnection.disconnected.connect(func(reason: String) -> void: ErrorOverlay.spawn_error("Connection " + reason))
	ServerConnection.connected.connect(_on_server_connection_connected)
	ServerConnection.received_packet.connect(_on_recieved_packet)

func _on_button_pressed() -> void:
	var ip: String = ip_line_edit.text.strip_edges()
	var port_str: String = port_line_edit.text.strip_edges()

	if ip == "":
		ip = ip_line_edit.placeholder_text

	if port_str == "":
		port_str = port_line_edit.placeholder_text

	var port: int
	if port_str.is_valid_int():
		port = int(port_str)
	else:
		ErrorOverlay.spawn_error("Invalid port: '%s'. Using default port 4206" % port_str)
		port = 4206

	ServerConnection.connect_to_server(ip, port)
	status_label.text = CONNECTING_TO_SERVER_MESSAGE

func _on_recieved_packet(packet_id: int, _data: PackedByteArray) -> void:
	if packet_id != PacketUtils.Incoming.SESSION_ID: return
	get_tree().change_scene_to_file("uid://lp435bqgilpb")

func _on_server_connection_connected() -> void:
	status_label.text = CONNECTED_TO_SERVER_MESSAGE

	ServerConnection.send_packet(
		ServerConnection.TCP,
		PacketUtils.Outgoing.REQUEST_SESSION_ID
	)
