// Fog of war over the map, drawn as one rectangle above everything.
//
// FogOfWar keeps one byte per hex in `fog_cells` (one texel per offset
// [col, row] cell): 0 = in sight, 128 = explored, 255 = never seen. Each
// pixel works out which hex it is in (the same maths as Hex.from_pixel) and
// averages a ring of nearby samples, so the edge is a soft gradient about a
// hex wide instead of hexagon outlines.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D fog_cells : filter_nearest, repeat_disable;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform vec2 grid_size = vec2(1.0);   // columns, rows
uniform float hex_radius = 32.0;
uniform float explored_dim = 0.35;    // darkness of explored-but-unseen ground

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

// 0 = visible, 0.5 = explored, 1 = unseen (outside the map counts as unseen).
float cell_value(vec2 p) {
	float q = (sqrt(3.0) / 3.0 * p.x - p.y / 3.0) / hex_radius;
	float r = (2.0 / 3.0 * p.y) / hex_radius;
	vec3 cube = vec3(q, r, -q - r);
	vec3 rc = round(cube);
	vec3 d = abs(rc - cube);
	if (d.x > d.y && d.x > d.z) {
		rc.x = -rc.y - rc.z;
	} else if (d.y > d.z) {
		rc.y = -rc.x - rc.z;
	}
	int qi = int(rc.x);
	int ri = int(rc.y);
	int col = qi + (ri - (ri & 1)) / 2;  // axial -> odd-r offset
	if (col < 0 || ri < 0 || col >= int(grid_size.x) || ri >= int(grid_size.y)) {
		return 1.0;
	}
	return texelFetch(fog_cells, ivec2(col, ri), 0).r;
}

void fragment() {
	// Two rings of samples (about one and two hexes out), rotated by noise, give
	// a gradient roughly two hexes wide that hides the hex shapes.
	float n = texture(noise, world_pos / 260.0).r;
	float acc = cell_value(world_pos) * 2.0;
	float weight = 2.0;
	const int TAPS = 12;
	for (int i = 0; i < TAPS; i++) {
		float a = 6.2831853 * (float(i) + n) / float(TAPS);
		vec2 dir = vec2(cos(a), sin(a));
		acc += cell_value(world_pos + dir * hex_radius * 0.9) * 1.0;
		acc += cell_value(world_pos + dir.yx * vec2(1.0, -1.0) * hex_radius * 1.9) * 0.6;
		weight += 1.6;
	}
	float v = acc / weight;
	float unseen = smoothstep(0.55, 0.92, v);
	float dim = smoothstep(0.05, 0.45, v) * explored_dim;
	COLOR = vec4(0.0, 0.0, 0.0, max(unseen, dim));
}
