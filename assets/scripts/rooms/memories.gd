class_name MemoriesRoom
extends Room

## Small empty room that holds a memory interactable (UI later).

@export var memory: MemoryInteractable


func on_player_entered(_player: Node2D) -> void:
	if memory == null:
		memory = _find_memory()


func _find_memory() -> MemoryInteractable:
	for child in get_children():
		if child is MemoryInteractable:
			return child
	return null
