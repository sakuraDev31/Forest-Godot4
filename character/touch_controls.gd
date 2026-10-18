class_name TouchControls
extends Control

## Advanced Touch HUD for Godot 4.7 Mobile
## Controls: Virtual Joystick, Camera Look Zone, Action Cluster (Jump, Run, Crouch, 1st/3rd),
## Vehicle Drive/Exit Controls, and Graphics Settings Modal (Resolution & Render Distance).

@export var look_sensitivity: float = 0.005

var look_touch_id: int = -1
var last_look_pos: Vector2 = Vector2.ZERO

var player_ref: CharacterBody3D = null
var active_vehicle: Node = null
var is_driving: bool = false

# Node references
@onready var joystick: Control = get_node_or_null("LeftTouchZone/VirtualJoystick")
@onready var action_cluster: Control = get_node_or_null("ActionCluster")
@onready var jump_btn: Button = get_node_or_null("ActionCluster/JumpBtn")
@onready var sprint_btn: Button = get_node_or_null("ActionCluster/SprintBtn")
@onready var crouch_btn: Button = get_node_or_null("ActionCluster/CrouchBtn")
@onready var camera_btn: Button = get_node_or_null("ActionCluster/CameraBtn")
@onready var drive_btn: Button = get_node_or_null("ActionCluster/DriveBtn")
@onready var exit_car_btn: Button = get_node_or_null("ExitCarBtn")

# Graphics Settings UI references
@onready var settings_btn: Button = get_node_or_null("SettingsBtn")
@onready var settings_modal: PanelContainer = get_node_or_null("SettingsModal")

func setup(player: CharacterBody3D) -> void:
	player_ref = player
	if joystick:
		if joystick.has_signal("joystick_moved"):
			joystick.joystick_moved.connect(_on_joystick_moved)
		if joystick.has_signal("sprint_threshold_changed"):
			joystick.sprint_threshold_changed.connect(_on_joystick_sprint_changed)

func _on_joystick_sprint_changed(sprinting: bool) -> void:
	if player_ref and player_ref.has_method("set_joystick_sprint"):
		player_ref.set_joystick_sprint(sprinting)

func _ready() -> void:
	# Action buttons signals - use button_down for instant tactile response on mobile
	if jump_btn:
		jump_btn.button_down.connect(_on_jump_pressed)
	if sprint_btn:
		sprint_btn.toggled.connect(_on_sprint_toggled)
	if crouch_btn:
		crouch_btn.button_down.connect(_on_crouch_pressed)
	if camera_btn:
		camera_btn.button_down.connect(_on_camera_pressed)
	if drive_btn:
		drive_btn.button_down.connect(_on_drive_pressed)
		drive_btn.visible = false
	if exit_car_btn:
		exit_car_btn.button_down.connect(_on_exit_car_pressed)
		exit_car_btn.visible = false

		
	# Settings UI
	if settings_btn:
		settings_btn.pressed.connect(_on_settings_pressed)
	if settings_modal:
		settings_modal.visible = false
		_setup_settings_modal_buttons()

func _setup_settings_modal_buttons() -> void:
	# Resolution buttons
	var res_low = settings_modal.find_child("ResLowBtn", true, false)
	var res_mid = settings_modal.find_child("ResMidBtn", true, false)
	var res_high = settings_modal.find_child("ResHighBtn", true, false)
	if res_low: res_low.pressed.connect(func(): _on_set_resolution("low"))
	if res_mid: res_mid.pressed.connect(func(): _on_set_resolution("mid"))
	if res_high: res_high.pressed.connect(func(): _on_set_resolution("high"))
	
	# Render distance buttons
	var dist_low = settings_modal.find_child("DistLowBtn", true, false)
	var dist_mid = settings_modal.find_child("DistMidBtn", true, false)
	var dist_high = settings_modal.find_child("DistHighBtn", true, false)
	if dist_low: dist_low.pressed.connect(func(): _on_set_render_distance("low"))
	if dist_mid: dist_mid.pressed.connect(func(): _on_set_render_distance("mid"))
	if dist_high: dist_high.pressed.connect(func(): _on_set_render_distance("high"))
	
	# Close button
	var close_btn = settings_modal.find_child("CloseSettingsBtn", true, false)
	if close_btn:
		close_btn.pressed.connect(func(): settings_modal.visible = false)
		
	_refresh_settings_ui()

func _on_settings_pressed() -> void:
	if settings_modal:
		settings_modal.visible = not settings_modal.visible
		if settings_modal.visible:
			_refresh_settings_ui()

func _get_graphics_settings() -> Node:
	if has_node("/root/GraphicsSettings"):
		return get_node("/root/GraphicsSettings")
	return null

