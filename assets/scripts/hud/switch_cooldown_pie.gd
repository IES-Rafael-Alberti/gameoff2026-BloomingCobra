extends Control

## Radial cooldown pie. Parent must be a square matching the switch icon.

var ratio: float = 0.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if is_equal_approx(ratio, next):
			visible = ratio > 0.001
			return
		ratio = next
		visible = ratio > 0.001
		queue_redraw()

@export var fill_color: Color = Color(0.04, 0.06, 0.12, 0.7)
@export var rim_color: Color = Color(0.8, 0.9, 1.0, 0.9)
## Fits the ornate circular frame of the cropped switch icon.
@export var radius_factor: float = 0.48


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = ratio > 0.001
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if ratio <= 0.001:
		return

	# Always use the centered square inside this control (handles non-square parents).
	var side := minf(size.x, size.y)
	if side < 2.0:
		return
	var origin := (size - Vector2(side, side)) * 0.5
	var center := origin + Vector2(side, side) * 0.5
	var radius := side * radius_factor

	var start := -PI * 0.5
	var sweep := TAU * ratio
	var steps := maxi(12, int(ceil(56.0 * ratio)))
	var points := PackedVector2Array()
	points.append(center)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var angle := start + sweep * t
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	draw_colored_polygon(points, fill_color)

	if ratio < 0.999:
		var tip := center + Vector2(cos(start + sweep), sin(start + sweep)) * radius
		draw_line(center, tip, rim_color, 1.75, true)
