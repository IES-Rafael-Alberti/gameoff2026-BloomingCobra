class_name PlayerVitality
extends Node

## Player life bar. Drains in Sueño/Vigilia; enemy/spike hits also reduce it.
## Hitting 0 kills the player.

signal vitality_changed(current: float, max_vitality: float, ratio: float)
signal depleted

@export var max_vitality: float = 100.0
## Full bar lasts ~40s at the default rate.
@export var drain_per_second: float = 2.5
## How much bar each Damageable damage point removes (contact_damage 1 → 10).
@export var vitality_per_damage_point: float = 10.0
@export var cat_heal_amount: float = 40.0

var current: float = 100.0

var _dead: bool = false
## Debug: ignore drain and hit damage.
var _invulnerable: bool = false


func _ready() -> void:
	current = max_vitality
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	## Clear any leftover world locks from older builds.
	_clear_world_locks()
	_emit_changed()


func tick(delta: float, in_vigil: bool) -> void:
	if _dead or _invulnerable:
		return
	if not in_vigil or current <= 0.0 or drain_per_second <= 0.0:
		return
	_lose(drain_per_second * delta)


## Enemy / spike / hazard hits routed from Damageable.damaged.
func apply_hit_damage(amount: int) -> float:
	if _dead or _invulnerable or amount <= 0:
		return 0.0
	return _lose(float(amount) * maxf(vitality_per_damage_point, 0.0))


func set_invulnerable(enabled: bool) -> void:
	_invulnerable = enabled


func is_invulnerable() -> bool:
	return _invulnerable


func toggle_invulnerable() -> bool:
	_invulnerable = not _invulnerable
	return _invulnerable


func heal(amount: float) -> float:
	if _dead or amount <= 0.0 or max_vitality <= 0.0:
		return 0.0
	var before := current
	current = minf(current + amount, max_vitality)
	var gained := current - before
	if gained > 0.0:
		_emit_changed()
	return gained


func heal_from_cat() -> float:
	return heal(cat_heal_amount)


func get_ratio() -> float:
	if max_vitality <= 0.0:
		return 0.0
	return clampf(current / max_vitality, 0.0, 1.0)


func is_depleted() -> bool:
	return _dead or current <= 0.0


func _lose(amount: float) -> float:
	if _dead or _invulnerable or amount <= 0.0 or current <= 0.0:
		return 0.0
	var before := current
	current = maxf(current - amount, 0.0)
	var lost := before - current
	if lost > 0.0:
		_emit_changed()
	if current <= 0.0 and before > 0.0:
		_dead = true
		depleted.emit()
	return lost


func _emit_changed() -> void:
	vitality_changed.emit(current, max_vitality, get_ratio())


func _clear_world_locks() -> void:
	WorldMode.set_locked(false)
