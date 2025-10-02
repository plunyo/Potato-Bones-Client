extends PanelContainer

const PLAYER_LOBBY_LIST_SCENE: PackedScene = preload("uid://dyaor04qfmrey")

@onready var player_container: VBoxContainer = $MarginContainer/VBoxContainer/MarginContainer/ScrollContainer/PlayerContainer
@onready var lobby_name_label: Label = $MarginContainer/VBoxContainer/LobbyNameLabel
@onready var lobby_id_label: Label = $MarginContainer/VBoxContainer/LobbyNameLabel/LobbyIDLabel

func _ready() -> void:
	ServerConnection.received_packet.connect(_on_packet_received)
	ServerConnection.send_packet(ServerConnection.TCP, PacketUtils.Outgoing.REQUEST_PLAYER_SYNC)
	ServerConnection.send_packet(ServerConnection.TCP, PacketUtils.Outgoing.REQUEST_LOBBY_SYNC)

func _on_packet_received(packet_id: int, data: PackedByteArray) -> void:
	match packet_id:
		PacketUtils.Incoming.LOBBY_SYNC:
			var lobby_info_res: PacketUtils.ReadResult = PacketUtils.read_lobby_sync(data)
			var lobby_info: Dictionary = lobby_info_res.value

			lobby_name_label.text = lobby_info.lobby_name
			lobby_id_label.text = "ID: " + str(lobby_info.lobby_id)

			for child: PlayerLobbyList in player_container.get_children():
				child.set_is_host(lobby_info.host_id == ServerConnection.client_id)

		PacketUtils.Incoming.SYNC_PLAYERS:
			var sync_res: PacketUtils.ReadResult = PacketUtils.read_player_sync(data)

			for child: PlayerLobbyList in player_container.get_children(): child.queue_free()

			for player_data: Dictionary in sync_res.value:
				var player_lobby_instance: PlayerLobbyList = PLAYER_LOBBY_LIST_SCENE.instantiate()
				player_container.add_child(player_lobby_instance)
				player_lobby_instance.set_data(player_data.username, player_data.id)
				if ServerConnection.lobby_info.has("host_id"):
					player_lobby_instance.set_is_host(ServerConnection.lobby_info.host_id == ServerConnection.client_id)
