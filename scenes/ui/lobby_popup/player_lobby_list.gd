class_name PlayerLobbyList
extends PanelContainer

@onready var username_label: Label = $MarginContainer/HBoxContainer/UsernameLabel
@onready var kick_button: Button = $MarginContainer/HBoxContainer/KickButton
@onready var change_host_button: Button = $MarginContainer/HBoxContainer/ChangeHostButton

var id: int = -1

func set_data(username: String, player_id: int) -> void:
	username_label.text = username
	id = player_id

func set_is_host(is_host: bool) -> void:
	var show_host_controls: bool = is_host and id != ServerConnection.client_id
	kick_button.visible = show_host_controls
	change_host_button.visible = show_host_controls

func _on_kick_button_pressed() -> void:
	ServerConnection.send_packet(
		ServerConnection.TCP,
		PacketUtils.Outgoing.KICK_PLAYER,
		PacketUtils.write_var_int(id),
		PacketUtils.write_string("Kicked by host!")
	)

func _on_change_host_button_pressed() -> void:
	ServerConnection.send_packet(ServerConnection.TCP, PacketUtils.Outgoing.CHANGE_HOST, PacketUtils.write_var_int(id))
