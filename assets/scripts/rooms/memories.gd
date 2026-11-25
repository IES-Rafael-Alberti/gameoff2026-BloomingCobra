class_name MemoriesRoom
extends Room

## Small empty room that holds a memory interactable (UI later).

@export var memory: MemoryInteractable


func on_player_entered(_player: Node2D) -> void:
	if memory == null:
		memory = _find_memory()
	_set_memories_music(true)


func on_player_exited(_player: Node2D) -> void:
	_set_memories_music(false)


func _find_memory() -> MemoryInteractable:
	for child in get_children():
		if child is MemoryInteractable:
			return child
	return null


func _set_memories_music(active: bool) -> void:
	var sfx := get_tree().get_first_node_in_group("sfx_general")
	if sfx == null:
		return
	if active and sfx.has_method("set_room_music"):
		sfx.call("set_room_music", &"memories")
	elif not active and sfx.has_method("clear_room_music"):
		sfx.call("clear_room_music")

