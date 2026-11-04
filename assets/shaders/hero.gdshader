// Hero body / scythe. Vertex colour = stylised albedo, COLOR.a = emission mask.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 rim_color : source_color = vec3(0.85, 0.15, 0.45);
uniform float rim_strength = 1.1;
uniform vec3 glow_color : source_color = vec3(0.9, 0.35, 1.0);
uniform float glow_strength = 1.4;
uniform float flash = 0.0;          // white hit flash
uniform float ghost = 0.0;          // dash: body becomes translucent-looking
uniform float sway = 1.0;           // cloak wind
uniform vec3 drag = vec3(0.0);      // local-space movement drag for the cloak
uniform float cloth_height = 1.0;   // cloth below this height sways

void vertex() {
	float h = clamp((cloth_height - VERTEX.y) / cloth_height, 0.0, 1.0);
	float w = h * h;
	float t = TIME * 2.4;
	VERTEX.x += sin(t + VERTEX.y * 7.0 + VERTEX.z * 3.0) * 0.018 * w * sway;
	VERTEX.z += cos(t * 0.8 + VERTEX.y * 5.0 + VERTEX.x * 4.0) * 0.014 * w * sway;
	VERTEX -= drag * w * 0.22;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(COLOR.rgb, vec3(0.0), ghost * 0.7);
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	EMISSION = rim_color * fres * (rim_strength + ghost * 3.0)
		+ COLOR.rgb * glow_color * COLOR.a * glow_strength
		+ vec3(flash);
}
