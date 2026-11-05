// Walls, pillars and props (triplanar-ish procedural stone / wood).
shader_type spatial;
uniform vec3 base : source_color = vec3(0.28, 0.28, 0.33);
uniform vec3 dark : source_color = vec3(0.04, 0.04, 0.06);
uniform float scale = 1.6;
uniform bool planks = false;
uniform bool see_through = false;   // pillars: dither out when the player is behind them
uniform vec3 player_pos = vec3(0.0, -100.0, 0.0);
varying vec3 wpos;
varying vec3 wnrm;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	if (see_through) {
		vec2 d = wpos.xz - player_pos.xz;
		float near = 1.0 - smoothstep(1.6, 2.8, length(d));
		float in_front = smoothstep(-0.6, 0.4, wpos.z - player_pos.z);
		float hide = near * in_front * smoothstep(0.3, 0.9, wpos.y) * 0.75;
		// ordered 4x4 dither keeps it opaque-pass cheap
		ivec2 q = ivec2(FRAGCOORD.xy) % 4;
		float bayer = float((q.x * 4 + q.y) * 7 % 16) / 16.0;
		if (bayer < hide) {
			discard;
		}
	}
	vec3 an = abs(wnrm);
	vec2 uv = an.y > 0.5 ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
	uv *= scale;
	float lines;
	if (planks) {
		lines = smoothstep(0.0, 0.08, abs(fract(uv.y * 1.5) - 0.5) * 2.0 - 0.85) ;
		lines = 1.0 - smoothstep(0.9, 1.0, abs(fract(uv.y * 1.5) - 0.5) * 2.0);
	} else {
		vec2 b = uv * vec2(1.0, 2.0);
		b.x += mod(floor(b.y), 2.0) * 0.5;
		vec2 f = fract(b);
		float e = min(min(f.x, 1.0 - f.x) * 0.5, min(f.y, 1.0 - f.y));
		lines = smoothstep(0.02, 0.06, e);
	}
	float n = vnoise(uv * 3.0) * 0.6 + vnoise(uv * 9.0) * 0.4;
	vec3 c = mix(dark, base, lines * (0.6 + 0.4 * n));
	// fade to black at the bottom & top for a moody look
	c *= mix(0.55, 1.0, smoothstep(0.0, 1.5, wpos.y));
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
