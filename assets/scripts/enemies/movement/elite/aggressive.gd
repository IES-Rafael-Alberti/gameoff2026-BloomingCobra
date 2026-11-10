extends EliteState

## Patrols toward the player and picks charge / circular attacks.
## Close range → spin. Mid/far band → charge.

@export var move_speed: float = 32.0
@export var contact_damage: int = 1
@export var contact_cooldown: float = 0.7

var _contact_cd: float = 0.0
var _prefer_circular: bool = false


func enter(from: StringName = &"") -> void:
	if brain == null:
		return
	brain.set_shield_active(true)
	_contact_cd = 0.0
	# After a charge rest, prefer spin if the player is still nearby.
	_prefer_circular = from == &"resting"
	if brain.charge != null:
		brain.charge.reset()
	if brain.circular != null:
		brain.circular.reset()


func exit(_to: StringName = &"") -> void:
	if brain == null:
		return
	if brain.charge != null:
		brain.charge.reset()
	if brain.circular != null:
		brain.circular.reset()


func physics_update(delta: float) -> void:
	if brain == null:
		return
	_contact_cd = maxf(_contact_cd - delta, 0.0)

	var player: Node2D = brain.get_player()
	if player == null:
		brain.change_state(&"idle")
		return

	# Prefer active attack ownership.
	if brain.charge != null and brain.charge.is_busy():
		brain.charge.physics_update(delta, player)
		_try_contact(player)
		return
	if brain.circular != null and brain.circular.is_busy():
		brain.circular.physics_update(delta)
		return
	# Cooldown tick for circular even when idle in this state.
	if brain.circular != null:
		brain.circular.physics_update(delta)

	var enemy: CharacterBody2D = brain.get_enemy()
	var to_player: Vector2 = player.global_position - enemy.global_position
	var distance: float = to_player.length()

	var detection_radius: float = float(brain.detection_radius) if "detection_radius" in brain else 110.0
	if distance > detection_radius:
		brain.change_state(&"idle")
		return

	var can_spin: bool = brain.circular != null and brain.circular.can_trigger(distance)
	var can_charge: bool = brain.charge != null and brain.charge.can_trigger(distance)

	if _prefer_circular and can_spin:
		_prefer_circular = false
		brain.circular.begin()
		return

	if can_spin:
		_prefer_circular = false
		brain.circular.begin()
		return

	if can_charge:
		brain.charge.begin(to_player)
		return

	# Slow advance through the room.
	var dir: Vector2 = brain.cardinal_from(to_player)
	brain.set_facing(dir)
	enemy.velocity = dir * move_speed
	brain.play_walk_anim(dir)
	_try_contact(player)


func _try_contact(player: Node2D) -> void:
	if _contact_cd > 0.0 or player == null:
		return
	var enemy: CharacterBody2D = brain.get_enemy()
	if enemy.global_position.distance_to(player.global_position) > 18.0:
		return
	_contact_cd = contact_cooldown
	var dmg := player.get_node_or_null("Damageable")
	if dmg != null and dmg.has_method("take_damage"):
		dmg.take_damage(contact_damage)
	if player.has_method("apply_knockback"):
		var away: Vector2 = player.global_position - enemy.global_position
		if away == Vector2.ZERO:
			away = brain.get_facing()
		player.apply_knockback(away.normalized(), 100.0)
