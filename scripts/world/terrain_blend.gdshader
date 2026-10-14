// Seamless terrain: blends terrain textures using splat (weight) maps.
//
// TerrainRenderer bakes up to 12 terrain weights into three RGBA splat
// textures (slot i -> texture i / 4, channel i % 4). Bilinear filtering makes
// soft transitions; per-terrain noise then breaks them into irregular,
// natural edges, so hex boundaries never show. Textures are sampled in world
// space, so the same terrain is continuous across hexes.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D splat_0 : filter_linear, repeat_disable;
uniform sampler2D splat_1 : filter_linear, repeat_disable;
uniform sampler2D splat_2 : filter_linear, repeat_disable;
uniform sampler2DArray terrain_textures : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise : filter_linear, repeat_enable;

uniform int slot_count = 1;
// World rectangle covered by the splat textures.
uniform vec2 splat_origin = vec2(0.0);
uniform vec2 splat_size = vec2(1.0);
// World pixels per repeat of a terrain texture.
uniform float texture_world_size = 256.0;
// How much noise disturbs the transitions, and how crisp they end up.
uniform float edge_noise = 0.5;
uniform float edge_sharpness = 4.0;
// Large-scale brightness variation and second-sample mixing, to hide tiling.
uniform float macro_variation = 0.08;
uniform float anti_tiling = 0.45;

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

float pick(vec4 v, int c) {
	return c == 0 ? v.r : (c == 1 ? v.g : (c == 2 ? v.b : v.a));
}

float slot_weight(int i, vec4 s0, vec4 s1, vec4 s2) {
	int c = i % 4;
	if (i < 4) {
		return pick(s0, c);
	} else if (i < 8) {
		return pick(s1, c);
	}
	return pick(s2, c);
}

vec3 sample_terrain(int i, vec2 wp) {
	vec2 uv = wp / texture_world_size;
	vec3 a = texture(terrain_textures, vec3(uv, float(i))).rgb;
	// A second sample at another scale/offset, mixed in patches, breaks up
	// the visible repeat of a single tiling texture.
	vec2 uv2 = uv * 0.713 + vec2(0.37, 0.53);
	vec3 b = texture(terrain_textures, vec3(uv2, float(i))).rgb;
	float m = texture(noise, wp / 900.0 + vec2(0.11, 0.73)).r;
	return mix(a, b, smoothstep(0.3, 0.7, m) * anti_tiling);
}

void fragment() {
	vec2 suv = (world_pos - splat_origin) / splat_size;
	vec4 s0 = texture(splat_0, suv);
	vec4 s1 = texture(splat_1, suv);
	vec4 s2 = texture(splat_2, suv);
	vec3 col = vec3(0.0);
	float total = 0.0;
	for (int i = 0; i < 12; i++) {
		if (i >= slot_count) {
			break;
		}
		float w = slot_weight(i, s0, s1, s2);
		if (w <= 0.003) {
			continue;
		}
		float n = texture(noise, world_pos / 150.0 + vec2(float(i) * 0.173, float(i) * 0.311)).r;
		float ww = clamp(w + (n - 0.5) * edge_noise, 0.0, 1.0);
		ww = pow(ww, edge_sharpness) + 1e-5 * w;
		col += sample_terrain(i, world_pos) * ww;
		total += ww;
	}
	col /= max(total, 1e-5);
	float macro = texture(noise, world_pos / 700.0).r - 0.5;
	col *= 1.0 + macro * 2.0 * macro_variation;
	COLOR = vec4(col, 1.0);
}
