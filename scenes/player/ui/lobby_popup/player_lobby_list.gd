class_name PlayerLobbyList
extends PanelContainer

@onready var username_label: Label = $MarginContainer/HBoxContainer/UsernameLabel
@onready var kick_button: Button = $MarginContainer/HBoxContainer/KickButton
@onready var change_host_button: Button = $MarginContainer/HBoxContainer/ChangeHostButton

var id: int

func set_data(username: String, player_id: int, is_host: bool) -> void:
	username_label.text = username
	id = player_id
	kick_button.visible = is_host and id != ServerConnection.client_id
	change_host_button.visible = is_host and id != ServerConnection.client_id

func _on_kick_button_pressed() -> void:
	ServerConnection.send_packet(PacketUtils.Outgoing.KICK_PLAYER, PacketUtils.write_var_int(id))

func _on_change_host_button_pressed() -> void:
	ServerConnection.send_packet(PacketUtils.Outgoing.CHANGE_HOST, PacketUtils.write_var_int(id))
