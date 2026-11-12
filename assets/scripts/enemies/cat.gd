class_name Cat
extends CharacterBody2D

signal caught

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var switchable: Node2D = $Switchable
@onready var sfx: Node = get_node_or_null("SfxPlayer")

var _movement: Node = null
var _active: bool = true
var _is_caught: bool = false


func _ready() -> void:
	add_to_group("cat")
	# Catchable by proximity; no solid push vs player.
	collision_layer = 0
	collision_mask = (1 << 0) | (1 << 3) | (1 << 5) # world + door_enemy + spikes_enemy
	_movement = get_node_or_null("Runner")
	if _movement and _movement.has_method("setup"):
		_movement.setup(self)
	if switchable.has_signal("mode_changed"):
		switchable.mode_changed.connect(_on_mode_changed)
		_on_mode_changed(switchable.get_mode())


func _physics_process(delta: float) -> void:
	if _is_caught:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if not _active or _movement == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _movement.has_method("physics_update"):
		_movement.physics_update(delta)
	move_and_slide()


func is_active() -> bool:
	return _active and not _is_caught


func play_walk_animation(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		animated_sprite.stop()
		return
	if abs(direction.x) > abs(direction.y):
		animated_sprite.play("walking_sides")
		animated_sprite.flip_h = direction.x < 0
	elif direction.y < 0:
		animated_sprite.play("walking_up")
		animated_sprite.flip_h = false
	else:
		animated_sprite.play("walking_down")
		animated_sprite.flip_h = false


func play_gather() -> void:
	_is_caught = true
	velocity = Vector2.ZERO
	if sfx != null and sfx.has_method("play_caught"):
		sfx.call("play_caught")
	if animated_sprite.sprite_frames.has_animation("gather"):
		animated_sprite.sprite_frames.set_animation_loop("gather", false)
		animated_sprite.play("gather")
		await animated_sprite.animation_finished
	caught.emit()
	_grant_catch_heal()
	queue_free()


func _grant_catch_heal() -> void:
	var player := get_player()
	if player == null:
		return
	if player.has_method("heal_vitality_from_cat"):
		player.call("heal_vitality_from_cat")
	elif player.has_method("heal_vitality"):
		player.call("heal_vitality", 40.0)


func get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


func _on_mode_changed(index: int) -> void:
	var was_active := _active
	_active = index == 0 and not _is_caught
	if _movement and _movement.has_method("set_active"):
		_movement.set_active(_active)
	if sfx != null and sfx.has_method("set_active"):
		sfx.call("set_active", _active)

	if not _active:
		velocity = Vector2.ZERO
		animated_sprite.stop()
		visible = false
		return

	# Reappears in Pesadilla at a random spot in the current room.
	if not was_active:
		_teleport_random_in_room()
	visible = true


func _teleport_random_in_room() -> void:
	var room := _find_room_at(global_position)
	if room == null:
		var player := get_player()
		if player != null:
			room = _find_room_at(player.global_position)
	if room == null or not room.has_method("get_camera_bounds"):
		return

	var bounds: Rect2 = room.get_camera_bounds()
	if bounds.size == Vector2.ZERO:
		return

	# Keep away from outer walls / camera edge.
	var margin := 24.0
	var inner := bounds.grow(-margin)
	if inner.size.x <= 1.0 or inner.size.y <= 1.0:
		inner = bounds

	global_position = Vector2(
		randf_range(inner.position.x, inner.end.x),
		randf_range(inner.position.y, inner.end.y)
	)
	velocity = Vector2.ZERO


func _find_room_at(point: Vector2) -> Node2D:
	var best: Node2D = null
	var best_area := INF
	for node in get_tree().get_nodes_in_group("rooms"):
		if not node.has_method("contains_world_point"):
			continue
		if not node.contains_world_point(point, 8.0):
			continue
		var bounds: Rect2 = node.get_camera_bounds()
		var area: float = bounds.get_area()
		if area < best_area:
			best_area = area
			best = node
	return best
