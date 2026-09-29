shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_disabled;

uniform sampler2D grain : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_size_meters : hint_range(1.0, 16.0) = 2.0;
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform float tone_gain : hint_range(0.25, 1.25) = 1.0;
uniform bool unfolded_coordinates = false;
uniform bool local_coordinates = false;
varying vec2 surface_world;

void vertex() {
	surface_world = unfolded_coordinates ? UV : (local_coordinates ? VERTEX.xz : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz);
}

void fragment() {
	// Imported sculpted terrain can expose back-facing triangles after the Maya
	// axis conversion. Orient those normals toward the visible side so local
	// lights affect the painted surface consistently.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec2 world_uv = surface_world / tile_size_meters;
	// 仅在周期边缘2%内交接，内部保持单次采样，不混合整幅笔触。
	vec2 p = fract(world_uv);
	vec2 uv = p * 0.96 + 0.02;
	vec2 edge = 0.5 * (1.0 - smoothstep(vec2(0.0), vec2(0.02), min(p, 1.0 - p)));
	vec2 other = uv + mix(vec2(0.96), vec2(-0.96), step(vec2(0.5), p));
	vec2 dx = dFdx(world_uv) * 0.96;
	vec2 dy = dFdy(world_uv) * 0.96;
	vec3 color = textureGrad(grain, uv, dx, dy).rgb;
	if (edge.x > 0.0) {
		color = mix(color, textureGrad(grain, vec2(other.x, uv.y), dx, dy).rgb, edge.x);
	}
	if (edge.y > 0.0) {
		vec3 opposite = textureGrad(grain, vec2(uv.x, other.y), dx, dy).rgb;
		if (edge.x > 0.0) {
			opposite = mix(opposite, textureGrad(grain, other, dx, dy).rgb, edge.x);
		}
		color = mix(color, opposite, edge.y);
	}
	ALBEDO = color * surface_tint.rgb * tone_gain;
	ROUGHNESS = 0.96;
}
