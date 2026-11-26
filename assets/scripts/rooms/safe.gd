class_name SafeRoom
extends Room

## Rest zone: safezone tiles only (no switchable variants).
## Forces nightmare movement and locks world switching while inside.
## Continuously regenerates PlayerVitality while the player stays inside
## (same style as vigilia drain, but recovering).

## Vitality restored per second while inside (~5s for a full bar at 100 max).
@export var regen_per_second: float = 20.0

var _player: Node2D = null


func on_player_entered(player: Node2D) -> void:
	_player = player
	_force_pesadilla_and_lock()
	_set_safe_music(true)
	# Mode listeners may refresh beds in the same frame; re-assert after.
	call_deferred("_set_safe_music", true)
	# Checkpoint: spawn here + progress (cleared rooms, map, memories).
	_write_checkpoint()


func on_player_exited(_exiting: Node2D) -> void:
	_player = null
	_set_safe_music(false)
	_unlock_switch()


func sync_mode() -> void:
	# No Switchable tile variants — keep the player on nightmare movement.
	# Re-assert safe music here so WorldMode refreshes cannot leave nightmare bed up.
	if is_active():
		_force_pesadilla_and_lock()
		_set_safe_music(true)
	call_deferred("_sync_all_enemies_mode")


func _force_pesadilla_and_lock() -> void:
	WorldMode.set_mode(WorldMode.MODE_PESADILLA)
	WorldMode.set_locked(true)


func _unlock_switch() -> void:
	WorldMode.set_locked(false)


func _set_safe_music(active: bool) -> void:
	var sfx := _get_general_sfx()
	if sfx == null:
		return
	if active and sfx.has_method("set_room_music"):
		sfx.call("set_room_music", &"safe_zone")
	elif not active and sfx.has_method("clear_room_music"):
		sfx.call("clear_room_music")


func _get_general_sfx() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var from_group := tree.get_first_node_in_group("sfx_general")
	if from_group != null:
		return from_group
	# Fallback when group is not registered yet (early enter).
	var root := tree.current_scene
	if root != null:
		return root.get_node_or_null("SfxGeneral")
	return null


func _process(delta: float) -> void:
	if not is_active() or _player == null or regen_per_second <= 0.0:
		return
	_regen_vitality(regen_per_second * delta)


func _regen_vitality(amount: float) -> void:
	if _player == null or amount <= 0.0:
		return
	if _player.has_method("heal_vitality"):
		_player.call("heal_vitality", amount)
		return
	var vit: Node = _player.get_node_or_null("Vitality")
	if vit != null and vit.has_method("heal"):
		vit.call("heal", amount)


func _write_checkpoint() -> void:
	save_state(RunState)
	if RunState != null and RunState.has_method("save_checkpoint"):
		RunState.save_checkpoint(self)
