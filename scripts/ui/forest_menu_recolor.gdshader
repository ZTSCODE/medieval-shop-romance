shader_type canvas_item;
#include "res://assets/shaders/painted_canvas_color.gdshaderinc"
uniform float selection : hint_range(0.0, 1.0) = 0.0;
uniform vec3 paper_color = vec3(0.274,0.236,0.228);
uniform vec3 selected_color = vec3(0.407,0.384,0.333);
// 通用按钮纸张与主菜单纸张不同，分别标定纹理基准亮度。
uniform float paper_reference_luma = 0.219;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	vec4 original = texture(TEXTURE, UV);
	original.rgb = paint_input(original.rgb);
	float luminance = dot(original.rgb, vec3(0.299, 0.587, 0.114));
	vec3 brown = original.rgb;
	vec3 selected = selected_color * (luminance / paper_reference_luma);
	COLOR = item_tint * vec4(paint_output(mix(brown,selected,selection)),original.a);
}
