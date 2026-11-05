shader_type canvas_item;
uniform float damage = 0.0;
uniform float base = 0.38;
uniform vec3 hurt_color : source_color = vec3(0.8, 0.0, 0.08);
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p * vec2(0.85, 1.0));
	float v = smoothstep(0.55, 1.45, d);
	vec3 c = mix(vec3(0.0), hurt_color, damage);
	COLOR = vec4(c, v * (base + damage * 0.6));
}
