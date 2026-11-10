extends Node

@export var speed: float = 35.0
@export var direction_change_interval: float = 2.0
@export var idle_chance: float = 0.35
@export var idle_duration_min: float = 0.8
@export var idle_duration_max: float = 2.0

var _enemy: CharacterBody2D
var _direction: Vector2 = Vector2.RIGHT
var _timer: float = 0.0
var _active: bool = true
var _idling: bool = false


func setup(enemy: CharacterBody2D) -> void:
	_enemy = enemy
	_pick_next_behavior()


func set_active(active: bool) -> void:
	_active = active


func physics_update(delta: float) -> void:
	if not _active or _enemy == null:
		return

	_timer -= delta
	if _timer <= 0.0:
		_pick_next_behavior()

	if _idling:
		_enemy.velocity = Vector2.ZERO
		_enemy.call("play_directional_animation", "walking", Vector2.ZERO)
		return

	# Collisions from the previous move_and_slide frame.
	for i in _enemy.get_slide_collision_count():
		var collision: KinematicCollision2D = _enemy.get_slide_collision(i)
		_redirect_from_wall(collision.get_normal())
		break

	_enemy.velocity = _direction * speed
	_enemy.call("play_directional_animation", "walking", _direction)


func _pick_next_behavior() -> void:
	if randf() < idle_chance:
		_idling = true
		_direction = Vector2.ZERO
		_timer = randf_range(idle_duration_min, idle_duration_max)
	else:
		_idling = false
		_pick_direction()


func _pick_direction() -> void:
	_idling = false
	_direction = Vector2.from_angle(randf() * TAU).normalized()
	_timer = direction_change_interval


func _redirect_from_wall(normal: Vector2) -> void:
	var bounced: Vector2 = _direction.bounce(normal).normalized()
	if bounced != Vector2.ZERO and bounced.dot(normal) >= 0.0:
		_direction = bounced
		_timer = direction_change_interval
		return

	for _attempt in 8:
		_pick_direction()
		if _direction.dot(normal) > 0.2:
			return

	_direction = normal.normalized()
	_timer = direction_change_interval
