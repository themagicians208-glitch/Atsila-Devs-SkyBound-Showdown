shader_type canvas_item;

// Diagonal two-tone stripe fill for the loading bar. The stripes scroll
// horizontally so the bar always looks "busy" while loading.

uniform vec4 blue_a : source_color = vec4(0.22, 0.56, 0.94, 1.0);
uniform vec4 blue_b : source_color = vec4(0.47, 0.76, 1.0, 1.0);
uniform float stripe_width : hint_range(0.01, 0.5) = 0.09;
uniform float scroll_speed = 0.7;

void fragment() {
	float d = (UV.x + UV.y) / stripe_width + TIME * scroll_speed;
	float s = step(0.5, fract(d));
	COLOR = mix(blue_a, blue_b, s);
}