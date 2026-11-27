class_name PlayerBuffs
extends Node

## Stacking attack/projectile damage boosts and hit-absorbing shield charges.
## Attack / projectile / shield all accumulate; none expire by time.

signal buffs_changed

@export var default_attack_stacks: int = 1
@export var default_projectile_stacks: int = 1
@export var default_shield_hits: int = 3
## Damage added by each consumed attack/projectile charge (per hit landed).
@export var melee_bonus_per_charge: int = 1
@export var projectile_bonus_per_charge: int = 1

var _attack_stacks: int = 0
var _projectile_stacks: int = 0
var _shield_hits: int = 0
## Damage carried by each individual charge (parallel to the stack counts).
var _attack_charge_damage: Array[int] = []
var _projectile_charge_damage: Array[int] = []


func apply_attack_boost(stacks: int = -1, damage_per_charge: int = -1) -> void:
	var add := stacks if stacks > 0 else default_attack_stacks
	add = maxi(add, 1)
	var dmg := damage_per_charge if damage_per_charge >= 0 else melee_bonus_per_charge
	_attack_stacks = maxi(_attack_stacks, 0) + add
	for _i in add:
		_attack_charge_damage.append(maxi(dmg, 0))
	buffs_changed.emit()


func apply_projectile_boost(stacks: int = -1, damage_per_charge: int = -1) -> void:
	var add := stacks if stacks > 0 else default_projectile_stacks
	add = maxi(add, 1)
	var dmg := damage_per_charge if damage_per_charge >= 0 else projectile_bonus_per_charge
	_projectile_stacks = maxi(_projectile_stacks, 0) + add
	for _i in add:
		_projectile_charge_damage.append(maxi(dmg, 0))
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


## Consumes one attack charge on a landed hit. Returns the damage bonus to add (0 if none).
func consume_melee_charge() -> int:
	if _attack_stacks <= 0:
		return 0
	_attack_stacks -= 1
	var bonus := maxi(melee_bonus_per_charge, 0)
	if not _attack_charge_damage.is_empty():
		bonus = _attack_charge_damage.pop_back()
	buffs_changed.emit()
	return bonus


## Consumes one projectile charge on a landed hit. Returns the damage bonus to add (0 if none).
func consume_projectile_charge() -> int:
	if _projectile_stacks <= 0:
		return 0
	_projectile_stacks -= 1
	var bonus := maxi(projectile_bonus_per_charge, 0)
	if not _projectile_charge_damage.is_empty():
		bonus = _projectile_charge_damage.pop_back()
	buffs_changed.emit()
	return bonus
