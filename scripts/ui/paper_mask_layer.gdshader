shader_type canvas_item;
render_mode unshaded;

uniform sampler2D brush_texture : filter_linear, repeat_enable;
uniform vec4 brush_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 texture_logical_size = vec2(640.0);
uniform vec2 texture_phase = vec2(0.0);
uniform vec2 paper_origin = vec2(0.0);
uniform vec4 paper_tint : source_color = vec4(1.0);
uniform float texture_strength = 0.22;
uniform float texture_neutral = 0.5;
uniform float mask_alpha_gain = 1.0;
uniform int layer_mode = 0;
varying vec2 paper_coordinate;

void vertex() {
	paper_coordinate = (VERTEX - paper_origin) / texture_logical_size + texture_phase;
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	float coverage = clamp(mask.a * mask_alpha_gain, 0.0, 1.0);
	vec3 color = paper_tint.rgb;
	if (layer_mode == 0) {
		if (coverage > 0.85) coverage = 1.0;
		if (coverage < 0.02) coverage = 0.0;
		vec2 brush_uv = brush_region.xy + fract(paper_coordinate) * brush_region.zw;
		float grain = texture(brush_texture, brush_uv).r;
		color *= 1.0 + (grain - texture_neutral) * texture_strength;
	}
	COLOR = vec4(color, coverage * paper_tint.a);
}
