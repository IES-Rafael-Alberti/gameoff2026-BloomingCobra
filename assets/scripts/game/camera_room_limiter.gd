extends Camera2D

var _current_room: Room = null


func _ready() -> void:
	limit_enabled = true
	call_deferred("_bind_room_manager")


func _bind_room_manager() -> void:
	var manager := get_tree().get_first_node_in_group("room_manager")
	if manager == null:
		return
	if manager.has_signal("room_changed") and not manager.room_changed.is_connected(_on_room_changed):
		manager.room_changed.connect(_on_room_changed)
	if "current_room" in manager and manager.current_room != null:
		_on_room_changed(null, manager.current_room)


func _on_room_changed(_previous: Room, next: Room) -> void:
	_current_room = next
	if next == null:
		return
	_apply_bounds(next)


func _apply_bounds(room: Room) -> void:
	var bounds: Rect2 = room.get_camera_bounds()
	if bounds.size == Vector2.ZERO:
		return
	limit_left = int(floor(bounds.position.x))
	limit_top = int(floor(bounds.position.y))
	limit_right = int(ceil(bounds.end.x))
	limit_bottom = int(ceil(bounds.end.y))
