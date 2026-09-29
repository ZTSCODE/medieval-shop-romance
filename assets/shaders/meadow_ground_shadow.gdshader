shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
varying float seed;
void vertex() { seed = INSTANCE_CUSTOM.r; }
void fragment() {
	vec2 at = (UV - vec2(0.5)) * 2.0;
	float angle = atan(at.y, at.x);
	float contour = 1.0 + 0.08 * sin(angle * 3.0 + seed * 6.28318) + 0.045 * cos(angle * 5.0);
	float radius = length(at) / contour;
	float soft = 1.0 - smoothstep(0.12, 0.98, radius);
	ALBEDO = vec3(0.035, 0.047, 0.044);
	ALPHA = soft * 0.31;
}
