shader_type canvas_item;

// Brief white wash over opaque pixels (charge-ready feedback).
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	float f = flash * col.a;
	col.rgb = mix(col.rgb, flash_color.rgb, f);
	col.rgb += flash_color.rgb * (f * 0.55);
	COLOR = col;
}
