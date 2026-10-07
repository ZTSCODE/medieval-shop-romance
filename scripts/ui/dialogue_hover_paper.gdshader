shader_type canvas_item;
#include "res://assets/shaders/painted_canvas_color.gdshaderinc"
varying vec4 item_tint;
void vertex() { item_tint = COLOR; }
void fragment() {
	vec4 paper = texture(TEXTURE, UV);
	vec3 source = paint_input(paper.rgb);
	// 与顶部标签统一灰红褐色；保留新按钮自己的纹理与轮廓。
	vec3 warm_paper = source * vec3(1.225, 1.014, 0.912);
	COLOR = vec4(paint_output(warm_paper), paper.a) * item_tint;
}
