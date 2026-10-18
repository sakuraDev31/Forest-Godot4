class_name DrivableCar
extends CharacterBody3D

## High-Performance Driveable Vehicle for Godot 4.7 Mobile
## Features arcade vehicle physics, visual wheel steering/rotation, 
## chassis roll/pitch suspension feel, and seamless Player Enter/Exit interaction.

signal player_entered
signal player_exited

@export_group("Vehicle Stats")
@export var max_speed: float = 24.0          # Max forward speed (m/s)
@export var reverse_speed: float = 8.0        # Max reverse speed
@export var acceleration: float = 16.0       # Forward acceleration
@export var braking: float = 24.0            # Braking force
@export var steer_speed: float = 3.5         # Steering responsiveness
@export var max_steer_angle: float = 0.55    # Max wheel turn angle in radians (~32 deg)
@export var lateral_grip: float = 8.5        # Lateral tire traction (higher = less drift)
@export var gravity: float = 20.0            # Gravity force

# State
var is_driven: bool = false
var current_steer_angle: float = 0.0
var forward_speed: float = 0.0
var driver_ref: CharacterBody3D = null

# Mobile input vector from TouchHUD
var mobile_steer: float = 0.0
var mobile_throttle: float = 0.0

# Node references
var car_mesh: Node3D = null
var wheel_fl: Node3D = null
var wheel_fr: Node3D = null
var wheel_bl: Node3D = null
var wheel_br: Node3D = null
@onready var spring_arm: SpringArm3D = get_node_or_null("SpringArm3D")
@onready var chase_camera: Camera3D = get_node_or_null("SpringArm3D/Camera3D")
@onready var interact_area: Area3D = get_node_or_null("InteractArea")
@onready var exit_marker: Marker3D = get_node_or_null("ExitMarker")

func _ready() -> void:
	add_to_group("vehicles")
	car_mesh = get_node_or_null("CarModel")
	if car_mesh:
		wheel_fl = car_mesh.find_child("wheel-front-left", true, false)
		wheel_fr = car_mesh.find_child("wheel-front-right", true, false)
		wheel_bl = car_mesh.find_child("wheel-back-left", true, false)
		wheel_br = car_mesh.find_child("wheel-back-right", true, false)
	
	if chase_camera:
		chase_camera.current = false
		
	if interact_area:
		interact_area.body_entered.connect(_on_interact_area_entered)
		interact_area.body_exited.connect(_on_interact_area_exited)

func _on_interact_area_entered(body: Node3D) -> void:
	if body is Player or body.is_in_group("player"):
		body.set_near_vehicle(self, true)

func _on_interact_area_exited(body: Node3D) -> void:
	if body is Player or body.is_in_group("player"):
		body.set_near_vehicle(self, false)

func enter_vehicle(player: CharacterBody3D) -> void:
	if is_driven:
		return
		
	driver_ref = player
	is_driven = true
	
	# Hide and disable driver
	player.visible = false
	player.set_physics_process(false)
	var col = player.find_child("CollisionShape3D", true, false)
	if col:
		col.set_deferred("disabled", true)
		
	# Switch to car chase camera
	if chase_camera:
		chase_camera.current = true
		
	# Update player touch controls
	if player.has_node("TouchHUD/TouchControls"):
		player.get_node("TouchHUD/TouchControls").set_driving_mode(true, self)
		
	player_entered.emit()

func exit_vehicle() -> void:
	if not is_driven or not driver_ref:
		return
		
	is_driven = false
	mobile_steer = 0.0
	mobile_throttle = 0.0
	
	# Place player at exit marker
	var exit_pos = exit_marker.global_position if exit_marker else global_position + (-global_basis.x * 2.0)
	driver_ref.global_position = exit_pos
	driver_ref.rotation.y = rotation.y
	driver_ref.visible = true
	driver_ref.velocity = Vector3.ZERO
	driver_ref.set_physics_process(true)
	
	var col = driver_ref.find_child("CollisionShape3D", true, false)
	if col:
		col.disabled = false
		
	# Switch camera back to player
	var player_cam = driver_ref.find_child("Camera3D", true, false)
	if player_cam and player_cam is Camera3D:
		player_cam.current = true
		
	if driver_ref.has_node("TouchHUD/TouchControls"):
		driver_ref.get_node("TouchHUD/TouchControls").set_driving_mode(false, null)
		
	driver_ref = null
	player_exited.emit()

