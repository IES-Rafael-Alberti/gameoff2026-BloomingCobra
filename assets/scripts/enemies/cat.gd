class_name Cat
extends CharacterBody2D

signal caught

@export var catch_heal_drop_scene: PackedScene = preload("res://assets/scenes/props/pickups/pickup_cat_heal.tscn")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var switchable: Node2D = $Switchable
@onready var sfx: Node = get_node_or_null("SfxPlayer")

var _movement: Node = null
var _active: bool = true
var _is_caught: bool = false
## Last horizontal facing for idle flip (idle art faces left by default).
var _idle_flip_h: bool = false


func _ready() -> void:
	add_to_group("cat")
	add_to_group("enemy")
	z_index = maxi(z_index, 2)
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
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	var frames := animated_sprite.sprite_frames
	if direction == Vector2.ZERO:
		_play_idle()
		return

	var anim := &""
	animated_sprite.flip_h = false

	if absf(direction.x) > absf(direction.y):
		if direction.x < 0.0:
			_idle_flip_h = false
			if frames.has_animation(&"walking_left"):
				anim = &"walking_left"
			elif frames.has_animation(&"walking_sides"):
				anim = &"walking_sides"
				animated_sprite.flip_h = true
			elif frames.has_animation(&"walking_right"):
				anim = &"walking_right"
				animated_sprite.flip_h = true
		else:
			_idle_flip_h = true
			if frames.has_animation(&"walking_right"):
				anim = &"walking_right"
			elif frames.has_animation(&"walking_sides"):
				anim = &"walking_sides"
			elif frames.has_animation(&"walking_left"):
				anim = &"walking_left"
				animated_sprite.flip_h = true
	elif direction.y < 0.0:
		anim = &"walking_up" if frames.has_animation(&"walking_up") else &""
	else:
		anim = &"walking_down" if frames.has_animation(&"walking_down") else &""

	if anim.is_empty():
		return
	if animated_sprite.animation != anim or not animated_sprite.is_playing():
		animated_sprite.play(anim)


func _play_idle() -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(&"idle"):
		animated_sprite.stop()
		return
	# Idle sheet faces left; flip when the cat last ran right.
	animated_sprite.flip_h = _idle_flip_h
	if animated_sprite.animation != &"idle" or not animated_sprite.is_playing():
		animated_sprite.play(&"idle")


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
	_spawn_catch_heal_drop()
	queue_free()


func _spawn_catch_heal_drop() -> void:
	if catch_heal_drop_scene == null:
		return
	var drop := catch_heal_drop_scene.instantiate()
	var parent := get_parent()
	if parent == null:
		parent = get_tree().current_scene
	if parent == null:
		return
	parent.add_child(drop)
	if drop is Node2D:
		(drop as Node2D).global_position = global_position


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


func _find_room_at(_point: Vector2) -> Node2D:
	# Cat lives inside its room scene; prefer the active room.
	var manager := get_tree().get_first_node_in_group("room_manager")
	if manager != null and "current_room" in manager and manager.current_room is Node2D:
		return manager.current_room as Node2D
	var parent_room := get_parent()
	while parent_room != null:
		if parent_room is Room or parent_room.is_in_group("rooms"):
			return parent_room as Node2D
		parent_room = parent_room.get_parent()
	return null
