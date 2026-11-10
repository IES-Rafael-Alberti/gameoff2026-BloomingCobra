extends Node

## Chase the player and melee when in attack_range.

var brain: Node = null
var _cooldown_left: float = 0.0


func setup(hunter_brain: Node) -> void:
	brain = hunter_brain


func enter(_from: StringName = &"") -> void:
	_cooldown_left = 0.0


func exit(_to: StringName = &"") -> void:
	_cooldown_left = 0.0


func physics_update(delta: float) -> void:
	if brain == null:
		return
	var enemy: CharacterBody2D = brain.get_enemy()
	if enemy == null:
		return

	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	var player: Node2D = brain.get_player()
	if player == null:
		brain.change_state(&"idle")
		return

	var detection_radius: float = float(brain.detection_radius) if "detection_radius" in brain else 110.0
	var to_player: Vector2 = player.global_position - enemy.global_position
	var distance: float = to_player.length()
	if distance > detection_radius:
		brain.change_state(&"idle")
		return

	var speed: float = float(brain.speed) if "speed" in brain else 55.0
	var attack_range: float = float(brain.attack_range) if "attack_range" in brain else 28.0
	var attack_cooldown: float = float(brain.attack_cooldown) if "attack_cooldown" in brain else 0.8
	var direction: Vector2 = to_player.normalized() if distance > 0.001 else Vector2.ZERO

	if distance <= attack_range:
		enemy.velocity = Vector2.ZERO
		enemy.call("set_attacking", true)
		enemy.call("play_directional_animation", "attacking", direction)
		if _cooldown_left <= 0.0:
			_cooldown_left = attack_cooldown
			if enemy.has_method("deal_player_hit"):
				enemy.call("deal_player_hit", player)
	else:
		enemy.call("set_attacking", false)
		enemy.velocity = direction * speed
		enemy.call("play_directional_animation", "walking", direction)
