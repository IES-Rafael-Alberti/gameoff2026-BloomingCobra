extends Node

@export var speed: float = 65.0
@export var flee_range: float = 100.0
@export var catch_range: float = 14.0
@export var wall_check_distance: float = 14.0

var _DIRECTIONS: Array[Vector2] = [
	Vector2.LEFT,
	Vector2.RIGHT,
	Vector2.UP,
	Vector2.DOWN,
	Vector2(-1, -1).normalized(),
	Vector2(1, -1).normalized(),
	Vector2(-1, 1).normalized(),
	Vector2(1, 1).normalized(),
]

var _enemy: CharacterBody2D
var _active: bool = true
var _catching: bool = false
var _flee_dir: Vector2 = Vector2.ZERO


func setup(enemy: CharacterBody2D) -> void:
	_enemy = enemy


func set_active(active: bool) -> void:
	_active = active
	_flee_dir = Vector2.ZERO


func physics_update(_delta: float) -> void:
	if not _active or _enemy == null or _catching:
		return

	var player: Node2D = _enemy.get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		_enemy.velocity = Vector2.ZERO
		_flee_dir = Vector2.ZERO
		_play_walk(Vector2.ZERO)
		return

	var away: Vector2 = _enemy.global_position - player.global_position
	var distance: float = away.length()

	if distance <= catch_range:
		_start_catch()
		return

	if distance <= flee_range and distance > 0.001:
		_flee_dir = _pick_flee_direction(away)
		_enemy.velocity = _flee_dir * speed
		_play_walk(_flee_dir)
	else:
		_enemy.velocity = Vector2.ZERO
		_flee_dir = Vector2.ZERO
		_play_walk(Vector2.ZERO)


func _pick_flee_direction(away: Vector2) -> Vector2:
	var away_n: Vector2 = away.normalized()
	var ranked: Array[Vector2] = _DIRECTIONS.duplicate()
	ranked.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.dot(away_n) > b.dot(away_n)
	)

	# Keep current direction if still good and free; otherwise switch away from walls.
	if _flee_dir != Vector2.ZERO and not _is_blocked(_flee_dir):
		var current_score: float = _flee_dir.dot(away_n)
		var best_score: float = ranked[0].dot(away_n)
		if current_score >= best_score - 0.25:
			return _flee_dir

	for dir in ranked:
		if not _is_blocked(dir):
			return dir

	return ranked[0]


func _is_blocked(dir: Vector2) -> bool:
	if _enemy == null:
		return true
	# Look ahead so we turn before hugging the wall.
	return _enemy.test_move(_enemy.global_transform, dir * wall_check_distance)


func _play_walk(direction: Vector2) -> void:
	if _enemy.has_method("play_walk_animation"):
		_enemy.call("play_walk_animation", direction)
	elif _enemy.has_method("play_directional_animation"):
		_enemy.call("play_directional_animation", "walking", direction)


func _start_catch() -> void:
	_catching = true
	_flee_dir = Vector2.ZERO
	_enemy.velocity = Vector2.ZERO
	if _enemy.has_method("play_gather"):
		_enemy.call("play_gather")
