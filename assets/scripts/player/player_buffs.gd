class_name PlayerBuffs
extends Node

## Stacking attack/projectile damage boosts and hit-absorbing shield charges.
## Attack / projectile / shield all accumulate; none expire by time.

signal buffs_changed

@export var default_attack_stacks: int = 1
@export var default_projectile_stacks: int = 1
@export var default_shield_hits: int = 3

var _attack_stacks: int = 0
var _projectile_stacks: int = 0
var _shield_hits: int = 0


func apply_attack_boost(stacks: int = -1) -> void:
	var add := stacks if stacks > 0 else default_attack_stacks
	_attack_stacks = maxi(_attack_stacks, 0) + maxi(add, 1)
	buffs_changed.emit()


func apply_projectile_boost(stacks: int = -1) -> void:
	var add := stacks if stacks > 0 else default_projectile_stacks
	_projectile_stacks = maxi(_projectile_stacks, 0) + maxi(add, 1)
	buffs_changed.emit()


func apply_shield(hits: int = -1) -> void:
	var h := hits if hits > 0 else default_shield_hits
	_shield_hits = maxi(_shield_hits, 0) + maxi(h, 1)
	buffs_changed.emit()


func get_melee_damage_bonus() -> int:
	return maxi(_attack_stacks, 0)


func get_projectile_damage_bonus() -> int:
	return maxi(_projectile_stacks, 0)


func get_shield_hits() -> int:
	return _shield_hits


func get_attack_stacks() -> int:
	return maxi(_attack_stacks, 0)


func get_projectile_stacks() -> int:
	return maxi(_projectile_stacks, 0)


func has_attack_boost() -> bool:
	return _attack_stacks > 0


func has_projectile_boost() -> bool:
	return _projectile_stacks > 0


## Consumes one shield charge. Returns true if the hit was absorbed.
func try_absorb_hit() -> bool:
	if _shield_hits <= 0:
		return false
	_shield_hits -= 1
	buffs_changed.emit()
	return true
