extends Node

@export var speed: float = 60.0
@export var initial_direction: Vector2 = Vector2(1, 1)
## Continuous spin while floating (degrees / sec). Sign follows horizontal travel.
@export var spin_degrees_per_second: float = 90.0

var _enemy: CharacterBody2D
var _direction: Vector2 = Vector2.RIGHT
var _active: bool = true


func setup(enemy: CharacterBody2D) -> void:
	_enemy = enemy
	# Stay on the enemy layer so player melee/projectiles can hit this body.
	# Skip solid push vs the player (hurtbox still handles contact damage).
	_enemy.collision_layer = 1 << 2
	# world + door_enemy (floats over spikes — no spikes_enemy)
	_enemy.collision_mask = (1 << 0) | (1 << 3)
	_direction = initial_direction.normalized()
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT
	_play_float()
	call_deferred("_ignore_player_collision")


func set_active(active: bool) -> void:
	_active = active
	if active:
		_play_float()
	else:
		_reset_spin()


func physics_update(delta: float) -> void:
	if not _active or _enemy == null:
		return

	var bounced := false
	for i in _enemy.get_slide_collision_count():
		var collision: KinematicCollision2D = _enemy.get_slide_collision(i)
		var next := _direction.bounce(collision.get_normal()).normalized()
		if next.distance_squared_to(_direction) > 0.0001:
			bounced = true
		_direction = next
		break

	if bounced:
		var sfx := _enemy.get_node_or_null("SfxPlayer")
		if sfx != null and sfx.has_method("play_bounce"):
			sfx.call("play_bounce")

	_enemy.velocity = _direction * speed
	_spin_while_floating(delta)
	_play_float()


func _ignore_player_collision() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	var player := _enemy.get_tree().get_first_node_in_group("player") as PhysicsBody2D
	if player == null:
		return
	_enemy.add_collision_exception_with(player)


func _play_float() -> void:
	var sprite := _sprite()
	if sprite == null:
		return
	if sprite.animation != &"floating":
		sprite.play("floating")
	sprite.flip_h = false


func _spin_while_floating(delta: float) -> void:
	var sprite := _sprite()
	if sprite == null or spin_degrees_per_second == 0.0:
		return
	var dir_sign := -1.0 if _direction.x < 0.0 else 1.0
	sprite.rotation_degrees += spin_degrees_per_second * dir_sign * delta


func _reset_spin() -> void:
	var sprite := _sprite()
	if sprite == null:
		return
	sprite.rotation = 0.0
	sprite.flip_h = false


func _sprite() -> AnimatedSprite2D:
	if _enemy == null:
		return null
	return _enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
