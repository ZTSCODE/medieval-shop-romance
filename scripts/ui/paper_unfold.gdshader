shader_type canvas_item;

varying vec4 item_color;

void vertex() {
	item_color = COLOR;
}

void fragment() {
	vec4 paper = texture(TEXTURE, UV);
	if (paper.a < 0.045) {
		paper.a = 0.0;
	} else {
		paper.a = mix(paper.a, 1.0, smoothstep(0.76, 0.85, paper.a));
	}
	COLOR = item_color * paper;
}
