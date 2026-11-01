shader_type spatial;
render_mode unshaded, cull_disabled;

// Paints the limb masks that racoon_body.gdshader would bend, so a rig can be
// tuned against the model: red = left arm, blue = right arm, green = legs.
// Takes the same uniform names, so it can be dropped in over an existing
// ShaderMaterial and keeps its parameters.

uniform vec3 u_y_vec = vec3(0.0, 1.0, 0.0);
uniform float u_y_off = 0.0;
uniform vec3 u_side_vec = vec3(0.0, 0.0, 1.0);
uniform float u_side_off = 0.0;
uniform float u_arm_y0 = 0.96;
uniform float u_arm_y1 = 1.22;
uniform float u_arm_y2 = 1.56;
uniform float u_arm_y3 = 1.72;
uniform float u_arm_x_in = 0.44;
uniform float u_arm_x_out = 0.86;
uniform float u_arm_x_far = 0.0;
uniform float u_leg_y0 = 0.36;
uniform float u_leg_y1 = 0.70;
uniform float u_leg_split = 0.16;
uniform float u_do_arms = 1.0;
uniform float u_do_legs = 0.0;

void vertex() {
	float model_y = dot(VERTEX, u_y_vec) + u_y_off;
	float model_side = dot(VERTEX, u_side_vec) + u_side_off;

	float band = smoothstep(u_arm_y0, u_arm_y1, model_y)
			* (1.0 - smoothstep(u_arm_y2, u_arm_y3, model_y));
	float far = 1.0;
	if (u_arm_x_far > 0.0) {
		far = 1.0 - smoothstep(u_arm_x_far - 2.5, u_arm_x_far, abs(model_side));
	}
	float arm_l = (1.0 - smoothstep(-u_arm_x_out, -u_arm_x_in, model_side)) * band * u_do_arms * far;
	float arm_r = smoothstep(u_arm_x_in, u_arm_x_out, model_side) * band * u_do_arms * far;
	float leg = (1.0 - smoothstep(u_leg_y0, u_leg_y1, model_y)) * u_do_legs;

	vec3 tint = mix(vec3(0.30, 0.30, 0.34), vec3(1.0, 0.15, 0.15), arm_l);
	tint = mix(tint, vec3(0.20, 0.55, 1.0), arm_r);
	tint = mix(tint, vec3(0.25, 1.0, 0.30), leg);
	COLOR.rgb = tint;
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
