shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert_wrap, specular_disabled;

// ============================================================
// MOBILE FOLIAGE SHADER (GENSHIN NPR PRINCIPLES FOR MALI-G57)
// Single-pass Alpha Scissor, 1 Texture Fetch, No Depth-Prepass
// ============================================================

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;

// Uniforms preserved for compatibility with existing material resources
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;

uniform sampler2D texture_ao : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;

uniform vec4 backlight : source_color = vec4(0.0);
uniform sampler2D texture_backlight : hint_default_black, filter_linear_mipmap, repeat_enable;

uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

// Procedural Sine Wind
uniform float wind_speed = 1.5;
uniform float wind_strength = 0.08;
uniform float wind_frequency = 0.1;
uniform float wind_detail = 0.1;
uniform vec2 wind_direction = vec2(1.0, 0.0);
uniform float vertex_mask_strength = 1.0;
uniform float directional_strength = 1.0;

void vertex() {
	// Root-locked sine wave displacement (base does not move, tips sway)
	float height = clamp(VERTEX.y, 0.0, 2.0);
	float wave = sin(TIME * wind_speed * 2.0 + (NODE_POSITION_WORLD.x + VERTEX.x) * 1.5 + (NODE_POSITION_WORLD.z + VERTEX.z) * 1.5);
	vec2 dir = normalize(wind_direction);
	VERTEX.x += wave * wind_strength * height * dir.x;
	VERTEX.z += wave * wind_strength * height * dir.y;
}

void fragment() {
	vec2 base_uv = UV * uv_scale + uv_offset;
	vec4 albedo_tex = texture(texture_albedo, base_uv);
	
	// Single-pass Alpha Scissor
	if (albedo_tex.a * albedo.a < 0.45) {
		discard;
	}
	
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	ALPHA = 1.0;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.0;
}