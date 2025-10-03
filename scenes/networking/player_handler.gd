extends Node2D

const PLAYER_SCENE: PackedScene = preload("uid://nktph0qyqjgy") as PackedScene

var players: Dictionary[int, Player] = {}

func _ready() -> void:
	ServerConnection.received_packet.connect(_on_received_packet)
	ServerConnection.send_packet(ServerConnection.TCP, PacketUtils.Outgoing.REQUEST_PLAYER_SYNC)

func _on_received_packet(packet_id: int, data: PackedByteArray) -> void:
	match packet_id:
		PacketUtils.Incoming.UPDATE_PLAYERS:
			_handle_player_update(PacketUtils.read_player_update(data).value)
		PacketUtils.Incoming.SYNC_PLAYERS:
			_handle_player_sync(PacketUtils.read_player_sync(data).value)

# helper to create a new player
func _create_player(id: int, username: String = "Anonymous") -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player

	player.id = id
	player.username = username

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
		var rot: float = data.get("rotation", 0.0)
		if id in players:
			players[id].target_position = pos
			players[id].target_rotation = rot
		else:
			_create_player(id, data.get("username", "Anonymous"))

# handle SYNC_PLAYERS packet
func _handle_player_sync(player_list: Array) -> void:
	var synced_ids: Array = []
	
	# first, update or create players
	for data: Dictionary in player_list:
		var id: int = data.get("id")
		if id == null:
			continue

		synced_ids.append(id)
		var username: String = data.get("username", "Anonymous")

		if id in players:
			var existing: Player = players[id]
			existing.username = username
		else:
			_create_player(id, username)

	# then, remove players not in the synced list
	for id in players.keys():
		if id not in synced_ids:
			players[id].queue_free()
			players.erase(id)
