shader_type canvas_item;

uniform vec2 art_origin;
uniform vec2 art_size = vec2(1.0);
uniform vec2 source_size = vec2(1.0);
uniform vec4 atmosphere_tint : source_color = vec4(0.51, 0.49, 0.45, 1.0);
uniform float atmosphere_strength = 0.012;
uniform float exposure_scale = 0.985;
uniform sampler2D type_paper_profile : filter_linear, repeat_disable;
uniform vec2 face_origin;
uniform vec2 face_size = vec2(168.0, 236.0);

varying vec2 edge_uv;
varying vec2 face_uv;

void vertex() {
	edge_uv = (VERTEX - art_origin) / max(art_size, vec2(0.001));
	face_uv = (VERTEX - face_origin) / face_size;
}

void fragment() {
	COLOR.rgb *= mix(vec3(1.0), atmosphere_tint.rgb, atmosphere_strength) * exposure_scale;
	vec2 pixel = clamp(edge_uv, vec2(0.0), vec2(1.0)) * source_size;
	vec2 border = min(pixel, source_size - vec2(1.0) - pixel);
	float distance_to_edge = min(min(border.x, border.y), min(source_size.x, source_size.y));
	float band = max(6.0, floor(source_size.x * 0.016));
	// Profile traced from the reference paper contour: a gently uneven side
	// and a short rounded return at the bottom, without a diagonal cut.
	float profile_y = clamp((face_uv.y - 0.10) / 0.10, 0.0, 1.0);
	float paper_right = texture(type_paper_profile, vec2(profile_y, 0.5)).r * face_size.x;
	float face_x = face_uv.x * face_size.x;
	float shoulder = smoothstep(paper_right - 0.35, paper_right + 0.35, face_x);
	float stroke = 0.14 * sin(pixel.x * 0.091 + pixel.y * 0.044) + 0.10 * sin(pixel.x * 0.031 - pixel.y * 0.085);
	float opacity = smoothstep(0.12 + stroke, 0.80 + stroke, distance_to_edge / band);
	COLOR.a *= opacity * shoulder;
}
