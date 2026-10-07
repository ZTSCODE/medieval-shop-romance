shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/painted_canvas_color.gdshaderinc"

uniform vec2 bar_size = vec2(168.0, 18.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;

float capsule(vec2 p, vec2 half_size) {
	float radius = half_size.y;
	vec2 q = abs(p) - (half_size - vec2(radius));
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 size = max(bar_size, vec2(1.0));
	vec2 p = UV * size;
	float scale = size.y / 18.0;
	float inset = 0.85 * scale;
	vec2 half_size = size * 0.5 - vec2(inset);
	// Stable, sparse pen wobble; no time noise that makes the outline crawl.
	vec2 brush = p / max(scale, 0.1);
	float wobble = (sin(brush.x * 0.27 + brush.y * 0.39) * 0.20
		+ sin(brush.x * 0.63 - brush.y * 0.32) * 0.10) * scale;
	float distance = capsule(p - size * 0.5, half_size) - wobble;
	float aa = max(fwidth(distance) * 0.7, 0.16);
	float coverage = 1.0 - smoothstep(-aa, aa, distance);
	float pen_width = (1.6 + 0.16 * sin(brush.x * 0.17 + brush.y * 0.29)) * scale;
	float interior = 1.0 - smoothstep(-pen_width - aa, -pen_width + aa, distance);
	float padding = inset + pen_width;
	float front = padding + clamp(progress, 0.0, 1.0) * (size.x - padding * 2.0);
	float filled = progress <= 0.0 ? 0.0 : (progress >= 1.0 ? 1.0 : 1.0 - smoothstep(front - aa, front + aa, p.x));
	float brush_value = sin(brush.x * 0.12 + brush.y * 0.41) * 0.012;
	vec3 track = vec3(0.19, 0.17, 0.19) + brush_value * 0.4;
	vec3 paper = vec3(0.90, 0.86, 0.76) + brush_value;
	vec3 color = mix(vec3(0.065, 0.070, 0.068), mix(track, paper, filled), interior);
	COLOR = vec4(paint_output(color), coverage) * COLOR;
}
