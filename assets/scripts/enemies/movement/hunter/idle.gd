extends Node

## Waits until the player stays in detection range for aggro_delay.

var brain: Node = null
var detection_radius: float = 110.0
var aggro_delay: float = 0.0

var _aggro_timer: float = 0.0


func setup(hunter_brain: Node) -> void:
	brain = hunter_brain


func enter(_from: StringName = &"") -> void:
	_aggro_timer = 0.0
	if brain == null:
		return
	var enemy: CharacterBody2D = brain.get_enemy()
	if enemy == null:
		return
	enemy.velocity = Vector2.ZERO
	enemy.call("set_attacking", false)
	enemy.call("play_directional_animation", "walking", Vector2.ZERO)


func exit(_to: StringName = &"") -> void:
	_aggro_timer = 0.0


func physics_update(delta: float) -> void:
	if brain == null:
		return
	var enemy: CharacterBody2D = brain.get_enemy()
	if enemy == null:
		return
	enemy.velocity = Vector2.ZERO
	enemy.call("set_attacking", false)
	enemy.call("play_directional_animation", "walking", Vector2.ZERO)

	var radius: float = detection_radius
	var delay: float = aggro_delay
	if "detection_radius" in brain:
		radius = float(brain.detection_radius)
	if "aggro_delay" in brain:
		delay = float(brain.aggro_delay)

	var player: Node2D = brain.get_player()
	if player == null:
		_aggro_timer = 0.0
		return

	var dist: float = enemy.global_position.distance_to(player.global_position)
	if dist > radius:
		_aggro_timer = 0.0
		return

	if delay <= 0.0:
		brain.change_state(&"aggressive")
		return

	_aggro_timer += delta
	if _aggro_timer >= delay:
		brain.change_state(&"aggressive")
