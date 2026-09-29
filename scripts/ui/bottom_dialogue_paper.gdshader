shader_type canvas_item;
render_mode unshaded;

uniform sampler2D brush_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile_size = 420.0;
uniform vec3 paper_tone = vec3(1.0);
varying vec2 paper_position;
varying vec4 sheet_tint;

void vertex() {
	paper_position = VERTEX;
	sheet_tint = COLOR;
}

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	vec2 sample_uv = paper_position / tile_size;
	vec2 local = fract(sample_uv);
	vec2 inset_uv = local * 0.96 + 0.02;
	vec2 blend = 0.5 * (1.0 - smoothstep(vec2(0.0), vec2(0.02), min(local, 1.0 - local)));
	vec2 other_uv = inset_uv + mix(vec2(0.96), vec2(-0.96), step(vec2(0.5), local));
	vec2 dx = dFdx(sample_uv) * 0.96;
	vec2 dy = dFdy(sample_uv) * 0.96;
	vec3 brush = textureGrad(brush_texture, inset_uv, dx, dy).rgb;
	brush = mix(brush, textureGrad(brush_texture, vec2(other_uv.x, inset_uv.y), dx, dy).rgb, blend.x);
	vec3 opposite = mix(textureGrad(brush_texture, vec2(inset_uv.x, other_uv.y), dx, dy).rgb, textureGrad(brush_texture, other_uv, dx, dy).rgb, blend.x);
	brush = mix(brush, opposite, blend.y);
	COLOR = vec4(brush * paper_tone * sheet_tint.rgb, smoothstep(0.05, 0.95, mask.a) * sheet_tint.a);
}
