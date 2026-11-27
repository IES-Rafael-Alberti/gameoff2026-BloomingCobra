class_name PlayerBuffs
extends Node

## Stacking attack/projectile boosts and hit-absorbing shield charges.
## Attack charges add damage to ANY hit (melee or projectile).
## Projectile charges make each attack also launch a projectile.
## Shield charges absorb hits. None of them expire by time.
## Stacks cap at their max; picking one up beyond the cap does nothing.
## A max of 0 means "no cap".

signal buffs_changed

@export var default_attack_stacks: int = 1
@export var default_projectile_stacks: int = 1
@export var default_shield_hits: int = 3
## Damage added by each consumed attack charge (to melee or projectile hits).
@export var attack_bonus_per_charge: int = 1
@export_group("Max Charges")
@export var max_attack_stacks: int = 5
@export var max_projectile_stacks: int = 5
@export var max_shield_hits: int = 5

var _attack_stacks: int = 0
var _projectile_stacks: int = 0
var _shield_hits: int = 0
## Per-charge damage for attack boosts (parallel to the stack count).
var _attack_charge_damage: Array[int] = []
## Per-charge damage of the projectile launched by each projectile boost (-1 = default).
var _projectile_shot_damage: Array[int] = []


func apply_attack_boost(stacks: int = -1, damage_per_charge: int = -1) -> void:
	var add := stacks if stacks > 0 else default_attack_stacks
	add = maxi(add, 1)
	var dmg := damage_per_charge if damage_per_charge >= 0 else attack_bonus_per_charge
	var current := maxi(_attack_stacks, 0)
	var target := current + add
	if max_attack_stacks > 0:
		target = mini(target, max_attack_stacks)
	var actual := target - current
	_attack_stacks = target
	for _i in actual:
		_attack_charge_damage.append(maxi(dmg, 0))
	buffs_changed.emit()


func apply_projectile_boost(stacks: int = -1, shot_damage: int = -1) -> void:
	var add := stacks if stacks > 0 else default_projectile_stacks
	add = maxi(add, 1)
	var current := maxi(_projectile_stacks, 0)
	var target := current + add
	if max_projectile_stacks > 0:
		target = mini(target, max_projectile_stacks)
	var actual := target - current
	_projectile_stacks = target
	for _i in actual:
		_projectile_shot_damage.append(shot_damage)
	buffs_changed.emit()


func apply_shield(hits: int = -1) -> void:
	var h := hits if hits > 0 else default_shield_hits
	var target := maxi(_shield_hits, 0) + maxi(h, 1)
	if max_shield_hits > 0:
		target = mini(target, max_shield_hits)
	_shield_hits = target
	buffs_changed.emit()


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
func consume_attack_charge() -> int:
	if _attack_stacks <= 0:
		return 0
	_attack_stacks -= 1
	var bonus := maxi(attack_bonus_per_charge, 0)
	if not _attack_charge_damage.is_empty():
		bonus = maxi(_attack_charge_damage.pop_back(), 0)
	buffs_changed.emit()
	return bonus


## Consumes one projectile charge when an attack fires.
## Returns null if no charge is available, else the shot damage override (-1 = attack default).
func consume_projectile_charge() -> Variant:
	if _projectile_stacks <= 0:
		return null
	_projectile_stacks -= 1
	var shot_damage := -1
	if not _projectile_shot_damage.is_empty():
		shot_damage = _projectile_shot_damage.pop_back()
	buffs_changed.emit()
	return shot_damage
