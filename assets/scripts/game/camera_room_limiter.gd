extends Camera2D

var _current_room: Room = null


func _ready() -> void:
	enabled = true
	make_current()
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
	_snap_now()


func _apply_bounds(room: Room) -> void:
	var bounds: Rect2 = room.get_camera_bounds()
	if bounds.size == Vector2.ZERO:
		return
	limit_left = int(floor(bounds.position.x))
	limit_top = int(floor(bounds.position.y))
	limit_right = int(ceil(bounds.end.x))
	limit_bottom = int(ceil(bounds.end.y))


## Call after a forced player teleport so limits + scroll match the new room now.
func snap_to_room(room: Room) -> void:
	if room == null:
		return
	_current_room = room
	_apply_bounds(room)
	_snap_now()


func _snap_now() -> void:
	var was_limit_smoothed := limit_smoothed
	var was_pos_smoothed := position_smoothing_enabled
	limit_smoothed = false
	position_smoothing_enabled = false
	make_current()
	reset_smoothing()
	force_update_scroll()
	# Restore smoothing after the snap so normal room transitions stay soft.
	limit_smoothed = was_limit_smoothed
	position_smoothing_enabled = was_pos_smoothed
