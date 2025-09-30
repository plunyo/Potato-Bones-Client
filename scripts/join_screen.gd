extends Control

const ERROR_MESSAGE_SCENE: PackedScene = preload("uid://k12a7effdqt1")
const CONNECTING_TO_SERVER_MESSAGE: String = "Connecting to server..."
const CONNECTED_TO_SERVER_MESSAGE: String = "Connected!"

@export var ip_line_edit: LineEdit
@export var port_line_edit: LineEdit

@onready var error_message_container: VBoxContainer = $ErrorMessageContainer
@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	ServerConnection.disconnected.connect(func() -> void: spawn_error("Connection failed."))
	ServerConnection.connected.connect(func() -> void:
		status_label.text = CONNECTED_TO_SERVER_MESSAGE
		get_tree().change_scene_to_packed(preload("uid://lp435bqgilpb") as PackedScene)
	)

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
		spawn_error("Invalid port: '%s'. Using default port 30000" % port_str)
		port = 30000

	ServerConnection.connect_to_server(ip, port)
	status_label.text = CONNECTING_TO_SERVER_MESSAGE

func spawn_error(message: String) -> void:
	status_label.text = ""
	var error_message_instance: Label = ERROR_MESSAGE_SCENE.instantiate() as Label
	error_message_instance.text = message
	error_message_container.add_child(error_message_instance)
