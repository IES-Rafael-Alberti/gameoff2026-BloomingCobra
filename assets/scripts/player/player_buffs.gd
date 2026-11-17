class_name PlayerBuffs
extends Node

## Timed attack/projectile damage boosts and hit-absorbing shield charges.

signal buffs_changed

@export var default_attack_duration: float = 12.0
@export var default_projectile_duration: float = 12.0
@export var default_attack_bonus: int = 1
@export var default_projectile_bonus: int = 1
@export var default_shield_hits: int = 3

var _attack_left: float = 0.0
var _projectile_left: float = 0.0
var _attack_bonus: int = 0
var _projectile_bonus: int = 0
var _attack_stacks: int = 0
var _projectile_stacks: int = 0
var _shield_hits: int = 0


func _process(delta: float) -> void:
	var changed := false
	if _attack_left > 0.0:
		_attack_left = maxf(_attack_left - delta, 0.0)
		if _attack_left <= 0.0:
			_attack_bonus = 0
			_attack_stacks = 0
			changed = true
	if _projectile_left > 0.0:
		_projectile_left = maxf(_projectile_left - delta, 0.0)
		if _projectile_left <= 0.0:
			_projectile_bonus = 0
			_projectile_stacks = 0
			changed = true
	if changed:
		buffs_changed.emit()


func apply_attack_boost(duration: float = -1.0, bonus: int = -1) -> void:
	var d := duration if duration > 0.0 else default_attack_duration
	var b := bonus if bonus > 0 else default_attack_bonus
	_attack_bonus = maxi(b, 1)
	_attack_left = maxf(d, 0.01)
	_attack_stacks += 1
	buffs_changed.emit()


func apply_projectile_boost(duration: float = -1.0, bonus: int = -1) -> void:
	var d := duration if duration > 0.0 else default_projectile_duration
	var b := bonus if bonus > 0 else default_projectile_bonus
	_projectile_bonus = maxi(b, 1)
	_projectile_left = maxf(d, 0.01)
	_projectile_stacks += 1
	buffs_changed.emit()


func apply_shield(hits: int = -1) -> void:
	var h := hits if hits > 0 else default_shield_hits
	_shield_hits = maxi(_shield_hits, 0) + maxi(h, 1)
	buffs_changed.emit()


func get_melee_damage_bonus() -> int:
	return _attack_bonus if _attack_left > 0.0 else 0


func get_projectile_damage_bonus() -> int:
	return _projectile_bonus if _projectile_left > 0.0 else 0


func get_shield_hits() -> int:
	return _shield_hits


func get_attack_stacks() -> int:
	return _attack_stacks if has_attack_boost() else 0


func get_projectile_stacks() -> int:
	return _projectile_stacks if has_projectile_boost() else 0


func has_attack_boost() -> bool:
	return _attack_left > 0.0 and _attack_bonus > 0


func has_projectile_boost() -> bool:
	return _projectile_left > 0.0 and _projectile_bonus > 0


func get_attack_boost_left() -> float:
	return _attack_left


func get_projectile_boost_left() -> float:
	return _projectile_left


## Consumes one shield charge. Returns true if the hit was absorbed.
func try_absorb_hit() -> bool:
	if _shield_hits <= 0:
		return false
	_shield_hits -= 1
	buffs_changed.emit()
	return true
