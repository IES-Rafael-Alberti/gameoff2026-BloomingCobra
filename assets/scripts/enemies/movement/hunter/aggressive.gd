extends Node

## Chase the player and melee when in attack_range.

@export var claw_fx_distance: float = 14.0
@export var claw_fx_duration: float = 0.28
## Aligns the claw slash art with the attack facing.
@export var claw_fx_angle_offset: float = deg_to_rad(-40.0)

var brain: Node = null
var _cooldown_left: float = 0.0
var _attack_fx: AnimatedSprite2D = null
var _fx_tween: Tween = null


func setup(hunter_brain: Node) -> void:
	brain = hunter_brain
	_attack_fx = get_node_or_null("Attack") as AnimatedSprite2D
	_hide_attack_fx()


func enter(_from: StringName = &"") -> void:
	_cooldown_left = 0.0
	_hide_attack_fx()


func exit(_to: StringName = &"") -> void:
	_cooldown_left = 0.0
	_hide_attack_fx()


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
			_play_claw_fx(direction)
			if enemy.has_method("deal_player_hit"):
				enemy.call("deal_player_hit", player)
	else:
		enemy.call("set_attacking", false)
		enemy.velocity = direction * speed
		enemy.call("play_directional_animation", "walking", direction)


func _play_claw_fx(direction: Vector2) -> void:
	if _attack_fx == null:
		return
	var facing := direction if direction != Vector2.ZERO else Vector2.RIGHT
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
		_fx_tween = null

	_attack_fx.visible = true
	_attack_fx.modulate = Color(1, 1, 1, 1)
	_attack_fx.rotation = facing.angle() + claw_fx_angle_offset
	_attack_fx.position = facing * claw_fx_distance
	_attack_fx.z_index = 1
	if _attack_fx.sprite_frames != null and _attack_fx.sprite_frames.has_animation(&"attack"):
		_attack_fx.sprite_frames.set_animation_loop(&"attack", false)
		_attack_fx.play(&"attack")

	_fx_tween = create_tween()
	_fx_tween.tween_interval(claw_fx_duration * 0.35)
	_fx_tween.tween_property(_attack_fx, "modulate:a", 0.0, claw_fx_duration * 0.65)
	_fx_tween.tween_callback(_hide_attack_fx)


func _hide_attack_fx() -> void:
	if _fx_tween != null and _fx_tween.is_valid():
		_fx_tween.kill()
	_fx_tween = null
	if _attack_fx == null:
		return
	_attack_fx.visible = false
	_attack_fx.stop()
	_attack_fx.modulate = Color(1, 1, 1, 1)
	_attack_fx.position = Vector2.ZERO
	_attack_fx.rotation = 0.0
