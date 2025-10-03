class_name UserInterface
extends CanvasLayer

@onready var lobby_popup: PanelContainer = $Control/PopupsMarginContainer/LobbyPopup
@onready var escape_popup: PanelContainer = $Control/PopupsMarginContainer/EscapePopup
@onready var lobby_popup_button: Button = $Control/MarginContainer/Control/PanelContainer/MarginContainer/HBoxContainer/LobbyPopupButton
@onready var escape_popup_button: Button = $Control/MarginContainer/Control/PanelContainer/MarginContainer/HBoxContainer/EscapePopupButton

func _on_lobby_popup_button_toggled(toggled_on: bool) -> void:
	lobby_popup.visible = toggled_on
	if toggled_on:
		escape_popup.visible = false
		escape_popup_button.button_pressed = false
	
func _on_escape_popup_button_toggled(toggled_on: bool) -> void:
	escape_popup.visible = toggled_on
	if toggled_on:
		lobby_popup.visible = false
		lobby_popup_button.button_pressed = false

func _on_leave_button_pressed() -> void:
	ServerConnection.send_packet(ServerConnection.TCP, PacketUtils.Outgoing.LEAVE_LOBBY)
	get_tree().change_scene_to_file("uid://lp435bqgilpb")
