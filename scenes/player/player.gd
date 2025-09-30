class_name Player
extends CharacterBody2D

const CATCH_UP_SPEED: float = 15.0
const SPEED: float = 500

@onready var camera: Camera2D = $Camera
@onready var username_label: Label = $UsernameLabel

@export var id: int = -1
@export var username: String

var target_position: Vector2

func _ready() -> void:
	ServerConnection.disconnected.connect(
		func() -> void:
			get_tree().change_scene_to_file("res://scenes/join_screen.tscn")
	)

	username_label.text = username

func _physics_process(delta: float) -> void:
	print(Engine.get_frames_per_second())
	if id != ServerConnection.client_id:
		global_position = global_position.lerp(target_position, CATCH_UP_SPEED * delta)
		return

	var input_direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_direction.normalized() * SPEED
	move_and_slide()

func _on_move_packet_timer_timeout() -> void:
	if id != ServerConnection.client_id: return

	ServerConnection.send_packet(
		PacketID.Outgoing.MOVE,
		ServerConnection.write_position(global_position)
	)
