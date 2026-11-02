shader_type canvas_item;

// Scrolls the waterfall texture downward so the streaks appear to flow.
// The host TextureRect should have texture_repeat enabled so the offset tiles.

uniform float speed = 0.45;

void fragment() {
	COLOR = texture(TEXTURE, vec2(UV.x, UV.y + TIME * speed));
}