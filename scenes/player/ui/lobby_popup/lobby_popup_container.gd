extends PanelContainer

const PLAYER_LOBBY_LIST_SCENE: PackedScene = preload("uid://dyaor04qfmrey")

@onready var player_container: VBoxContainer = $MarginContainer/VBoxContainer/MarginContainer/ScrollContainer/PlayerContainer

func _ready() -> void:
	ServerConnection.received_packet.connect(_on_packet_received)
	ServerConnection.send_packet(PacketUtils.Outgoing.REQUEST_SYNC)

func _on_packet_received(packet_id: int, data: PackedByteArray) -> void:
	if packet_id != PacketUtils.Incoming.SYNC_PLAYERS: return

	var sync_res: Array = PacketUtils.read_player_sync(data)

	for child: Control in player_container.get_children(): child.queue_free()
	for player_data: Dictionary in sync_res[PacketUtils.VALUE].players:
		var player_lobby_instance: PlayerLobbyList  = PLAYER_LOBBY_LIST_SCENE.instantiate()
		player_container.add_child(player_lobby_instance)
		player_lobby_instance.set_data(
			player_data.username, player_data.id,
			ServerConnection.client_id == sync_res[PacketUtils.VALUE].host_id
		)
