extends Node2D

const PLAYER_SCENE: PackedScene = preload("uid://nktph0qyqjgy") as PackedScene

var players: Dictionary[int, Player] = {}

func _ready() -> void:
	ServerConnection.received_packet.connect(_on_received_packet)
	ServerConnection.send_packet(PacketUtils.Outgoing.REQUEST_SYNC)

func _on_received_packet(packet_id: int, data: PackedByteArray) -> void:
	match packet_id:
		PacketUtils.Incoming.UPDATE_PLAYERS:
			_handle_player_update(PacketUtils.read_player_update(data, 0)[0])
		PacketUtils.Incoming.SYNC_PLAYERS:
			_handle_player_sync(PacketUtils.read_player_sync(data, 0)[0].players)

# helper to create a new player
func _create_player(id: int, net_position: Vector2, username: String = "Anonymous") -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player

	player.id = id
	player.username = username
	player.global_position = net_position
	player.target_position = net_position

	add_child(player)
	player.camera.enabled = id == ServerConnection.client_id

	players[id] = player
	return player

# handle UPDATE_PLAYERS packet
func _handle_player_update(player_list: Array) -> void:
	for data: Dictionary in player_list:
		var id: int = data.get("id")
		if id == ServerConnection.client_id:
			continue

		var pos: Vector2 = data.get("position", Vector2.ZERO)
		if id in players:
			players[id].target_position = pos
		else:
			_create_player(id, pos)

# handle SYNC_PLAYERS packet
func _handle_player_sync(player_list: Array) -> void:
	for data: Dictionary in player_list:
		var id: int = data.get("id")
		if id == null:
			continue

		var username: String = data.get("username", "Anonymous")
		var pos: Vector2 = data.get("position", Vector2.ZERO)

		if id in players:
			var existing: Player = players[id]
			existing.username = username
			if id != ServerConnection.client_id:
				existing.target_position = pos
		else:
			_create_player(id, pos, username)
