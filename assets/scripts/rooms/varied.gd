class_name VariedRoom
extends Room

## Flexible standard room: enemies, door buttons, shifting puzzles, etc.
## If `doors` are assigned in the inspector, they close on enter (after a short
## delay) and reopen when all spawned enemies are defeated.

@export var spawn_on_enter: bool = true
@export var lock_assigned_doors_on_enter: bool = true

var _cleared: bool = false
var _watching: bool = false


func on_player_entered(_player: Node2D) -> void:
	if spawn_on_enter:
		spawn_enemies()

	if not _should_lock_doors():
		return

	if _cleared:
		return

	_watching = true
	_connect_enemy_deaths()
	if not has_alive_enemies():
		# Avoid soft-lock if no enemies were placed.
		_clear_locks()
		return

	await close_doors_after_delay()
	if not is_active() or _cleared:
		return
	_connect_enemy_deaths()


func on_player_exited(_player: Node2D) -> void:
	_watching = false
	cancel_pending_door_close()
	if not _cleared and _should_lock_doors():
		set_all_doors_open(true)
	commit_unlock_buttons()


func _process(_delta: float) -> void:
	if not _watching or _cleared or not is_active():
		return
	if not has_alive_enemies():
		_clear_locks()


func _should_lock_doors() -> bool:
	return lock_assigned_doors_on_enter and not doors.is_empty()


func _connect_enemy_deaths() -> void:
	for enemy in get_alive_enemies():
		var dmg := enemy.get_node_or_null("Damageable")
		if dmg != null and dmg.has_signal("died") and not dmg.died.is_connected(_on_enemy_died):
			dmg.died.connect(_on_enemy_died)


func _on_enemy_died() -> void:
	call_deferred("_check_cleared")


func _check_cleared() -> void:
	if _cleared or not is_active():
		return
	if not has_alive_enemies():
		_clear_locks()


func on_button_unlock() -> void:
	_clear_locks()


func _clear_locks() -> void:
	_cleared = true
	_watching = false
	cancel_pending_door_close()
	set_all_doors_open(true)
