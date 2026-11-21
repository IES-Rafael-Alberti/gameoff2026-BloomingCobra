extends Node

## Diagonal burst mover for the divider snake: rest → thrust → rest.
## Next lunge picks a random clear diagonal (skips directions blocked by walls).

const DIAGONALS: Array[Vector2] = [
	Vector2(1, 1),
	Vector2(1, -1),
	Vector2(-1, 1),
	Vector2(-1, -1),
]

enum Phase { REST, LUNGE }

@export var speed: float = 70.0
## How far each tail-thrust travels.
@export var lunge_distance: float = 42.0
@export var rest_duration_min: float = 0.28
@export var rest_duration_max: float = 0.55
## Reject diagonals that collide within this distance.
@export var wall_probe_distance: float = 18.0
## Extra push away from a wall when probes say everything is blocked.
@export var unstick_nudge: float = 3.0

var _enemy: CharacterBody2D
var _direction: Vector2 = Vector2(1, 1).normalized()
var _phase: Phase = Phase.REST
var _timer: float = 0.0
var _lunge_traveled: float = 0.0
var _active: bool = true
var _blocked_streak: int = 0


func setup(enemy: CharacterBody2D) -> void:
	_enemy = enemy
	_start_rest()


func set_active(active: bool) -> void:
	_active = active
	if not active and _enemy != null:
		_enemy.velocity = Vector2.ZERO
		_play_facing(_direction)


func physics_update(delta: float) -> void:
	if not _active or _enemy == null:
		return

	match _phase:
		Phase.REST:
			_update_rest(delta)
		Phase.LUNGE:
			_update_lunge(delta)


func _update_rest(delta: float) -> void:
	_enemy.velocity = Vector2.ZERO
	_play_facing(_direction)
	_timer -= delta
	if _timer <= 0.0:
		_start_lunge()


func _update_lunge(delta: float) -> void:
	# Hit a wall mid-thrust → pick a new free diagonal away from it.
	if _enemy.get_slide_collision_count() > 0:
		var collision: KinematicCollision2D = _enemy.get_slide_collision(0)
		_redirect_from_wall(collision.get_normal())
		return

	_enemy.velocity = _direction * speed
	_play_facing(_direction)
	_lunge_traveled += speed * delta
	if _lunge_traveled >= lunge_distance:
		_start_rest()


func _play_facing(dir: Vector2) -> void:
	if _enemy == null:
		return
	# Keep the last diagonal facing during rests (dividers have no useful idle pose).
	var face := dir if dir != Vector2.ZERO else _direction
	if face == Vector2.ZERO:
		face = Vector2(1, 1).normalized()
	_enemy.call("play_directional_animation", "walking", face)


func _start_rest() -> void:
	_phase = Phase.REST
	_lunge_traveled = 0.0
	_timer = randf_range(rest_duration_min, rest_duration_max)
	if _enemy != null:
		_enemy.velocity = Vector2.ZERO


func _start_lunge() -> void:
	var next := _pick_clear_diagonal()
	if next == Vector2.ZERO:
		_blocked_streak += 1
		_unstick_if_needed()
		next = _pick_clear_diagonal()
	if next == Vector2.ZERO:
		# Still trapped — force any diagonal and hope the slide frees us.
		next = DIAGONALS[randi() % DIAGONALS.size()].normalized()
		_blocked_streak += 1
	else:
		_blocked_streak = 0

	_direction = next
	_phase = Phase.LUNGE
	_lunge_traveled = 0.0


func _redirect_from_wall(normal: Vector2) -> void:
	var options: Array[Vector2] = []
	for raw in DIAGONALS:
		var dir := raw.normalized()
		# Prefer directions that leave the wall (point roughly along the normal).
		if dir.dot(normal) <= 0.05:
			continue
		if _is_direction_clear(dir):
			options.append(dir)

	if options.is_empty():
		for raw in DIAGONALS:
			var dir := raw.normalized()
			if dir.dot(normal) > 0.05:
				options.append(dir)

	if options.is_empty():
		_start_rest()
		return

	_direction = options[randi() % options.size()]
	_phase = Phase.LUNGE
	_lunge_traveled = 0.0
	_enemy.velocity = _direction * speed
	_play_facing(_direction)


func _pick_clear_diagonal(avoid_current: bool = true) -> Vector2:
	var options: Array[Vector2] = []
	for raw in DIAGONALS:
		var dir := raw.normalized()
		if _is_direction_clear(dir):
			options.append(dir)

	if options.is_empty():
		return Vector2.ZERO

	if avoid_current and options.size() > 1 and _direction != Vector2.ZERO:
		var filtered: Array[Vector2] = []
		for dir in options:
			if dir.distance_squared_to(_direction) > 0.01:
				filtered.append(dir)
		if not filtered.is_empty():
			options = filtered

	return options[randi() % options.size()]


func _is_direction_clear(dir: Vector2) -> bool:
	if _enemy == null:
		return false
	# Probe from a tiny inset so overlapping a wall after a hit doesn't mark every dir blocked.
	var inset := -dir * 1.5
	var from := _enemy.global_transform.translated(inset)
	return not _enemy.test_move(from, dir * wall_probe_distance)


func _unstick_if_needed() -> void:
	if _enemy == null or _blocked_streak < 2:
		return
	# Nudge away from the last collision normal, or along the opposite of current dir.
	var push := -_direction
	if _enemy.get_slide_collision_count() > 0:
		push = _enemy.get_slide_collision(0).get_normal()
	elif push == Vector2.ZERO:
		push = Vector2.UP
	_enemy.global_position += push.normalized() * unstick_nudge
	_enemy.velocity = Vector2.ZERO
