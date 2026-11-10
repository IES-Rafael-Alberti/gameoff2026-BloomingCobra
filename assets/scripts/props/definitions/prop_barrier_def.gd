class_name PropBarrierDef
extends PropDefinition

## Indestructible solid block.


func _init() -> void:
	placeholder_color = Color(0.35, 0.38, 0.45, 1.0)
	if display_name.is_empty():
		display_name = "Barrier"
