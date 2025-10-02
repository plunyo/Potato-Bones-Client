class_name LobbyScreen
extends MarginContainer

const LOBBY_SCENE: PackedScene = preload("uid://cfjq5c3jacg7f") as PackedScene

@onready var lobby_container: VBoxContainer = $"VBoxContainer/TabContainer/Join Lobby/VBoxContainer/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/LobbyContainer"
@onready var lobby_name_line_edit: LineEdit = $"VBoxContainer/TabContainer/Create Lobby/VBoxContainer/LobbyNameLineEdit"
@onready var username_line_edit: LineEdit = $VBoxContainer/HBoxContainer/UsernameLineEdit

var username: String = "Anonymous"

func _ready() -> void:
	ServerConnection.received_packet.connect(_on_received_packed)
	request_lobby_list()

func _on_refresh_button_pressed() -> void:
	request_lobby_list()

func request_lobby_list() -> void:
	ServerConnection.send_packet(
		ServerConnection.TCP, 
		PacketUtils.Outgoing.REQUEST_LOBBY_LIST,
	)

func _on_received_packed(packet_id: int, data: PackedByteArray) -> void:
	match packet_id:
		PacketUtils.Incoming.JOIN_ACCEPT:
			get_tree().change_scene_to_file("uid://cu141n04nwv1p")
		PacketUtils.Incoming.LOBBY_LIST:
			for child: Lobby in lobby_container.get_children(): child.queue_free()

			for lobby: Dictionary in PacketUtils.read_lobby_list(data).value:
				var lobby_instance: Lobby = LOBBY_SCENE.instantiate() as Lobby
				lobby_container.add_child(lobby_instance)
				lobby_instance.set_data(lobby.name, lobby.id, lobby.players)
				lobby_instance.join_pressed.connect(_on_join_button_pressed)

func _on_create_lobby_button_pressed() -> void:
	ServerConnection.send_packet(
		ServerConnection.TCP, 
		PacketUtils.Outgoing.CREATE_LOBBY,
		PacketUtils.write_string(username),
		PacketUtils.write_string(
			lobby_name_line_edit.text if !lobby_name_line_edit.text.is_empty() else lobby_name_line_edit.placeholder_text
		)
	)

func _on_join_button_pressed(id: int) -> void:
	ServerConnection.send_packet(
		ServerConnection.TCP, 
		PacketUtils.Outgoing.JOIN,
		PacketUtils.write_string(username),
		PacketUtils.write_var_int(id)
	)

func _on_username_line_edit_text_changed(new_text: String) -> void:
	username = new_text if !new_text.is_empty() else "Anonymous"
	lobby_name_line_edit.placeholder_text = new_text + "'s Lobby" if !new_text.is_empty() else "Anonymous's Lobby"
