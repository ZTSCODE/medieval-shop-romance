shader_type canvas_item;

uniform float selection : hint_range(0.0, 1.0) = 0.0;
uniform vec3 normal_tint = vec3(0.886, 0.895, 0.903);
uniform vec3 selected_color = vec3(0.407, 0.384, 0.333);
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	vec4 paper = texture(TEXTURE, UV);
	float luminance = dot(paper.rgb, vec3(0.299, 0.587, 0.114));
	vec3 selected = selected_color * (luminance / 0.203);
	COLOR = item_tint * vec4(mix(paper.rgb * normal_tint, selected, selection), paper.a);
}
