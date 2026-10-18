extends Node

## Graphics Settings Manager for Godot 4.7 Mobile
## Controls 3D Resolution Scaling, Render Distance (Camera Far & Fog),
## Dynamic Auto-LOD Mesh Scaling, Foliage Clipmap Ranges, and Shadows.
## Strictly defaults to LOW resolution (0.65x) and LOW render distance (120m) on clean install.

const SETTINGS_FILE: String = "user://settings.cfg"

signal settings_changed(settings: Dictionary)

static var instance: Node = null

var resolution_tier: String = "low"     # "low" (0.65x), "mid" (0.85x), "high" (1.0x)
var render_dist_tier: String = "low"    # "low" (120m), "mid" (250m), "high" (500m)
var shadow_tier: String = "low"         # "low" (off), "mid" (1024), "high" (2048)

func _ready() -> void:
	instance = self
	load_and_apply_settings()
	# Apply once more deferred to ensure main scene nodes are fully loaded
	call_deferred("apply_all_settings")

func load_and_apply_settings() -> void:
	var cfg = ConfigFile.new()
	var err = cfg.load(SETTINGS_FILE)
	
	if err != OK:
		# Fresh install: strictly default to LOW resolution and LOW render distance
		resolution_tier = "low"
		render_dist_tier = "low"
		shadow_tier = "low"
		save_settings()
	else:
		resolution_tier = cfg.get_value("graphics", "resolution_tier", "low")
		render_dist_tier = cfg.get_value("graphics", "render_dist_tier", "low")
		shadow_tier = cfg.get_value("graphics", "shadow_tier", "low")
		
	apply_all_settings()

func save_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("graphics", "resolution_tier", resolution_tier)
	cfg.set_value("graphics", "render_dist_tier", render_dist_tier)
	cfg.set_value("graphics", "shadow_tier", shadow_tier)
	cfg.save(SETTINGS_FILE)

func set_resolution(tier: String) -> void:
	resolution_tier = tier.to_lower()
	_apply_resolution()
	save_settings()
	settings_changed.emit(get_current_settings())

func set_render_distance(tier: String) -> void:
	render_dist_tier = tier.to_lower()
	_apply_render_distance()
	save_settings()
	settings_changed.emit(get_current_settings())

func set_shadows(tier: String) -> void:
	shadow_tier = tier.to_lower()
	_apply_shadows()
	save_settings()
	settings_changed.emit(get_current_settings())

func get_current_settings() -> Dictionary:
	return {
		"resolution_tier": resolution_tier,
		"render_dist_tier": render_dist_tier,
		"shadow_tier": shadow_tier,
		"scale_value": get_scale_value(),
		"camera_far": get_camera_far(),
		"mesh_lod_threshold": get_mesh_lod_threshold()
	}

func get_scale_value() -> float:
	match resolution_tier:
		"low": return 0.65
		"mid": return 0.85
		"high": return 1.0
		_: return 0.65

func get_camera_far() -> float:
	match render_dist_tier:
		"low": return 120.0
		"mid": return 250.0
		"high": return 500.0
		_: return 120.0

func get_mesh_lod_threshold() -> float:
	# Higher values trigger lower-poly LODs sooner for smaller screen coverage
	match render_dist_tier:
		"low": return 3.0
		"mid": return 2.0
		"high": return 1.0
		_: return 3.0

func apply_all_settings() -> void:
	_apply_resolution()
	_apply_render_distance()
	_apply_shadows()

func _apply_resolution() -> void:
	var vp = get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = get_scale_value()

