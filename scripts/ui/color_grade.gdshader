// Gentle film-like grade over the game view: contrast, saturation, warmth and
// a soft vignette, to pull the pre-rendered art together.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float contrast = 1.06;
uniform float saturation = 1.06;
uniform float warmth = 0.025;
uniform float vignette = 0.32;

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	c = (c - 0.5) * contrast + 0.5;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c += vec3(warmth, warmth * 0.35, -warmth * 0.6);
	vec2 d = (UV - 0.5) * vec2(1.0, 0.85);
	c *= 1.0 - vignette * smoothstep(0.32, 0.8, length(d));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
