shader_type canvas_item;

uniform vec2 art_origin;
uniform vec2 art_size = vec2(1.0);
uniform vec2 source_size = vec2(1.0);

varying vec2 edge_uv;

void vertex() {
	edge_uv = (VERTEX - art_origin) / max(art_size, vec2(0.001));
}

void fragment() {
	vec2 pixel = clamp(edge_uv, vec2(0.0), vec2(1.0)) * source_size;
	vec2 border = min(pixel, source_size - vec2(1.0) - pixel);
	float distance_to_edge = min(min(border.x, border.y), min(source_size.x, source_size.y));
	float band = max(6.0, floor(source_size.x * 0.016));
	float shoulder = 1.0 - (1.0 - smoothstep(0.11, 0.14, edge_uv.x)) * (1.0 - smoothstep(0.092, 0.115, edge_uv.y));
	float stroke = 0.14 * sin(pixel.x * 0.091 + pixel.y * 0.044) + 0.10 * sin(pixel.x * 0.031 - pixel.y * 0.085);
	float opacity = smoothstep(0.12 + stroke, 0.80 + stroke, distance_to_edge / band);
	COLOR.a *= opacity * shoulder;
}
