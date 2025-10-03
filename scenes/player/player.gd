class_name Player
extends CharacterBody2D

const POS_TOLERANCE: float = 2.0
const ANGLE_TOLERANCE_DEG: float = 3.0

const NAME_TAG_OFFSET: Vector2 = Vector2(-86.0, -110.0)
const USER_INTERFACE: PackedScene = preload("uid://c3wm46ftjfvyq") as PackedScene
const CATCH_UP_SPEED: float = 15.0
const SPEED: float = 500

@onready var camera: Camera2D = $Camera
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var body: Node2D = $Body

@export var username_label: Label
@export var id: int = -1

var username: String
var last_transform: Transform2D

var target_position: Vector2
var target_rotation: float

var move_packets_sent: int = 0

func _ready() -> void:
	if id == ServerConnection.client_id:
		add_child(USER_INTERFACE.instantiate() as UserInterface)

	last_transform = body.global_transform
	username_label.text = username

func _physics_process(delta: float) -> void:
	if id != ServerConnection.client_id:
		print(id, " ", target_rotation)
		body.global_rotation = lerp_angle(body.global_rotation, target_rotation, CATCH_UP_SPEED * delta)
		global_position = global_position.lerp(target_position, CATCH_UP_SPEED * delta)
		return

	var input_direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_direction.normalized() * SPEED
	move_and_slide()

	if Input.is_action_just_pressed(&"attack"):
		animation_tree.set(&"parameters/attack_oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	animation_tree.set(
		&"parameters/movement_blend/blend_amount",
		lerp(
			animation_tree.get(&"parameters/movement_blend/blend_amount"),
			input_direction.normalized().length(),
			CATCH_UP_SPEED * delta
		)
	)

	var mouse_pos: Vector2 = get_global_mouse_position()
	var rotation_goal: float = (mouse_pos - global_position).angle() + PI / 2
	body.global_rotation = lerp_angle(body.global_rotation, rotation_goal, CATCH_UP_SPEED * delta)

func _on_move_packet_timer_timeout() -> void:
	if id != ServerConnection.client_id:
		return

	var pos_changed: bool = last_transform.get_origin().distance_to(body.global_transform.get_origin()) > POS_TOLERANCE
	var angle_changed: bool = global_rotation_degrees > ANGLE_TOLERANCE_DEG

	# only send if position OR rotation changed enough
	#if not pos_changed and not angle_changed:
	#	return

	move_packets_sent += 1
	ServerConnection.send_packet(
		ServerConnection.UDP,
		PacketUtils.Outgoing.MOVE,
		PacketUtils.write_var_int(move_packets_sent),
		PacketUtils.write_position(global_position),
		PacketUtils.write_rotation(body.global_rotation)
	)

	last_transform = body.global_transform
