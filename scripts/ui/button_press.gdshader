shader_type canvas_item;
uniform float press_amount = 1.0;
uniform vec2 press_center = vec2(0.0);
void vertex() {
	VERTEX = press_center + (VERTEX - press_center) * press_amount;
}
