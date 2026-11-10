shader_type canvas_item;

## Progressive green reveal over transparent empty.
## Starts at top center, fills counterclockwise.
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	vec2 centered = UV - vec2(0.5);

	// Keep original texture transparency (so empty areas of the PNG stay clear).
	if (col.a < 0.01) {
		COLOR = col;
		return;
	}

	float angle = atan(centered.x, -centered.y); // 0 at top
	float normalized = -angle / TAU;
	if (normalized < 0.0) {
		normalized += 1.0;
	}

	// Outside the charged wedge → fully transparent so empty shows through.
	if (progress <= 0.001 || normalized > progress) {
		col.a = 0.0;
	}

	COLOR = col;
}
