class_name TrapRoom
extends Room

## Locks every door on enter (after a short delay) until enemies are defeated.

var _cleared: bool = false
var _watching: bool = false


func on_player_entered(_player: Node2D) -> void:
	if _cleared:
		spawn_enemies()
		return

	spawn_enemies()
	_watching = true
	_connect_enemy_deaths()
	if not has_alive_enemies():
		_clear_trap()
		return

	await close_doors_after_delay()
	if not is_active() or _cleared:
		return
	_connect_enemy_deaths()


func on_player_exited(_player: Node2D) -> void:
	_watching = false
	cancel_pending_door_close()
	# Never soft-lock the player outside a sealed uncleared trap.
	if not _cleared:
		set_all_doors_open(true)
	commit_unlock_buttons()


func _process(_delta: float) -> void:
	if not _watching or _cleared or not is_active():
		return
	if not has_alive_enemies():
		_clear_trap()


func _connect_enemy_deaths() -> void:
	for enemy in get_alive_enemies():
		var dmg := enemy.get_node_or_null("Damageable")
		if dmg != null and dmg.has_signal("died") and not dmg.died.is_connected(_on_enemy_died):
			dmg.died.connect(_on_enemy_died)


func _on_enemy_died() -> void:
	# Defer so queue_free has removed the enemy from the alive list.
	call_deferred("_check_cleared")


func _check_cleared() -> void:
	if _cleared or not is_active():
		return
	if not has_alive_enemies():
		_clear_trap()


func on_button_unlock() -> void:
	_clear_trap()


func _clear_trap() -> void:
	_cleared = true
	_watching = false
	cancel_pending_door_close()
	set_all_doors_open(true)
