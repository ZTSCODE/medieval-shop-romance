shader_type canvas_item;
uniform float selection : hint_range(0.0, 1.0) = 0.0;
uniform vec3 paper_color = vec3(0.274,0.236,0.228);
uniform vec3 selected_color = vec3(0.407,0.384,0.333);
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	vec4 original = texture(TEXTURE, UV);
	float luminance = dot(original.rgb, vec3(0.299, 0.587, 0.114));
	vec3 brown = original.rgb;
	vec3 selected = selected_color * (luminance / 0.24);
	COLOR = item_tint * vec4(mix(brown,selected,selection),original.a);
}
