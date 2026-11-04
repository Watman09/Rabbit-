// Dash afterimage: additive fresnel silhouette.
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;
uniform float alpha = 1.0;
uniform vec3 color : source_color = vec3(0.9, 0.1, 0.4);
void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	ALBEDO = color * (0.12 + fres * 1.4) * alpha;
}
