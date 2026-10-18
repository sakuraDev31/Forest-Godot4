shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Lightweight Mobile Water Shader with Procedural Sine/Cosine Waves
// Zero heavy multi-tap screen blur - highly optimized for Mali/Adreno mobile GPUs

uniform vec4 shallow_color : source_color = vec4(0.12, 0.45, 0.58, 0.85);
uniform vec4 deep_color : source_color = vec4(0.04, 0.16, 0.32, 0.95);
uniform float metallic : hint_range(0.0, 1.0) = 0.1;
uniform float roughness : hint_range(0.0, 1.0) = 0.15;
uniform float specular : hint_range(0.0, 1.0) = 0.8;

// Wave simulation parameters (Sine/Cosine)
uniform float wave_height : hint_range(0.0, 1.0) = 0.18;
uniform float wave_frequency_1 : hint_range(0.01, 1.0) = 0.12;
uniform float wave_frequency_2 : hint_range(0.01, 1.0) = 0.22;
uniform float wave_speed_1 : hint_range(0.1, 5.0) = 1.2;
uniform float wave_speed_2 : hint_range(0.1, 5.0) = 1.8;

// Textures
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 normal_scale = vec2(0.08, 0.08);
uniform float normal_strength : hint_range(0.0, 2.0) = 0.6;
uniform float foam_threshold : hint_range(0.0, 1.0) = 0.65;

varying float v_wave_height;
varying vec3 v_world_pos;

void vertex() {
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = world_vertex;
	
	// Wave 1: Primary sinusoidal rolling wave
	float w1 = sin(world_vertex.x * wave_frequency_1 + TIME * wave_speed_1) * 
	           cos(world_vertex.z * (wave_frequency_1 * 0.75) + TIME * (wave_speed_1 * 0.85));
	
	// Wave 2: Secondary cross-directional wave
	float w2 = sin((world_vertex.x + world_vertex.z) * wave_frequency_2 * 0.7 - TIME * wave_speed_2) * 
	           cos((world_vertex.x - world_vertex.z) * wave_frequency_2 * 0.5 + TIME * (wave_speed_2 * 0.7));
	
	float combined_wave = (w1 + w2 * 0.45) * wave_height;
	v_wave_height = combined_wave;
	
	VERTEX.y += combined_wave;
	
	// Calculate smooth analytical normals from sine/cosine derivatives
	float d_dx = cos(world_vertex.x * wave_frequency_1 + TIME * wave_speed_1) * 
	             cos(world_vertex.z * (wave_frequency_1 * 0.75) + TIME * (wave_speed_1 * 0.85)) * 
	             wave_frequency_1 * wave_height;
	
	float d_dz = -sin(world_vertex.x * wave_frequency_1 + TIME * wave_speed_1) * 
	              sin(world_vertex.z * (wave_frequency_1 * 0.75) + TIME * (wave_speed_1 * 0.85)) * 
	              (wave_frequency_1 * 0.75) * wave_height;
	
	NORMAL = normalize(vec3(-d_dx, 1.0, -d_dz));
}

void fragment() {
	// Dual scrolling UVs for normal map
	vec2 uv_scroll_1 = v_world_pos.xz * normal_scale + vec2(TIME * 0.03, TIME * 0.02);
	vec2 uv_scroll_2 = v_world_pos.xz * normal_scale * 1.5 - vec2(TIME * 0.02, TIME * 0.04);
	
	vec3 n1 = texture(normal_map, uv_scroll_1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_map, uv_scroll_2).rgb * 2.0 - 1.0;
	vec3 blended_normal = normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
	
	NORMAL_MAP = blended_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;
	
	// Fresnel reflection factor
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.5);
	
	// Depth gradient based on wave height
	float height_factor = clamp((v_wave_height / wave_height) * 0.5 + 0.5, 0.0, 1.0);
	vec3 base_water = mix(deep_color.rgb, shallow_color.rgb, height_factor * 0.7 + 0.3);
	
	// Add sunlight / sky reflection via Fresnel
	vec3 final_color = mix(base_water, shallow_color.rgb * 1.35, fresnel * 0.6);
	
	// Foam on wave peaks
	float foam_mask = smoothstep(foam_threshold, 1.0, height_factor);
	vec2 foam_uv = v_world_pos.xz * normal_scale * 2.0 + vec2(TIME * 0.04, -TIME * 0.03);
	vec3 foam_sample = texture(foam_texture, foam_uv).rgb;
	final_color = mix(final_color, vec3(0.92, 0.96, 1.0), foam_mask * foam_sample.r * 0.75);
	
	ALBEDO = final_color;
	METALLIC = metallic;
	ROUGHNESS = mix(roughness, 0.05, fresnel);
	SPECULAR = specular;
	ALPHA = mix(deep_color.a, shallow_color.a, height_factor);
}
