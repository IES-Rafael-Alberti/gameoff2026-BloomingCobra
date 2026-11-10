extends Node2D

## When health drops to `health_threshold` or below, replaces this enemy with
## `split_count` copies of `split_scene`. Leave `split_scene` empty on the
## final stage so it dies normally at 0 HP.

@export var split_scene: PackedScene
@export var health_threshold: int = 0
@export var split_count: int = 2
@export var spawn_separation: float = 14.0
@export var play_divide_animation: bool = true

var _enemy: CharacterBody2D
var _damageable: Node
var _splitting: bool = false


func _ready() -> void:
	_enemy = get_parent() as CharacterBody2D
	if _enemy == null:
		return
	_damageable = _enemy.get_node_or_null("Damageable")
	if _damageable != null and _damageable.has_signal("damaged"):
		_damageable.damaged.connect(_on_damaged)


func is_splitting() -> bool:
	return _splitting


func _on_damaged(_amount: int, current_health: int) -> void:
	if _splitting or split_scene == null or split_count <= 0:
		return
	if current_health > health_threshold:
		return
	_begin_split()


func _begin_split() -> void:
	_splitting = true
	_suppress_death()
	_freeze_host()
	if _enemy.has_method("clear_hurt_lock"):
		_enemy.call("clear_hurt_lock")

	if play_divide_animation:
		await _play_divide()

	if not is_instance_valid(_enemy):
		return

	_spawn_halves()
	_enemy.queue_free()


func _suppress_death() -> void:
	if _damageable == null:
		return
	# Avoid Enemy._on_died freeing us before the split finishes.
	for connection in _damageable.died.get_connections():
		_damageable.died.disconnect(connection["callable"])
	if "immortal" in _damageable:
		_damageable.immortal = true


func _freeze_host() -> void:
	_enemy.velocity = Vector2.ZERO
	var movement := _enemy.get_node_or_null("Roamer")
	if movement != null and movement.has_method("set_active"):
		movement.set_active(false)

	# Hit callbacks run while physics is flushing queries — defer collision edits.
	_enemy.set_deferred("collision_layer", 0)
	_enemy.set_deferred("collision_mask", 0)
	for child in _enemy.get_children():
		if child is Area2D:
			var area := child as Area2D
			area.set_deferred("monitoring", false)
			area.set_deferred("monitorable", false)
			for shape in area.get_children():
				if shape is CollisionShape2D:
					shape.set_deferred("disabled", true)

	var body_shape := _enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body_shape != null:
		body_shape.set_deferred("disabled", true)


func _play_divide() -> void:
	var sprite := _enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation("divide"):
		return

	sprite.sprite_frames.set_animation_loop("divide", false)
	sprite.play("divide")
	var frames := sprite.sprite_frames.get_frame_count("divide")
	var speed := sprite.sprite_frames.get_animation_speed("divide") * maxf(sprite.speed_scale, 0.01)
	if frames <= 0 or speed <= 0.0:
		return
	await get_tree().create_timer(float(frames) / speed).timeout


func _spawn_halves() -> void:
	var container := _enemy.get_parent()
	if container == null:
		return

	var origin := _enemy.global_position
	var mode := _current_mode()
	var room := _find_room()

	for i in split_count:
		var half := split_scene.instantiate()
		container.add_child(half)
		if half is Node2D:
			(half as Node2D).global_position = origin + _offset_for_index(i)
		_apply_mode(half, mode)
		if room != null and room.has_method("register_enemy"):
			room.call("register_enemy", half)


func _offset_for_index(index: int) -> Vector2:
	if split_count == 1:
		return Vector2.ZERO
	if split_count == 2:
		var side := -1.0 if index == 0 else 1.0
		return Vector2(side * spawn_separation, 0.0)
	var angle := TAU * float(index) / float(split_count)
	return Vector2.from_angle(angle) * spawn_separation


func _current_mode() -> int:
	var switchable := _enemy.get_node_or_null("Switchable")
	if switchable != null and switchable.has_method("get_mode"):
		return int(switchable.call("get_mode"))
	return 0


func _apply_mode(half: Node, mode: int) -> void:
	var switchable := half.get_node_or_null("Switchable")
	if switchable != null and switchable.has_method("set_mode"):
		switchable.call("set_mode", mode)


func _find_room() -> Node:
	var node: Node = _enemy.get_parent()
	while node != null:
		if node is Room:
			return node
		node = node.get_parent()
	return null
