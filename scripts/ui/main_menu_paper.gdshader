shader_type canvas_item;
#include "res://assets/shaders/painted_canvas_color.gdshaderinc"

uniform float selection : hint_range(0.0, 1.0) = 0.0;
uniform vec3 normal_tint = vec3(0.886, 0.895, 0.903);
uniform vec3 selected_color = vec3(0.407, 0.384, 0.333);
// 按当前纸张纹理标定，保持与概念图的灰橄榄高亮一致。
uniform float paper_reference_luma = 0.218;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	vec4 paper = texture(TEXTURE, UV);
	paper.rgb = paint_input(paper.rgb);
	float luminance = dot(paper.rgb, vec3(0.299, 0.587, 0.114));
	vec3 selected = selected_color * (luminance / paper_reference_luma);
	COLOR = item_tint * vec4(paint_output(mix(paper.rgb * normal_tint, selected, selection)), paper.a);
}
