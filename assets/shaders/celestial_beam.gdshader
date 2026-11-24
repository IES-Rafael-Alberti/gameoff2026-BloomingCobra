shader_type canvas_item;
render_mode blend_add, unshaded;

// Cono de luz celestial que cae desde el techo de la saferoom.
// Usamos VERTEX en vez de UV: Godot no pasa los UV de un Polygon2D
// al shader si el nodo no tiene textura asignada.

uniform vec2 rect_half_size = vec2(70.0, 110.0);
uniform vec4 beam_color : source_color = vec4(1.0, 0.93, 0.74, 1.0);
uniform float intensity : hint_range(0.0, 1.5, 0.01) = 0.42;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float top_half_width : hint_range(0.01, 0.5, 0.005) = 0.09;
uniform float bottom_half_width : hint_range(0.01, 0.5, 0.005) = 0.37;
uniform float edge_softness : hint_range(0.02, 1.0, 0.01) = 0.55;
uniform float floor_fade_start : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float floor_fade_end : hint_range(0.0, 1.0, 0.01) = 0.94;
uniform float floor_edge_softness : hint_range(1.0, 3.0, 0.01) = 1.7;
uniform float ray_strength : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float flicker_speed : hint_range(0.0, 4.0, 0.01) = 0.45;
uniform float dust_amount : hint_range(0.0, 1.0, 0.01) = 0.35;

varying vec2 v_local;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// Equivalente a UV, pero calculado desde la geometria del poligono.
	vec2 uv = clamp(v_local / (2.0 * rect_half_size) + 0.5, vec2(0.0), vec2(1.0));
	float t = uv.y;

	// Cono: estrecho arriba, ancho abajo. Hacia el suelo los bordes se
	// difuminan mas para que el rayo no termine en una linea dura.
	float half_w = mix(top_half_width, bottom_half_width, smoothstep(0.0, 0.9, t));
	float dx = abs(uv.x - 0.5) / max(half_w, 0.0001);
	float soft = clamp(edge_softness * mix(0.85, floor_edge_softness, t), 0.02, 1.0);
	float cone = 1.0 - smoothstep(1.0 - soft, 1.0, dx);

	// Apagado largo y progresivo: el rayo se funde con el pool en vez de
	// cortarse. Empieza mucho antes del borde del poligono.
	float falloff = 1.0 - smoothstep(floor_fade_start, floor_fade_end, t);
	falloff = pow(falloff, 1.25);
	float vertical = smoothstep(0.0, 0.10, t) * falloff;

	// Rayos tenues que se desplazan muy lentamente.
	float shaft = sin(uv.x * 34.0 + sin(t * 4.0 + TIME * flicker_speed) * 0.8);
	shaft = 1.0 - ray_strength + ray_strength * (shaft * 0.5 + 0.5);

	// Respiracion suave, como una luz viva.
	float pulse = 0.94 + 0.06 * sin(TIME * flicker_speed * 1.6);

	// Polvillo dorado flotando dentro del cono.
	vec2 grid = vec2(7.0, 13.0);
	vec2 cell = floor(uv * grid);
	vec2 local = fract(uv * grid);
	float h = hash21(cell);
	vec2 mote = vec2(
		0.5 + 0.30 * sin(h * 17.0 + TIME * 0.25 + cell.y),
		0.5 + 0.30 * cos(h * 23.0 - TIME * 0.18 + cell.x)
	);
	float mote_glow = 1.0 - smoothstep(0.0, 0.18, length(local - mote));
	mote_glow *= step(0.84, h) * dust_amount;

	// En la zona baja el pool ya aporta luz, asi que el beam cede intensidad
	// para que la suma aditiva no sature ni marque el cambio de superficie.
	float handoff = 1.0 - 0.35 * smoothstep(0.40, 0.90, t);
	float a = cone * vertical * shaft * pulse * intensity * handoff;
	a += mote_glow * cone * vertical * intensity * handoff;

	// Alpha = 1 para que el resultado sea el mismo con ADD/SRC_ALPHA y con ADD/ONE.
	COLOR = vec4(beam_color.rgb * a * opacity, 1.0);
}
