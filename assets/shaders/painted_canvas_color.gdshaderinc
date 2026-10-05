// 手绘配色在 sRGB 中标定；HDR 画布采样及输出采用线性颜色。
uniform bool linear_canvas = true;

vec3 paint_to_srgb(vec3 color) {
	vec3 c = max(color, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 paint_to_linear(vec3 color) {
	vec3 c = max(color, vec3(0.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 paint_input(vec3 color) {
	return linear_canvas ? paint_to_srgb(color) : color;
}

vec3 paint_output(vec3 color) {
	return linear_canvas ? paint_to_linear(color) : color;
}
