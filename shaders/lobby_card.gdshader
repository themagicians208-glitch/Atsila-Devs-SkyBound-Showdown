shader_type canvas_item;

// Pillowy mode-select card: vertical pastel gradient, thick navy rounded
// border, and a soft white glow that fades in on hover/focus.

uniform vec4 top_color : source_color = vec4(1.0, 0.97, 0.90, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.75, 0.94, 0.78, 1.0);
uniform vec4 border_color : source_color = vec4(0.17, 0.11, 0.36, 1.0);
uniform float radius = 32.0;
uniform float border = 4.0;
uniform vec2 rect_size = vec2(380.0, 470.0);
uniform float glow = 0.0;

void fragment() {
	vec2 p = UV * rect_size;
	vec2 h = rect_size * 0.5;
	vec2 d = abs(p - h) - (h - vec2(radius));
	float sdf = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
	float aa = 1.5;
	float inside = 1.0 - smoothstep(-aa, aa, sdf);
	float inner = 1.0 - smoothstep(-aa, aa, sdf + border);
	vec3 fill = mix(top_color.rgb, bottom_color.rgb, UV.y);
	vec3 col = mix(border_color.rgb, fill, inner);
	col += glow * 0.30 * inside;
	COLOR = vec4(col, top_color.a * inside);
}