class_name Player
extends CharacterBody2D

const NAME_TAG_OFFSET: Vector2 = Vector2(-86.0, -110.0)
const USER_INTERFACE: PackedScene = preload("uid://c3wm46ftjfvyq") as PackedScene
const CATCH_UP_SPEED: float = 15.0
const SPEED: float = 500

@onready var camera: Camera2D = $Camera
@onready var username_label: Label = $UsernameLabel

@export var id: int = -1
@export var username: String

var target_position: Vector2
var target_rotation: float

var move_packets_sent: int = 0

func _ready() -> void:
	if id == ServerConnection.client_id:
		add_child(USER_INTERFACE.instantiate() as UserInterface)
	username_label.text = username

func _physics_process(delta: float) -> void:
	username_label.global_position = global_position + NAME_TAG_OFFSET

	if id != ServerConnection.client_id:
		global_rotation = lerp(global_rotation, target_rotation, CATCH_UP_SPEED * delta)
		global_position = global_position.lerp(target_position, CATCH_UP_SPEED * delta)
		return

	var input_direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_direction.normalized() * SPEED
	move_and_slide()

	var mouse_pos: Vector2 = get_global_mouse_position()
	var rotation_goal: float = (mouse_pos - global_position).angle() + PI / 2
	global_rotation = lerp_angle(global_rotation, rotation_goal, CATCH_UP_SPEED * delta)

func _on_move_packet_timer_timeout() -> void:
	if id != ServerConnection.client_id: return

	move_packets_sent += 1
	ServerConnection.send_packet(
		ServerConnection.UDP,
		PacketUtils.Outgoing.MOVE,
		PacketUtils.write_var_int(move_packets_sent),
		PacketUtils.write_position(global_position),
		PacketUtils.write_rotation(global_rotation)
	)
