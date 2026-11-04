// Flat ground effects: telegraphs (circle / line), shockwave rings, portals.
// mode 0 = filled circle telegraph, 1 = rectangle telegraph, 2 = ring wave,
// 3 = spawn portal, 4 = soft streak (dash trail; fades toward the start), 5 = soft disc.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform int mode = 0;
uniform float fill = 0.0;
uniform float fade = 1.0;
uniform vec3 color : source_color = vec3(1.0, 0.08, 0.15);
uniform float thickness = 0.08;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = 0.0;
	if (mode == 0) {
		float rim = smoothstep(1.0, 0.96, d) * smoothstep(0.88, 0.96, d);
		float inner = smoothstep(1.0, 0.0, d) * 0.12;
		float f = step(d, fill) * smoothstep(1.0, 0.0, d) * 0.35 + smoothstep(fill, fill - 0.04, d) * step(fill - 0.04, d) * 0.9;
		a = (rim + inner + f) * step(d, 1.0);
	} else if (mode == 1) {
		float ex = abs(p.x);
		float edge = smoothstep(0.86, 1.0, ex) + smoothstep(-0.96, -1.0, p.y) * 0.5;
		float y01 = UV.y;
		float f = step(1.0 - fill, 1.0 - y01) * 0.16;
		float chevron = step(0.5, fract((y01 + abs(p.x) * 0.25) * 6.0 - TIME * 2.0)) * 0.07;
		a = (edge * 0.6 + f + chevron + 0.03);
	} else if (mode == 2) {
		float r = fill;
		float band = smoothstep(thickness, 0.0, abs(d - r));
		float inner = smoothstep(r, 0.0, d) * 0.15 * (1.0 - r);
		a = (band + inner) * step(d, 1.0);
	} else if (mode == 3) {
		float ang = atan(p.y, p.x);
		float swirl = sin(ang * 5.0 + d * 10.0 - TIME * 6.0) * 0.5 + 0.5;
		float ring = smoothstep(0.1, 0.0, abs(d - 0.85 * fill));
		a = (ring + swirl * smoothstep(1.0, 0.2, d) * 0.4) * step(d, 1.0) * fill;
	}
	else if (mode == 4) {
		float lat = exp(-p.x * p.x * 6.0);
		float len = smoothstep(-1.0, 1.0, p.y) * smoothstep(1.0, 0.85, p.y);
		a = lat * len * 0.9 + exp(-p.x * p.x * 60.0) * len * 0.8;
	}
	else if (mode == 5) {
		a = pow(clamp(1.0 - d, 0.0, 1.0), 2.0) * 0.35;
	}
	ALBEDO = color * a * fade;
}
