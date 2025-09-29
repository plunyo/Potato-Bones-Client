extends Node2D

const PLAYER_SCENE: PackedScene = preload("uid://nktph0qyqjgy") as PackedScene

var players: Dictionary[int, Player] = {}

func _ready() -> void:
	ServerConnection.received_packet.connect(_on_received_packet)

func _on_received_packet(packet_id: int, data: PackedByteArray) -> void:
	match packet_id:
		ServerConnection.PacketID.Incoming.UPDATE_PLAYERS:
			for player_data in ServerConnection.read_player_update(data, 0).value:
				var id = player_data.get("id")
				if id == ServerConnection.client_id:
					continue

				var pos = player_data.get("position", Vector2.ZERO)

				if id in players:
					# update existing player smoothly
					players[id].target_position = pos
				else:
					# create new player instance
					var new_player := PLAYER_SCENE.instantiate() as Player
					new_player.id = id
					new_player.global_position = pos
					new_player.target_position = pos  # initialize target
					players[id] = new_player
					add_child(new_player)

		ServerConnection.PacketID.Incoming.SYNC_PLAYERS:
			for player_data in ServerConnection.read_player_sync(data, 0).value:
				var id = player_data.get("id")
				if id == null:
					continue

				var username = player_data.get("username", "Anonymous")
				var net_position = player_data.get("position", Vector2.ZERO)

				if id in players:
					# update existing player
					var existing := players[id]
					existing.username = username
					if id != ServerConnection.client_id:
						existing.target_position = net_position
				else:
					# create new player instance
					var player_instance := PLAYER_SCENE.instantiate() as Player
					player_instance.id = id
					player_instance.username = username
					player_instance.global_position = net_position
					player_instance.target_position = net_position
					players[id] = player_instance
					add_child(player_instance)
					player_instance.camera.enabled = id == ServerConnection.client_id
