extends Node2D

const PLAYER_SCENE: PackedScene = preload("uid://nktph0qyqjgy") as PackedScene

var players: Dictionary[int, Player] = {}

func _ready() -> void:
	ServerConnection.received_packet.connect(_on_received_packet)

func _on_received_packet(packet_id: int, data: PackedByteArray) -> void:
	match packet_id:
		ServerConnection.PacketID.Incoming.UPDATE_PLAYERS:
			_handle_player_update(ServerConnection.read_player_update(data, 0).value)
		ServerConnection.PacketID.Incoming.SYNC_PLAYERS:
			_handle_player_sync(ServerConnection.read_player_sync(data, 0).value)

# helper to create a new player
func _create_player(id: int, net_position: Vector2, username: String = "Anonymous") -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.id = id
	player.username = username
	player.global_position = net_position
	player.target_position = net_position
	player.camera.enabled = id == ServerConnection.client_id
	add_child(player)
	players[id] = player
	return player

# handle UPDATE_PLAYERS packet
func _handle_player_update(player_list: Array) -> void:
	for data in player_list:
		var id = data.get("id")
		if id == ServerConnection.client_id:
			continue

		var pos = data.get("position", Vector2.ZERO)
		if id in players:
			players[id].target_position = pos
		else:
			_create_player(id, pos)

# handle SYNC_PLAYERS packet
func _handle_player_sync(player_list: Array) -> void:
	for data in player_list:
		var id = data.get("id")
		if id == null:
			continue

		var username = data.get("username", "Anonymous")
		var pos = data.get("position", Vector2.ZERO)

		if id in players:
			var existing := players[id]
			existing.username = username
			if id != ServerConnection.client_id:
				existing.target_position = pos
		else:
			_create_player(id, pos, username)
