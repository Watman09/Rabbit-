// Procedural dungeon flagstones.
shader_type spatial;

uniform vec3 stone_a : source_color = vec3(0.085, 0.085, 0.10);
uniform vec3 stone_b : source_color = vec3(0.15, 0.145, 0.17);
uniform vec3 grout : source_color = vec3(0.02, 0.02, 0.03);
uniform float tile = 2.2;
uniform vec2 arena_half = vec2(20.0, 20.0);
uniform vec3 moon_dir_color : source_color = vec3(0.25, 0.4, 0.9);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.5 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.2; }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz / tile;
	// offset every other row for a running bond pattern
	float row = floor(p.y);
	p.x += mod(row, 2.0) * 0.5;
	vec2 id = floor(p);
	vec2 f = fract(p);
	float rnd = hash(id);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float g = smoothstep(0.015, 0.05, edge + (fbm(wpos.xz * 3.0) - 0.5) * 0.03);
	float n = fbm(wpos.xz * 1.3);
	vec3 c = mix(stone_a, stone_b, rnd * 0.7 + n * 0.3);
	// cracks
	float crack = smoothstep(0.03, 0.0, abs(fbm(wpos.xz * 0.9 + rnd * 10.0) - 0.5)) * step(0.6, rnd);
	c = mix(c, grout, crack * 0.8);
	c = mix(grout, c, g);
	// wear and darkness toward walls
	vec2 q = abs(wpos.xz) / arena_half;
	float edge_dark = smoothstep(0.55, 1.05, max(q.x, q.y));
	c *= 1.0 - edge_dark * 0.55;
	ALBEDO = c;
	ROUGHNESS = 0.85 - rnd * 0.2;
	SPECULAR = 0.35;
}
