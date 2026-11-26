class_name MemoriesRoom
extends Room

## Small empty room that holds a memory interactable (UI later).

@export var memory: MemoryInteractable


func load_state(_run_state: Node = null) -> void:
	super.load_state(_run_state)
	if memory == null:
		memory = _find_memory()
	# MemoryInteractable removes itself in _ready when already collected.


func on_player_entered(_player: Node2D) -> void:
	if memory == null:
		memory = _find_memory()
	_set_memories_music(true)
	# Mode listeners may refresh beds in the same frame; re-assert after.
	call_deferred("_set_memories_music", true)


func on_player_exited(_player: Node2D) -> void:
	_set_memories_music(false)


func sync_mode() -> void:
	if is_active():
		_set_memories_music(true)
	call_deferred("_sync_all_enemies_mode")


func _find_memory() -> MemoryInteractable:
	for child in get_children():
		if child is MemoryInteractable:
			return child
	return null


func _set_memories_music(active: bool) -> void:
	var sfx := _get_general_sfx()
	if sfx == null:
		return
	if active and sfx.has_method("set_room_music"):
		sfx.call("set_room_music", &"memories")
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
