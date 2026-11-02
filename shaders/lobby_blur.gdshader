shader_type canvas_item;

// Small 3x3 blur of whatever is behind the sub-menu, plus a gentle darkening,
// so the menu buttons stand out from the busy sky world.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float radius = 2.5;
uniform float darkness : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE * radius;
	vec4 c = vec4(0.0);
	c += texture(screen_tex, SCREEN_UV + vec2(-1.0, -1.0) * ps);
	c += texture(screen_tex, SCREEN_UV + vec2( 0.0, -1.0) * ps) * 2.0;
	c += texture(screen_tex, SCREEN_UV + vec2( 1.0, -1.0) * ps);
	c += texture(screen_tex, SCREEN_UV + vec2(-1.0,  0.0) * ps) * 2.0;
	c += texture(screen_tex, SCREEN_UV + vec2( 0.0,  0.0) * ps) * 4.0;
	c += texture(screen_tex, SCREEN_UV + vec2( 1.0,  0.0) * ps) * 2.0;
	c += texture(screen_tex, SCREEN_UV + vec2(-1.0,  1.0) * ps);
	c += texture(screen_tex, SCREEN_UV + vec2( 0.0,  1.0) * ps) * 2.0;
	c += texture(screen_tex, SCREEN_UV + vec2( 1.0,  1.0) * ps);
	c /= 16.0;
	COLOR = vec4(c.rgb * (1.0 - darkness), 1.0);
}