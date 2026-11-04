// Scythe slash crescent. Mesh UV.x runs along the arc (0 start .. 1 end),
// UV.y runs radially (0 inner .. 1 outer). Additive.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform float progress = 0.0;     // leading edge position along the arc
uniform float trail = 0.6;        // trail length (uv units)
uniform float fade = 1.0;
uniform vec3 edge_color : source_color = vec3(1.0, 0.05, 0.2);
uniform vec3 core_color : source_color = vec3(1.0, 0.7, 0.9);
uniform float intensity = 1.6;
uniform bool symmetric = false;   // crescent projectile: thick in the middle

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float head = progress;
	float tailp = head - trail;
	float along = clamp((UV.x - tailp) / max(head - tailp, 0.001), 0.0, 1.0);
	// soft leading edge + fade toward the tail
	float vis = smoothstep(head + 0.002, head - 0.05, UV.x) * smoothstep(tailp, tailp + 0.1, UV.x);
	vis *= smoothstep(0.0, 0.04, UV.x) * smoothstep(1.0, 0.96, UV.x) * step(UV.x, 1.0);
	if (symmetric) {
		along = 1.0 - abs(UV.x * 2.0 - 1.0);
		vis = smoothstep(0.0, 0.25, along);
	}
	// crescent band hugging the outer radius, thick at the head, thin at the tail
	float thick = mix(0.06, 0.5, pow(along, 1.4));
	float centre = 1.0 - thick * 0.5;
	float rr = clamp(1.0 - abs(UV.y - centre) / (thick * 0.5), 0.0, 1.0);
	float outer_edge = 1.0 - thick * 0.12;
	float core = exp(-pow((UV.y - outer_edge) / (0.02 + 0.05 * along), 2.0));
	float streak = vnoise(vec2(UV.x * 30.0 - TIME * 4.0, UV.y * 6.0));
	float body = pow(rr, 1.5) * (0.25 + 0.75 * streak) * mix(0.35, 1.0, UV.y);
	float a = (core * 1.6 + body * 0.7) * pow(along, 1.2) * vis * fade;
	vec3 col = mix(edge_color, core_color, clamp(core * 0.9, 0.0, 1.0));
	ALBEDO = col * a * intensity;
}
