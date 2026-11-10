class_name Door
extends StaticBody2D

## Layer bits (1-based Godot layers):
## 1 world, 2 player, 3 enemy, 4 door_enemy, 5 door_player
const LAYER_DOOR_ENEMY := 1 << 3
const LAYER_DOOR_PLAYER := 1 << 4

@export var starts_open: bool = false

var _open: bool = false


func _ready() -> void:
	add_to_group("door")
	collision_mask = 0
	# Stay solid even if the parent room pauses with PROCESS_MODE_DISABLED.
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE

	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.disabled:
		starts_open = true

	set_open(starts_open)


func set_open(open: bool) -> void:
	_open = open
	for child in get_children():
		if child is CollisionShape2D:
			# Shapes stay enabled; open/closed is handled by layers.
			# Defer in case this is called from a physics body_entered callback.
			child.set_deferred("disabled", false)

	# Only enemies collide when open — player can pass.
	var layer := LAYER_DOOR_ENEMY if _open else (LAYER_DOOR_ENEMY | LAYER_DOOR_PLAYER)
	set_deferred("collision_layer", layer)


func is_open() -> bool:
	return _open


func toggle_open() -> void:
	set_open(not _open)
