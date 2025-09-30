class_name Lobby
extends PanelContainer

signal join_pressed(id: int)

@onready var lobby_name_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/LobbyNameLabel
@onready var lobby_id_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/HBoxContainer/LobbyIDLabel
@onready var players_label: Label = $MarginContainer/HBoxContainer/VBoxContainer/HBoxContainer/PlayersLabel

var id: int

func set_data(lobby_name: String, lobby_id: int, players: PackedStringArray) -> void:
	lobby_name_label.text = lobby_name
	lobby_id_label.text = str(lobby_id)
	id = lobby_id
	players_label.text = ", ".join(players)

func _on_join_button_pressed() -> void:
	join_pressed.emit(id)
