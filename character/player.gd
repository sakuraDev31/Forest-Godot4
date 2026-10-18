class_name Player
extends CharacterBody3D

## 3D Survivor Character Controller for Godot 4.7 Mobile
## Supports both Animated Anime Survivor Model and Mannequin Model
## Features Third-Person SpringArm / First-Person Camera, Touch Controls & Keyboard

signal stamina_changed(current: float, max_val: float)
signal health_changed(current: float, max_val: float)

@export_group("Model Options")
@export_enum("AnimeSurvivor", "Mannequin") var model_type: String = "AnimeSurvivor"

@export_group("Movement")
@export var speed_walk: float = 3.5
@export var speed_run: float = 6.0
@export var speed_sprint: float = 9.0
@export var speed_crouch: float = 2.0
@export var turn_rate: float = 12.0

@export_group("Physics")
@export var gravity: float = 20.0
@export var jump_velocity: float = 7.5
@export var coyote_time_max: float = 0.15
@export var jump_buffer_max: float = 0.15

@export_group("Camera")
@export var mouse_sensitivity: float = 0.003
@export var touch_sensitivity: float = 0.005
@export var min_pitch: float = -75.0
@export var max_pitch: float = 75.0
@export var default_spring_length: float = 3.5

# Runtime State
var health: float = 100.0
var max_health: float = 100.0
var stamina: float = 100.0
var max_stamina: float = 100.0

var is_sprinting: bool = false
var is_crouching: bool = false
var is_first_person: bool = false

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0

var _pitch: float = 0.0
var _yaw: float = 0.0
var external_move_vector: Vector2 = Vector2.ZERO

# Model & Rig references
var player_model: Node3D = null
var player_animator: RefCounted = null
var mannequin_instance: Node3D = null

const PlayerModelScript = preload("res://character/player_model.gd")
const PlayerAnimatorScript = preload("res://character/player_animator.gd")
const MannequinGLB = preload("res://character/dummy_refrence.glb")

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var visual_mesh: Node3D = $VisualMesh
@onready var camera_rig: Node3D = $CameraRig
@onready var spring_arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var touch_hud: CanvasLayer = get_node_or_null("TouchHUD")

func _ready() -> void:
	add_to_group("player")
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(45.0)
	
	# Mouse capture on desktop / web
	if not OS.has_feature("mobile"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Setup character model
	_setup_model(model_type)
	
	# Setup touch controls if TouchHUD exists
	if touch_hud and touch_hud.has_node("TouchControls"):
		var tc = touch_hud.get_node("TouchControls")
		if tc.has_method("setup"):
			tc.setup(self)

func _setup_model(type: String) -> void:
	if not visual_mesh:
		return
		
	# Clear previous visual children
	for child in visual_mesh.get_children():
		child.queue_free()
		
	player_model = null
	player_animator = null
	mannequin_instance = null
	
	if type == "AnimeSurvivor":
		player_model = PlayerModelScript.new()
		visual_mesh.add_child(player_model)
		player_animator = PlayerAnimatorScript.new(player_model)
	elif type == "Mannequin":
		if MannequinGLB:
			mannequin_instance = MannequinGLB.instantiate()
			mannequin_instance.scale = Vector3(1.0, 1.0, 1.0)
			visual_mesh.add_child(mannequin_instance)

func toggle_model() -> void:
	if model_type == "AnimeSurvivor":
		model_type = "Mannequin"
	else:
		model_type = "AnimeSurvivor"
	_setup_model(model_type)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		apply_look_delta(Vector2(event.relative.x * mouse_sensitivity, event.relative.y * mouse_sensitivity))
		
	# Hotkeys
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif event.keycode == KEY_V:
			toggle_camera_mode()
		elif event.keycode == KEY_M:
			toggle_model()
		elif event.keycode == KEY_C:
			toggle_crouch()

func apply_look_delta(delta: Vector2) -> void:
	_yaw -= delta.x
	_pitch -= delta.y
	_pitch = clampf(_pitch, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	
	# Rotate camera rig
	if camera_rig:
		camera_rig.rotation = Vector3(_pitch, _yaw, 0.0)

func toggle_camera_mode() -> void:
	is_first_person = not is_first_person
	if spring_arm and camera:
		if is_first_person:
			spring_arm.spring_length = 0.0
			camera.position = Vector3(0, 0.1, -0.2)
			if visual_mesh:
				visual_mesh.visible = false
		else:
			spring_arm.spring_length = default_spring_length
			camera.position = Vector3.ZERO
			if visual_mesh:
				visual_mesh.visible = true

func toggle_crouch() -> void:
	is_crouching = not is_crouching
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var cap = collision_shape.shape as CapsuleShape3D
		if is_crouching:
			cap.height = 1.1
			collision_shape.position.y = 0.55
		else:
			cap.height = 1.8
			collision_shape.position.y = 0.9

func trigger_jump() -> void:
	jump_buffer_timer = jump_buffer_max

func set_touch_sprint(sprinting: bool) -> void:
	is_sprinting = sprinting

func _physics_process(delta: float) -> void:
	# 1. Update Coyote and Jump Buffer Timers
	if is_on_floor():
		coyote_timer = coyote_time_max
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)
		
	jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)
	
	# 2. Gather Movement Input (Keyboard + Virtual Joystick)
	var input_vec = _get_input_vector()
	
	# Check sprinting
	var sprint_pressed = Input.is_key_pressed(KEY_SHIFT) or is_sprinting
	
	# Determine speed
	var current_speed = speed_walk
	if is_crouching:
		current_speed = speed_crouch
	elif sprint_pressed and input_vec.length_squared() > 0.01:
		current_speed = speed_sprint
	
	# 3. Calculate 3D movement direction relative to camera rig yaw
	var move_dir = Vector3.ZERO
	if input_vec.length_squared() > 0.001:
		var cam_rot_y = camera_rig.rotation.y if camera_rig else 0.0
		var forward = Vector3(sin(cam_rot_y), 0, cos(cam_rot_y))
		var right = Vector3(cos(cam_rot_y), 0, -sin(cam_rot_y))
		move_dir = (right * input_vec.x + forward * (-input_vec.y)).normalized()
		
		# Rotate visual mesh smoothly to face movement direction
		if visual_mesh and visual_mesh.visible:
			var target_rot_y = atan2(move_dir.x, move_dir.z)
			visual_mesh.rotation.y = lerp_angle(visual_mesh.rotation.y, target_rot_y, delta * turn_rate)
	
	# 4. Horizontal velocity
	velocity.x = move_dir.x * current_speed
	velocity.z = move_dir.z * current_speed
	
	# 5. Gravity & Jumping
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1 # Slight downward ground clamping
		
	# Check jump input
	if Input.is_key_pressed(KEY_SPACE) or Input.is_action_just_pressed("jump"):
		trigger_jump()
		
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = jump_velocity
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
	
	# 6. Apply Movement with Ground Snapping
	move_and_slide()
	
	# 7. Update Procedural Animation
	if player_animator:
		player_animator.update(delta, velocity, is_on_floor(), is_crouching, sprint_pressed)

func _get_input_vector() -> Vector2:
	var v = external_move_vector
	
	# Add keyboard inputs
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("move_forward"):
		v.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("move_backward"):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("move_left"):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("move_right"):
		v.x += 1.0
		
	if v.length_squared() > 1.0:
		v = v.normalized()
		
	return v
