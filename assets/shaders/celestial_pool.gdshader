shader_type canvas_item;
render_mode blend_add, unshaded;

// Charco de luz sobre el suelo (y pequeno foco en el techo).
// La forma elipse viene del tamano del Polygon2D que usa este material.
// Las coordenadas se derivan de VERTEX porque los UV del Polygon2D
// no llegan al shader cuando el nodo no tiene textura.

uniform vec2 rect_half_size = vec2(65.0, 35.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.91, 0.68, 1.0);
uniform float intensity : hint_range(0.0, 2.0, 0.01) = 0.55;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float core_size : hint_range(0.0, 0.5, 0.01) = 0.12;
uniform float core_softness : hint_range(0.05, 0.6, 0.01) = 0.26;
uniform float pulse_speed : hint_range(0.0, 4.0, 0.01) = 0.55;

varying vec2 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 uv = clamp(v_local / (2.0 * rect_half_size) + 0.5, vec2(0.0), vec2(1.0));
	vec2 p = uv - 0.5;
	float d = length(p) * 2.0; // 0 en el centro, 1 en el borde

	float halo = pow(max(0.0, 1.0 - d), 2.2);
	float core = 1.0 - smoothstep(core_size, core_size + core_softness, d);
	float pulse = 0.95 + 0.05 * sin(TIME * pulse_speed);

	// Nucleo mas blando y algo menos peso para que la suma con el beam
	// no sature en la zona de transicion.
	float a = (halo * 0.70 + core * 0.34) * intensity * pulse;

	COLOR = vec4(glow_color.rgb * a * opacity, 1.0);
}
