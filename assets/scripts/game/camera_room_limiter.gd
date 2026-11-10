extends Camera2D

@export var room_detect_margin: float = 8.0

var _current_room: Node2D = null


func _ready() -> void:
	limit_enabled = true
	call_deferred("_refresh_room")


func _physics_process(_delta: float) -> void:
	_refresh_room()


func _refresh_room() -> void:
	var player := get_parent() as Node2D
	if player == null:
		return

	var room := _find_room_at(player.global_position)
	if room == _current_room:
		return

	var previous := _current_room
	_current_room = room

	if previous != null and previous.has_method("set_active"):
		previous.set_active(false, player)
	if room != null and room.has_method("set_active"):
		room.set_active(true, player)
		_apply_bounds(room)


func _find_room_at(point: Vector2) -> Node2D:
	var best: Node2D = null
	var best_area := INF

	for node in get_tree().get_nodes_in_group("rooms"):
		if not node.has_method("get_camera_bounds"):
			continue
		if not node.contains_world_point(point, room_detect_margin):
			continue
		var bounds: Rect2 = node.get_camera_bounds()
		var area: float = bounds.get_area()
		# Prefer the smallest room containing the player (e.g. chica over large).
		if area < best_area:
			best_area = area
			best = node

	return best


func _apply_bounds(room: Node2D) -> void:
	var bounds: Rect2 = room.get_camera_bounds()
	if bounds.size == Vector2.ZERO:
		return
	limit_left = int(floor(bounds.position.x))
	limit_top = int(floor(bounds.position.y))
	limit_right = int(ceil(bounds.end.x))
	limit_bottom = int(ceil(bounds.end.y))
