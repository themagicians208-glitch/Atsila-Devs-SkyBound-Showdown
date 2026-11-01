shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Limb animation for the raccoon body.
//
// The body, both arms and both legs are ONE fused mesh, so the limbs cannot be
// animated as separate nodes. Instead this shader bends the vertices that belong
// to each arm / leg around its joint, with a soft falloff so the mesh never tears
// where a limb meets the torso.
//
// Vertex positions arrive in the MESH's own space. The uniforms below convert
// between that space and the model space the joint positions were measured in.

// --- appearance ---
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;

// --- model-space extraction (row of the mesh->model basis) ---
uniform vec3 u_y_vec = vec3(0.0, 1.0, 0.0);
uniform float u_y_off = 0.0;
uniform vec3 u_side_vec = vec3(0.0, 0.0, 1.0);
uniform float u_side_off = 0.0;

// --- limb masks, in model space, measured from the body centre ---
// Each character configures these in its own units (see the subclasses of
// character_style.gd), so a single shader rigs all of them.
uniform float u_arm_y0 = 0.96;     // arm band: fades in from y0 to y1 ...
uniform float u_arm_y1 = 1.22;
uniform float u_arm_y2 = 1.56;     // ... and back out from y2 to y3
uniform float u_arm_y3 = 1.72;
uniform float u_arm_x_in = 0.44;   // |side| where the arm weight starts rising
uniform float u_arm_x_out = 0.86;  // |side| where it is full
// ... and where it fades out again. Some models (isabelle's long hair) hang down
// into the same height band as the arms, further out than the hands, so the arm
// mask needs an outer edge as well as an inner one. 0 or below switches it off.
uniform float u_arm_x_far = 0.0;
// The arm drop and flap are mirrored per arm, which is right for a model whose
// arms stick out along the side axis (the raccoon). A model whose arms run along
// that axis instead (isabelle) needs both arms moved the same way: set this to -1.
uniform float u_arm_flap_mirror = 1.0;
uniform float u_leg_y0 = 0.36;     // complete leg weight below y0
uniform float u_leg_y1 = 0.70;     // none above y1
uniform float u_leg_split = 0.16;  // half-width of the gap between the legs
uniform float u_leg_side = 0.33;   // side offset of each hip
uniform float u_do_arms = 1.0;     // which masks apply to this mesh
uniform float u_do_legs = 1.0;

// --- joints converted into mesh-local space ---
uniform vec3 u_leg_pivot_l = vec3(0.0);
uniform vec3 u_leg_pivot_r = vec3(0.0);
uniform vec3 u_arm_pivot_l = vec3(0.0);
uniform vec3 u_arm_pivot_r = vec3(0.0);
uniform vec3 u_axis_left_right = vec3(0.0, 0.0, 1.0);
uniform vec3 u_axis_up = vec3(0.0, 1.0, 0.0);
uniform vec3 u_axis_front_back = vec3(1.0, 0.0, 0.0);
uniform vec3 u_up_local = vec3(0.0, 1.0, 0.0);

// --- pose ---
uniform float u_leg_swing = 0.0;
uniform float u_arm_swing = 0.0;
// Both arms driving the same way (a slash reaching forward, or pulling back),
// where u_arm_swing is the walking stride and therefore opposite per arm.
uniform float u_arm_reach = 0.0;
uniform float u_crouch = 0.0;
// Arms lifting / dropping and legs splaying. These move sideways in screen space,
// so they stay readable from the game camera, which sits behind the player.
uniform float u_arm_flap = 0.0;
uniform float u_leg_splay = 0.0;
// The model is sculpted with its arms stuck out to the sides. This rotates them
// down so they hang at the character's sides, which is the resting pose.
uniform float u_arm_drop = -1.30;


vec3 rotate_about(vec3 p, vec3 pivot, vec3 axis, float angle) {
	vec3 q = p - pivot;
	float c = cos(angle);
	float s = sin(angle);
	return q * c + cross(axis, q) * s + axis * dot(axis, q) * (1.0 - c) + pivot;
}


vec3 rotate_dir(vec3 v, vec3 axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}


