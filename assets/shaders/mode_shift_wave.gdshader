shader_type canvas_item;

// Expanding radial ripple for the dream / nightmare shift.
// Only the wave band is opaque: the rest of the screen is left untouched, so
// the HUD (drawn on higher canvas layers) is never distorted. The band samples
// the frame captured by the BackBufferCopy to warp the world, and always draws
// a bright crest so the shift reads clearly even if screen sampling is weak.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float aspect = 1.7778;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 wave_color : source_color = vec4(0.5, 0.85, 1.0, 1.0);
uniform float wave_width : hint_range(0.02, 0.6) = 0.24;
uniform float displacement : hint_range(0.0, 0.2) = 0.08;
uniform float chromatic : hint_range(0.0, 0.05) = 0.012;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Aspect-corrected distance keeps the ring circular at any window size.
	vec2 delta = uv - center;
	vec2 metric = delta * vec2(aspect, 1.0);
	float dist = length(metric);
	vec2 dir = dist > 0.0001 ? metric / dist : vec2(0.0);
	vec2 uv_dir = vec2(dir.x / aspect, dir.y);

	// Start the ring just off-screen and always reach the farthest corner.
	vec2 corner = max(abs(center), abs(vec2(1.0) - center));
	float max_dist = length(corner * vec2(aspect, 1.0));
	float radius = -wave_width + progress * (max_dist + 2.0 * wave_width);

	float x = (dist - radius) / wave_width;
	float band = exp(-x * x * 2.0);
	float wake = exp(-pow(x + 1.6, 2.0) * 1.4) * 0.35;
	float envelope = clamp(band + wake, 0.0, 1.0);
	float wave = envelope * sin(x * 6.28318);

	// Fade in/out so the overlay never pops at the ends of the animation.
	float time_fade = smoothstep(0.0, 0.05, progress) * (1.0 - smoothstep(0.88, 1.0, progress));
	float amount = wave * displacement * intensity * time_fade;
	vec2 warped = clamp(uv + uv_dir * amount, vec2(0.001), vec2(0.999));

	// Chromatic aberration rides the same wave.
	float split = chromatic * envelope * intensity * time_fade;
	vec2 ca = uv_dir * split;
	vec3 col;
	col.r = texture(screen_tex, clamp(warped + ca, vec2(0.001), vec2(0.999))).r;
	col.g = texture(screen_tex, warped).g;
	col.b = texture(screen_tex, clamp(warped - ca, vec2(0.001), vec2(0.999))).b;

	// Luminous crest tinted with the destination world's color.
	float crest = exp(-x * x * 8.0) * time_fade * intensity;
	col = mix(col, wave_color.rgb, clamp(crest * 0.75, 0.0, 0.85));
	col += wave_color.rgb * crest * 0.25;

	// Transparent outside the band: only the ripple touches the frame.
	float alpha = clamp(envelope * time_fade * intensity * 0.95, 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
