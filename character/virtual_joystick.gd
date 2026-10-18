class_name TouchVirtualJoystick
extends Control

## Production Dynamic Floating Virtual Joystick for Godot 4.7 Mobile
## Supports: Dynamic placement on tap, Smooth Floating Thumb follow,
## Radial Deadzone, Speed Scaling (Walk/Run/Sprint), and Visual Sprint Feedback.

signal joystick_moved(output_vector: Vector2)
signal sprint_threshold_changed(is_sprinting: bool)

@export var max_radius: float = 85.0
@export var dead_zone: float = 0.08
@export var sprint_threshold: float = 0.85

var touch_id: int = -1
var center_pos: Vector2 = Vector2.ZERO
var default_center: Vector2 = Vector2.ZERO
var current_pos: Vector2 = Vector2.ZERO
var output: Vector2 = Vector2.ZERO
var is_in_sprint_zone: bool = false

@onready var knob: Control = $Knob
@onready var base: Control = $Base

func _ready() -> void:
	# Calculate default resting position based on size
	default_center = size / 2.0
	center_pos = default_center
	current_pos = default_center
	_reset_joystick_visuals()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		default_center = size / 2.0
		if touch_id == -1:
			center_pos = default_center
			current_pos = default_center
			_reset_joystick_visuals()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_id == -1:
			touch_id = event.index
			center_pos = event.position
			if base:
				base.position = center_pos - base.size / 2.0
				base.modulate = Color(1.0, 1.0, 1.0, 0.9)
			if knob:
				knob.modulate = Color(1.0, 1.0, 1.0, 1.0)
			_process_drag(event.position)
			accept_event()
		elif not event.pressed and event.index == touch_id:
			_reset_joystick()
			accept_event()

	elif event is InputEventScreenDrag and event.index == touch_id:
		_process_drag(event.position)
		accept_event()

	# Also support mouse for PC testing
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and touch_id == -1:
				touch_id = 999
				center_pos = event.position
				if base:
					base.position = center_pos - base.size / 2.0
					base.modulate = Color(1.0, 1.0, 1.0, 0.9)
				_process_drag(event.position)
				accept_event()
			elif not event.pressed and touch_id == 999:
				_reset_joystick()
				accept_event()

	elif event is InputEventMouseMotion and touch_id == 999:
		_process_drag(event.position)
		accept_event()

func _process_drag(target_pos: Vector2) -> void:
	var diff = target_pos - center_pos
	var dist = diff.length()

	# Dynamic Floating Joystick: Base smoothly follows thumb when exceeding max radius
	if dist > max_radius:
		var excess = dist - max_radius
		center_pos += diff.normalized() * excess
		diff = target_pos - center_pos
		if base:
			base.position = center_pos - base.size / 2.0

	current_pos = center_pos + diff

	# Calculate normalized output with deadzone
	var raw_mag = diff.length() / max_radius
	if raw_mag < dead_zone:
		output = Vector2.ZERO
	else:
		# Smooth ramp up after deadzone
		var remapped_mag = clampf((raw_mag - dead_zone) / (1.0 - dead_zone), 0.0, 1.0)
		var dir = diff.normalized()
		# In screen coordinates: -Y is UP (forward), +X is RIGHT
		output = Vector2(dir.x, -dir.y) * remapped_mag

	# Check sprint threshold (pushed hard forward/direction)
	var sprint_active = (output.length() >= sprint_threshold and output.y > 0.25)
	if sprint_active != is_in_sprint_zone:
		is_in_sprint_zone = sprint_active
		sprint_threshold_changed.emit(is_in_sprint_zone)
		_update_sprint_visuals(is_in_sprint_zone)

	_update_knob_visual()
	joystick_moved.emit(output)

func _update_knob_visual() -> void:
	if knob:
		knob.position = current_pos - knob.size / 2.0

func _update_sprint_visuals(sprinting: bool) -> void:
	if knob:
		if sprinting:
			# Glow cyan/neon to clearly indicate Sprint mode active
			knob.modulate = Color(0.2, 0.95, 1.0, 1.0)
		else:
			knob.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _reset_joystick() -> void:
	touch_id = -1
	is_in_sprint_zone = false
	sprint_threshold_changed.emit(false)
	output = Vector2.ZERO
	center_pos = default_center
	current_pos = default_center
	_reset_joystick_visuals()
	joystick_moved.emit(Vector2.ZERO)

func _reset_joystick_visuals() -> void:
	if base:
		base.position = default_center - base.size / 2.0
		base.modulate = Color(1.0, 1.0, 1.0, 0.45)
	if knob:
		knob.position = default_center - knob.size / 2.0
		knob.modulate = Color(1.0, 1.0, 1.0, 0.65)
