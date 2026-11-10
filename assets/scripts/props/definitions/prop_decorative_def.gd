class_name PropDecorativeDef
extends PropDefinition

## Scene dressing (lamps, signs…). Optionally blocks movement.

## If false, sprite-only decoration (no physics blocking).
@export var blocks_movement: bool = false


func _init() -> void:
	placeholder_color = Color(0.45, 0.65, 0.55, 1.0)
	if display_name.is_empty():
		display_name = "Decorative"
