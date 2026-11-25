shader_type canvas_item;

// Radial cooldown pie for a ColorRect overlay (no icon sampling).
// cooldown 1 = full cover, 0 = hidden. Sweeps clockwise from the top.
uniform float cooldown : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.72;
uniform float radius : hint_range(0.2, 0.7) = 0.48;
uniform float edge_softness : hint_range(0.0, 0.08) = 0.02;
uniform float rim_glow : hint_range(0.0, 1.0) = 0.7;
uniform vec4 shade_color : source_color = vec4(0.03, 0.05, 0.1, 1.0);
uniform vec4 rim_color : source_color = vec4(0.75, 0.88, 1.0, 1.0);

void fragment() {
	if (cooldown <= 0.001) {
		COLOR = vec4(0.0);
		return;
	}

	vec2 centered = UV - vec2(0.5);
	float dist = length(centered);

	// Soft disc so the overlay follows the round icon, not a square.
	float disc = 1.0 - smoothstep(radius - 0.04, radius, dist);
	if (disc <= 0.001) {
		COLOR = vec4(0.0);
		return;
	}

	// 0 at top, increases clockwise.
	float angle = atan(centered.x, -centered.y);
	float normalized = angle / TAU;
	if (normalized < 0.0) {
		normalized += 1.0;
	}

	float soft = max(edge_softness, 0.0001);
	float in_cd = 1.0 - smoothstep(cooldown - soft, cooldown + soft, normalized);
	if (cooldown >= 0.999) {
		in_cd = 1.0;
	}

	float alpha = in_cd * disc * opacity;

	// Leading sweep rim.
	float rim = 1.0 - smoothstep(0.0, soft * 2.5, abs(normalized - cooldown));
	rim *= step(0.001, cooldown) * step(cooldown, 0.999) * disc;

	vec3 rgb = mix(shade_color.rgb, rim_color.rgb, rim * rim_glow);
	COLOR = vec4(rgb, alpha + rim * rim_glow * 0.35);
}
