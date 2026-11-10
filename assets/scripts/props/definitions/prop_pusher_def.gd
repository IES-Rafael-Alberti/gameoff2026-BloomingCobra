class_name PropPusherDef
extends PropDefinition

## Moving block that pushes the player (parkour / vigilia).

@export var move_speed: float = 40.0
## Local offset from start position to the opposite ping-pong point.
@export var travel: Vector2 = Vector2(64, 0)
## 0 = start at origin, 0.5 = mid travel, etc.
@export_range(0.0, 1.0, 0.01) var start_offset: float = 0.0


func _init() -> void:
	placeholder_color = Color(0.55, 0.35, 0.75, 1.0)
	collision_size = Vector2(16, 16)
	if display_name.is_empty():
		display_name = "Pusher"