void vertex() {
	// Where is this vertex in model space?
	float model_y = dot(VERTEX, u_y_vec) + u_y_off;
	float model_side = dot(VERTEX, u_side_vec) + u_side_off;

	// The fade at the outer end only applies when a character sets it.
	float arm_far = 1.0;
	if (u_arm_x_far > 0.0) {
		arm_far = 1.0 - smoothstep(u_arm_x_far - 2.5, u_arm_x_far, abs(model_side));
	}

	// Arms: out past the shoulders and at shoulder height.
	float arm_band = smoothstep(u_arm_y0, u_arm_y1, model_y)
			* (1.0 - smoothstep(u_arm_y2, u_arm_y3, model_y));
	float arm_l = (1.0 - smoothstep(-u_arm_x_out, -u_arm_x_in, model_side)) * arm_band * u_do_arms * arm_far;
	float arm_r = smoothstep(u_arm_x_in, u_arm_x_out, model_side) * arm_band * u_do_arms * arm_far;

	// Legs: below the hips, split either side of centre.
	float leg_mask = (1.0 - smoothstep(u_leg_y0, u_leg_y1, model_y)) * u_do_legs;
	float leg_l = leg_mask * (1.0 - smoothstep(-u_leg_split, u_leg_split, model_side));
	float leg_r = leg_mask * smoothstep(-u_leg_split, u_leg_split, model_side);

	vec3 p = VERTEX;
	vec3 n = NORMAL;

	// Arms: first drop them from the sculpted out-to-the-side pose so they hang
	// down, then swing them forward / back from there.
	if (arm_l > 0.001) {
		float drop = (u_arm_drop + u_arm_flap) * arm_l;
		p = rotate_about(p, u_arm_pivot_l, u_axis_front_back, drop);
		n = rotate_dir(n, u_axis_front_back, drop);
	}
	if (arm_r > 0.001) {
		float drop = -(u_arm_drop + u_arm_flap) * arm_r * u_arm_flap_mirror;
		p = rotate_about(p, u_arm_pivot_r, u_axis_front_back, drop);
		n = rotate_dir(n, u_axis_front_back, drop);
	}

	// A hanging arm swings forward / back about the left-right axis at the shoulder.
	// u_arm_swing is the stride, so it opposes the two arms; u_arm_reach moves them
	// the same way, which is what a slash needs.
	if (arm_l > 0.001) {
		float a = (u_arm_swing - u_arm_reach) * arm_l;
		p = rotate_about(p, u_arm_pivot_l, u_axis_left_right, a);
		n = rotate_dir(n, u_axis_left_right, a);
	}
	if (arm_r > 0.001) {
		float a = (-u_arm_swing - u_arm_reach) * arm_r;
		p = rotate_about(p, u_arm_pivot_r, u_axis_left_right, a);
		n = rotate_dir(n, u_axis_left_right, a);
	}

	// Legs swing forward / back (about the left-right axis at each hip).
	if (leg_l > 0.001) {
		float a = u_leg_swing * leg_l;
		p = rotate_about(p, u_leg_pivot_l, u_axis_left_right, a);
		n = rotate_dir(n, u_axis_left_right, a);
	}
	if (leg_r > 0.001) {
		float a = -u_leg_swing * leg_r;
		p = rotate_about(p, u_leg_pivot_r, u_axis_left_right, a);
		n = rotate_dir(n, u_axis_left_right, a);
	}

	// ... and step slightly wider / narrower, which also reads from behind.
	if (leg_l > 0.001) {
		float a = u_leg_splay * leg_l;
		p = rotate_about(p, u_leg_pivot_l, u_axis_front_back, a);
		n = rotate_dir(n, u_axis_front_back, a);
	}
	if (leg_r > 0.001) {
		float a = -u_leg_splay * leg_r;
		p = rotate_about(p, u_leg_pivot_r, u_axis_front_back, a);
		n = rotate_dir(n, u_axis_front_back, a);
	}

	// Tuck the legs up a little while airborne.
	p += u_up_local * (u_crouch * leg_mask);

	VERTEX = p;
	NORMAL = n;
}


void fragment() {
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.2;
}