class_name SafeRoom
extends Room

## Rest zone: player can recover health while inside.

@export var heal_on_enter: bool = true
@export var heal_per_second: float = 1.0

var _heal_accumulator: float = 0.0
var _player: Node2D = null


func on_player_entered(player: Node2D) -> void:
	_player = player
	_heal_accumulator = 0.0
	if heal_on_enter:
		_heal_player(true)


func on_player_exited(_player: Node2D) -> void:
	_player = null
	_heal_accumulator = 0.0


func _process(delta: float) -> void:
	if not is_active() or _player == null or heal_per_second <= 0.0:
		return
	_heal_accumulator += heal_per_second * delta
	if _heal_accumulator >= 1.0:
		var amount := int(floor(_heal_accumulator))
		_heal_accumulator -= float(amount)
		_apply_heal(amount)


func _heal_player(full: bool) -> void:
	var dmg := _get_player_damageable()
	if dmg == null:
		return
	if full and dmg.has_method("heal_full"):
		dmg.heal_full()
	elif dmg.has_method("heal"):
		dmg.heal(1)


func _apply_heal(amount: int) -> void:
	var dmg := _get_player_damageable()
	if dmg != null and dmg.has_method("heal"):
		dmg.heal(amount)


func _get_player_damageable() -> Node:
	if _player == null:
		return null
	return _player.get_node_or_null("Damageable")
