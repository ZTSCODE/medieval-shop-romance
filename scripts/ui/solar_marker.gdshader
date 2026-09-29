shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float distance_to_edge = length(UV - vec2(0.5)) - 0.34;
	float pixel_width = max(fwidth(distance_to_edge), 0.0001);
	float coverage = 1.0 - smoothstep(-pixel_width * 0.5, pixel_width * 0.5, distance_to_edge);
	COLOR.a *= coverage;
}