func _apply_render_distance() -> void:
	var far_dist = get_camera_far()
	var vp = get_viewport()
	
	# 1. Update Viewport Mesh Auto-LOD threshold
	if vp and "mesh_lod_threshold" in vp:
		vp.mesh_lod_threshold = get_mesh_lod_threshold()
	
	# 2. Update active camera and player/vehicle cameras
	var active_cam = vp.get_camera_3d() if vp else null
	if active_cam:
		active_cam.far = far_dist
		
	var player = get_tree().root.find_child("Player", true, false) if get_tree() else null
	if player:
		var cam = player.find_child("Camera3D", true, false)
		if cam and cam is Camera3D:
			cam.far = far_dist
			
	var car = get_tree().root.find_child("DrivableCar", true, false) if get_tree() else null
	if car:
		var car_cam = car.find_child("Camera3D", true, false)
		if car_cam and car_cam is Camera3D:
			car_cam.far = far_dist
			
	# 3. Update WorldEnvironment fog to match camera clipping plane
	var env_node = get_tree().root.find_child("WorldEnvironment", true, false) if get_tree() else null
	if not env_node and get_tree():
		env_node = get_tree().root.find_child("Sky3D", true, false)
		
	if env_node and env_node is WorldEnvironment and env_node.environment:
		var env = env_node.environment
		if env.fog_enabled:
			env.fog_depth_begin = maxf(10.0, far_dist * 0.2)
			env.fog_depth_end = far_dist
			
	# 4. Apply distance visibility ranges & culling to scene geometry
	_apply_scene_lod_and_culling(far_dist)
	
	# 5. Apply dynamic LOD ranges to Terrain3D foliage assets
	_apply_terrain_lod()

func _apply_scene_lod_and_culling(far_dist: float) -> void:
	var scene_root = get_tree().current_scene if get_tree() else null
	if not scene_root:
		return
	_apply_node_culling_recursive(scene_root, far_dist)

func _apply_node_culling_recursive(node: Node, far_dist: float) -> void:
	if node is GeometryInstance3D:
		var n_name = node.name.to_lower()
		var is_small_prop = ("grass" in n_name or "bush" in n_name 
			or "small" in n_name or "flower" in n_name)
		
		if is_small_prop:
			node.visibility_range_end = minf(far_dist * 0.45, 50.0)
			node.visibility_range_end_margin = 10.0
		else:
			node.visibility_range_end = far_dist
			node.visibility_range_end_margin = 20.0
			
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		
	for child in node.get_children():
		_apply_node_culling_recursive(child, far_dist)

func _apply_terrain_lod() -> void:
	if not get_tree():
		return
	var terrain = get_tree().root.find_child("Terrain3D", true, false)
	if not terrain or not ("assets" in terrain) or not terrain.assets:
		return
		
	var mesh_list = terrain.assets.get("mesh_list")
	if not mesh_list:
		return
		
	for asset in mesh_list:
		if not asset:
			continue
		var a_name = asset.get("name").to_lower() if ("name" in asset) else ""
		if "grass" in a_name:
			match render_dist_tier:
				"low": asset.set("lod0_range", 35.0)
				"mid": asset.set("lod0_range", 55.0)
				"high": asset.set("lod0_range", 85.0)
		elif "bush" in a_name or "small rock" in a_name:
			match render_dist_tier:
				"low": asset.set("lod0_range", 45.0)
				"mid": asset.set("lod0_range", 70.0)
				"high": asset.set("lod0_range", 100.0)
		else:
			# Pine and maple trees, large rocks
			match render_dist_tier:
				"low": asset.set("lod0_range", 80.0)
				"mid": asset.set("lod0_range", 140.0)
				"high": asset.set("lod0_range", 220.0)

func _apply_shadows() -> void:
	if not get_tree():
		return
	var light = get_tree().root.find_child("DirectionalLight3D", true, false)
	if not light:
		light = get_tree().root.find_child("SunLight", true, false)
		
	if light and light is DirectionalLight3D:
		match shadow_tier:
			"low":
				light.shadow_enabled = false
			"mid":
				light.shadow_enabled = true
				RenderingServer.directional_shadow_atlas_set_size(1024, true)
			"high":
				light.shadow_enabled = true
				RenderingServer.directional_shadow_atlas_set_size(2048, true)
