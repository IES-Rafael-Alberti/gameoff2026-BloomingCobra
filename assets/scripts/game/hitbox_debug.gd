extends Node2D

## Draws Area2D / body shapes when debug hitboxes are enabled (F1).

var enabled: bool = false


func _ready() -> void:
	z_index = 100
	set_process(true)


func set_debug_enabled(value: bool) -> void:
	enabled = value
	get_tree().debug_collisions_hint = value
	queue_redraw()


func toggle() -> bool:
	set_debug_enabled(not enabled)
	return enabled


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	var tree := get_tree()
	if tree == null:
		return

	for node in tree.get_nodes_in_group("player_hitbox"):
		_draw_area(node, Color(1.0, 0.2, 0.2, 0.35), Color(1.0, 0.3, 0.3, 0.9))

	for node in tree.get_nodes_in_group("hurtbox"):
		_draw_area(node, Color(0.2, 0.9, 0.3, 0.3), Color(0.1, 1.0, 0.3, 0.9))

	for node in tree.get_nodes_in_group("enemy"):
		_draw_character_shapes(node, Color(1.0, 0.85, 0.1, 0.25), Color(1.0, 0.8, 0.0, 0.85))
		_draw_detection_radius(node, Color(0.85, 0.2, 1.0, 0.12), Color(0.95, 0.35, 1.0, 0.85))

	for node in tree.get_nodes_in_group("prop_breakable"):
		_draw_character_shapes(node, Color(1.0, 0.45, 0.1, 0.3), Color(1.0, 0.55, 0.15, 0.95))
	for node in tree.get_nodes_in_group("prop_hittable"):
		if node.is_in_group("prop_breakable"):
			continue
		_draw_character_shapes(node, Color(1.0, 0.45, 0.1, 0.3), Color(1.0, 0.55, 0.15, 0.95))

	var player := tree.get_first_node_in_group("player")
	if player != null:
		_draw_character_shapes(player, Color(0.2, 0.5, 1.0, 0.25), Color(0.3, 0.6, 1.0, 0.9))


func _draw_character_shapes(node: Node, fill: Color, outline: Color) -> void:
	if node is CollisionObject2D:
		for child in node.get_children():
			if child is CollisionShape2D and not child.disabled:
				_draw_shape(child as CollisionShape2D, fill, outline)


func _draw_detection_radius(node: Node, fill: Color, outline: Color) -> void:
	if node == null or not node.has_method("get_detection_debug_radius"):
		return
	var radius: float = float(node.call("get_detection_debug_radius"))
	if radius <= 0.0:
		return
	if not (node is Node2D):
		return
	var center: Vector2 = get_global_transform().affine_inverse() * (node as Node2D).global_position
	draw_circle(center, radius, fill)
	draw_arc(center, radius, 0.0, TAU, 48, outline, 1.0)


func _draw_area(area: Node, fill: Color, outline: Color) -> void:
	if area == null or not (area is Area2D):
		return
	if not (area as Area2D).monitoring and not (area as Area2D).monitorable:
		# Still draw inactive hitboxes faintly while debugging.
		fill.a *= 0.45
		outline.a *= 0.55
	for child in area.get_children():
		if child is CollisionShape2D and not child.disabled:
			_draw_shape(child as CollisionShape2D, fill, outline)
		elif child is CollisionPolygon2D:
			_draw_polygon_shape(child as CollisionPolygon2D, fill, outline)


func _draw_shape(shape_node: CollisionShape2D, fill: Color, outline: Color) -> void:
	var shape := shape_node.shape
	if shape == null:
		return
	var xf: Transform2D = shape_node.get_global_transform()
	var local_xf := get_global_transform().affine_inverse() * xf

	if shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		var half := rect.size * 0.5
		var pts := PackedVector2Array([
			local_xf * Vector2(-half.x, -half.y),
			local_xf * Vector2(half.x, -half.y),
			local_xf * Vector2(half.x, half.y),
			local_xf * Vector2(-half.x, half.y),
		])
		draw_colored_polygon(pts, fill)
		for i in pts.size():
			draw_line(pts[i], pts[(i + 1) % pts.size()], outline, 1.0)
	elif shape is CircleShape2D:
		var circle := shape as CircleShape2D
		var center := local_xf * Vector2.ZERO
		var radius := circle.radius * maxf(local_xf.get_scale().x, local_xf.get_scale().y)
		draw_circle(center, radius, fill)
		draw_arc(center, radius, 0.0, TAU, 24, outline, 1.0)


func _draw_polygon_shape(poly: CollisionPolygon2D, fill: Color, outline: Color) -> void:
	if poly.polygon.is_empty():
		return
	var xf: Transform2D = poly.get_global_transform()
	var local_xf := get_global_transform().affine_inverse() * xf
	var pts := PackedVector2Array()
	for p in poly.polygon:
		pts.append(local_xf * p)
	if pts.size() >= 3:
		draw_colored_polygon(pts, fill)
		for i in pts.size():
			draw_line(pts[i], pts[(i + 1) % pts.size()], outline, 1.0)
