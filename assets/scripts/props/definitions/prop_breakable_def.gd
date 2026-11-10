class_name PropBreakableDef
extends PropDefinition

## Static breakable block / crate / vase.

@export var max_health: int = 2
@export var destroy_on_death: bool = true
@export var loot_scene: PackedScene
@export_range(0.0, 1.0, 0.01) var loot_chance: float = 0.0
@export var hit_invulnerability_time: float = 0.05


func _init() -> void:
	placeholder_color = Color(0.72, 0.48, 0.28, 1.0)
	if display_name.is_empty():
		display_name = "Breakable"