func _unhandled_input(event: InputEvent) -> void:
	if is_driven and event is InputEventKey and event.pressed:
		if event.keycode == KEY_E or event.keycode == KEY_ENTER:
			exit_vehicle()

func _physics_process(delta: float) -> void:
	# 1. Gather Input
	var throttle_input := 0.0
	var steer_input := 0.0
	
	if is_driven:
		# Keyboard WASD / Arrows
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			throttle_input += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			throttle_input -= 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			steer_input += 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			steer_input -= 1.0
			
		# Mobile touch input
		if absf(mobile_throttle) > 0.05:
			throttle_input = mobile_throttle
		if absf(mobile_steer) > 0.05:
			steer_input = -mobile_steer
			
	# 2. Acceleration & Braking
	var forward_vec = -global_basis.z
	var right_vec = global_basis.x
	
	# Current speed in vehicle forward direction
	var current_forward_speed = velocity.dot(forward_vec)
	
	if throttle_input > 0.0:
		# Accelerate forward
		if current_forward_speed < max_speed:
			velocity += forward_vec * acceleration * throttle_input * delta
	elif throttle_input < 0.0:
		# If moving forward, brake hard. Otherwise, reverse.
		if current_forward_speed > 1.5:
			velocity -= forward_vec * braking * delta
		else:
			if current_forward_speed > -reverse_speed:
				velocity += forward_vec * (acceleration * 0.6) * throttle_input * delta
	else:
		# Natural rolling resistance friction
		if is_on_floor():
			var rolling_friction = 4.0
			velocity.x = move_toward(velocity.x, 0.0, rolling_friction * delta)
			velocity.z = move_toward(velocity.z, 0.0, rolling_friction * delta)
			
	# 3. Steering & Yaw Rotation
	var target_steer = steer_input * max_steer_angle
	current_steer_angle = move_toward(current_steer_angle, target_steer, steer_speed * delta)
	
	# Car only turns when moving
	var speed_ratio = clampf(current_forward_speed / max_speed, -0.6, 1.0)
	if absf(speed_ratio) > 0.02 and is_on_floor():
		var turn_rate = current_steer_angle * speed_ratio * 2.2
		rotation.y += turn_rate * delta
		
	# 4. Lateral Grip (Drift control)
	# Eliminate sideways sliding velocity along right_vec
	var lateral_vel = velocity.dot(right_vec)
	velocity -= right_vec * lateral_vel * minf(1.0, lateral_grip * delta)
	
	# 5. Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.2
		
	# 6. Apply Movement
	move_and_slide()
	
	# 7. Visual Feedback: Wheels and Chassis Suspension Tilt
	_update_visuals(delta, current_forward_speed)

func _update_visuals(delta: float, current_forward_speed: float) -> void:
	# Front wheel steering angle
	if wheel_fl:
		wheel_fl.rotation.y = current_steer_angle
	if wheel_fr:
		wheel_fr.rotation.y = current_steer_angle
		
	# Wheel rolling rotation around X axis
	var roll_delta = (current_forward_speed / 0.35) * delta
	if wheel_fl:
		wheel_fl.rotation.x += roll_delta
	if wheel_fr:
		wheel_fr.rotation.x += roll_delta
	if wheel_bl:
		wheel_bl.rotation.x += roll_delta
	if wheel_br:
		wheel_br.rotation.x += roll_delta
		
	# Chassis roll tilt when turning
	if car_mesh:
		var target_roll = -current_steer_angle * (current_forward_speed / max_speed) * 0.18
		car_mesh.rotation.z = lerpf(car_mesh.rotation.z, target_roll, delta * 6.0)
		
		# Chassis pitch squat on acceleration / dive on braking
		var accel_pitch = (velocity.length() / max_speed) * 0.04
		car_mesh.rotation.x = lerpf(car_mesh.rotation.x, -accel_pitch, delta * 5.0)
