extends Node2D

signal damaged(amount: int, current_health: int)
signal healed(amount: int, current_health: int)
signal died

@export var max_health: int = 3
## After a hit, ignore further damage for this long (stops multi-hit from one touch).
@export var invulnerability_time: float = 0.0
## When true, hits still fire `damaged` but health is never depleted / death never triggers.
@export var immortal: bool = false

var health: int
var _invuln_left: float = 0.0


func _ready() -> void:
	health = max_health


func _process(delta: float) -> void:
	if _invuln_left > 0.0:
		_invuln_left = maxf(_invuln_left - delta, 0.0)


func is_invulnerable() -> bool:
	return _invuln_left > 0.0


func take_damage(amount: int) -> void:
	if amount <= 0 or _invuln_left > 0.0:
		return
	if not immortal and health <= 0:
		return

	if not immortal:
		health = maxi(health - amount, 0)

	if invulnerability_time > 0.0:
		_invuln_left = invulnerability_time

	damaged.emit(amount, health)

	if not immortal and health <= 0:
		died.emit()


func heal(amount: int) -> void:
	if amount <= 0:
		return
	if not immortal and health <= 0:
		return
	var before := health
	health = mini(health + amount, max_health)
	var gained := health - before
	if gained > 0:
		healed.emit(gained, health)


func heal_full() -> void:
	if not immortal and health <= 0:
		return
	var gained := max_health - health
	health = max_health
	if gained > 0:
		healed.emit(gained, health)