func _on_set_resolution(tier: String) -> void:
	var gs = _get_graphics_settings()
	if gs:
		gs.set_resolution(tier)
	_refresh_settings_ui()

func _on_set_render_distance(tier: String) -> void:
	var gs = _get_graphics_settings()
	if gs:
		gs.set_render_distance(tier)
	_refresh_settings_ui()

func _refresh_settings_ui() -> void:
	var gs = _get_graphics_settings()
	if not settings_modal or not gs:
		return
	var res_low = settings_modal.find_child("ResLowBtn", true, false)
	var res_mid = settings_modal.find_child("ResMidBtn", true, false)
	var res_high = settings_modal.find_child("ResHighBtn", true, false)
	
	if res_low: res_low.modulate = Color(0.3, 0.9, 0.3) if gs.resolution_tier == "low" else Color(0.8, 0.8, 0.8)
	if res_mid: res_mid.modulate = Color(0.3, 0.9, 0.3) if gs.resolution_tier == "mid" else Color(0.8, 0.8, 0.8)
	if res_high: res_high.modulate = Color(0.3, 0.9, 0.3) if gs.resolution_tier == "high" else Color(0.8, 0.8, 0.8)
	
	var dist_low = settings_modal.find_child("DistLowBtn", true, false)
	var dist_mid = settings_modal.find_child("DistMidBtn", true, false)
	var dist_high = settings_modal.find_child("DistHighBtn", true, false)
	
	if dist_low: dist_low.modulate = Color(0.3, 0.9, 0.3) if gs.render_dist_tier == "low" else Color(0.8, 0.8, 0.8)
	if dist_mid: dist_mid.modulate = Color(0.3, 0.9, 0.3) if gs.render_dist_tier == "mid" else Color(0.8, 0.8, 0.8)
	if dist_high: dist_high.modulate = Color(0.3, 0.9, 0.3) if gs.render_dist_tier == "high" else Color(0.8, 0.8, 0.8)

func show_drive_prompt(visible_state: bool) -> void:
	if drive_btn and not is_driving:
		drive_btn.visible = visible_state

func set_driving_mode(driving: bool, vehicle: Node = null) -> void:
	is_driving = driving
	active_vehicle = vehicle
	
	if drive_btn:
		drive_btn.visible = false
	if exit_car_btn:
		exit_car_btn.visible = driving
		
	# Hide on-foot action buttons when driving
	if jump_btn: jump_btn.visible = not driving
	if sprint_btn: sprint_btn.visible = not driving
	if crouch_btn: crouch_btn.visible = not driving
	if camera_btn: camera_btn.visible = not driving

func _on_joystick_moved(vec: Vector2) -> void:
	if is_driving and active_vehicle:
		# In driving mode, joystick controls car throttle (Y) and steering (X)
		active_vehicle.mobile_throttle = vec.y
		active_vehicle.mobile_steer = vec.x
	elif player_ref:
		player_ref.external_move_vector = vec

func _on_jump_pressed() -> void:
	if player_ref and player_ref.has_method("trigger_jump"):
		player_ref.trigger_jump()

func _on_sprint_toggled(toggled_on: bool) -> void:
	if player_ref and player_ref.has_method("set_touch_sprint"):
		player_ref.set_touch_sprint(toggled_on)
	if sprint_btn:
		sprint_btn.modulate = Color(0.25, 1.0, 0.45, 1.0) if toggled_on else Color(1.0, 1.0, 1.0, 1.0)

func _on_crouch_pressed() -> void:
	if player_ref and player_ref.has_method("toggle_crouch"):
		player_ref.toggle_crouch()

func _on_camera_pressed() -> void:
	if player_ref and player_ref.has_method("toggle_camera_mode"):
		player_ref.toggle_camera_mode()

func _on_drive_pressed() -> void:
	if player_ref and player_ref.has_method("try_interact_vehicle"):
		player_ref.try_interact_vehicle()

func _on_exit_car_pressed() -> void:
	if active_vehicle:
		active_vehicle.exit_vehicle()

func _gui_input(event: InputEvent) -> void:
	# Right half of screen touch drag for camera rotation
	if event is InputEventScreenTouch:
		if event.position.x > size.x * 0.45:
			if event.pressed and look_touch_id == -1:
				look_touch_id = event.index
				last_look_pos = event.position
			elif not event.pressed and event.index == look_touch_id:
				look_touch_id = -1


	elif event is InputEventScreenDrag and event.index == look_touch_id:
		var delta = event.position - last_look_pos
		last_look_pos = event.position
		if is_driving and active_vehicle and active_vehicle.has_method("apply_camera_rotation"):
			active_vehicle.apply_camera_rotation(delta * look_sensitivity)
		elif player_ref and player_ref.has_method("apply_look_delta"):
			player_ref.apply_look_delta(delta * look_sensitivity)
