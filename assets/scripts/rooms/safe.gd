class_name SafeRoom
extends Room

## Rest zone: safezone tiles only (no switchable variants).
## Forces nightmare movement and locks world switching while inside.

@export var heal_on_enter: bool = true
@export var heal_per_second: float = 1.0

var _heal_accumulator: float = 0.0
var _player: Node2D = null


func on_player_entered(player: Node2D) -> void:
	_player = player
	_heal_accumulator = 0.0
	_force_pesadilla_and_lock()
	_set_safe_music(true)
	if heal_on_enter:
		_heal_player(true)


func on_player_exited(_player: Node2D) -> void:
	_player = null
	_heal_accumulator = 0.0
	_set_safe_music(false)
	_unlock_switch()


func sync_mode() -> void:
	# No Switchable tile variants — keep the player on nightmare movement.
	if is_active():
		_force_pesadilla_and_lock()
	call_deferred("_sync_all_enemies_mode")


func _force_pesadilla_and_lock() -> void:
	WorldMode.set_mode(WorldMode.MODE_PESADILLA)
	WorldMode.set_locked(true)


func _unlock_switch() -> void:
	WorldMode.set_locked(false)


func _set_safe_music(active: bool) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx_general")
	if sfx == null:
		return
	if active and sfx.has_method("set_room_music"):
		sfx.call("set_room_music", &"safe_zone")
	elif not active and sfx.has_method("clear_room_music"):
		sfx.call("clear_room_music")


func _process(delta: float) -> void:
	if not is_active() or _player == null or heal_per_second <= 0.0:
		return
	_heal_accumulator += heal_per_second * delta
	if _heal_accumulator >= 1.0:
		var amount := floori(_heal_accumulator)
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
