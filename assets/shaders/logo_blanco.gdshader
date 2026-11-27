shader_type canvas_item;

//para que sea blanco el png

uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float intensity : hint_range(0, 1) = 1.0;

// Disintegration with a glowing ember front. Animate `dissolve` from 0 (untouched)
// to 1 (completely gone). The hot rim follows the burn line and cools to ember
// toward the untouched pixels.

group_uniforms Dissolve;
uniform vec2 sheet_frames = vec2(1.0, 1.0);   // a sprite sheet: its hframes and vframes, so the effect works per frame
uniform float dissolve : hint_range(0.0, 1.0) = 0.5;
uniform float noise_scale : hint_range(2.0, 64.0) = 22.0;   // size of the burnt patches
uniform float warp : hint_range(0.0, 1.0) = 0.6;             // how organic, curly the edges are
// 0 = the holes open everywhere at once, 1 = the burn sweeps across the sprite
uniform float sweep : hint_range(0.0, 1.0) = 0.0;
uniform float sweep_angle : hint_range(-3.1416, 3.1416) = 1.5708;   // default: from top to bottom
group_uniforms Edge;
uniform float edge_width : hint_range(0.0, 0.25) = 0.10;
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 edge_hot : source_color = vec4(1.0, 0.95, 0.6, 1.0);

float hash(vec2 p) {
	p = fract(p * 0.3183099 + vec2(0.1, 0.113));
	p *= 17.0;
	return fract(p.x * p.y * (p.x + p.y));
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // quintic: no grid creases
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
// rotated octaves hide the square noise grid
float fbm(vec2 p) {
	mat2 r = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = r * p * 2.03 + 11.7;
		a *= 0.5;
	}
	return v / 0.9375;
}

varying vec4 vertex_tint;   // modulate and self_modulate, applied at the end

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 front = texture(TEXTURE, UV);

	//vec4 col = texture(TEXTURE, UV);
	vec4 col = mix(front, vec4(tint_color, front.a), intensity);
	// the UV inside the current frame (1 x 1: the whole texture, as before)
	vec2 fuv = UV * sheet_frames - min(floor(UV * sheet_frames), sheet_frames - 1.0);
	vec2 p = fuv * noise_scale * 0.35;
	// domain warp: the burnt patches get curly, organic outlines
	vec2 w = vec2(fbm(p * 0.7 + 3.1), fbm(p * 0.7 + 8.4)) - 0.5;
	float n = fbm(p + w * warp * 2.5);
	// fbm values bunch up around 0.5: spread them evenly over 0..1 (an approximate
	// normal CDF) so the burn progresses steadily from start to end
	float z = (n - 0.5) / 0.11;
	n = 0.5 + 0.5 * tanh(z * 0.85);
	vec2 dir = vec2(cos(sweep_angle), sin(sweep_angle));
	float g = dot(fuv - 0.5, dir) / (abs(dir.x) + abs(dir.y)) + 0.5;
	n = mix(n, g * 0.75 + n * 0.25, sweep);
	// the cut: 0 keeps every pixel, 1 removes every pixel, whatever the noise
	float thr = mix(-edge_width - 0.02, 1.04, dissolve);
	float aa = min(fwidth(n), 0.02) + 0.001;
	float gone = smoothstep(thr - aa, thr + aa, n);
	// ember hugs the front: hottest at the burn line, cooling outward
	float e = clamp((n - thr) / max(edge_width, 0.0001), 0.0, 1.0);
	vec3 ember = mix(edge_hot.rgb, edge_color.rgb, e);
	col.rgb = mix(col.rgb, ember, (1.0 - e) * gone * step(0.0001, edge_width));
	col.a *= gone;
	COLOR = col;
	COLOR *= vertex_tint;
}
