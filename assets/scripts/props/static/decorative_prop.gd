class_name DecorativeProp
extends StaticBody2D

## Decorative prop; collision optional via PropDecorativeDef.blocks_movement.

const LAYER_WORLD := 1 << 0
const DEFAULT_DEFINITION := preload("res://assets/resources/props/decorative_lamp.tres")

@export var definition: PropDecorativeDef = DEFAULT_DEFINITION
## Vertical float amplitude in pixels. 0 = no float.
@export var float_amplitude: float = 0.0
## Full up-down cycles per second.
@export var float_speed: float = 0.7

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _float_phase: float = 0.0
var _sprite_base_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("prop_decorative")
	z_index = maxi(z_index, 1)
	apply_definition()
	if sprite != null:
		_sprite_base_pos = sprite.position
	_float_phase = randf() * TAU
	set_process(float_amplitude > 0.0)


func _process(delta: float) -> void:
	if sprite == null or float_amplitude <= 0.0:
		return
	_float_phase += delta * float_speed * TAU
	sprite.position = _sprite_base_pos + Vector2(0.0, sin(_float_phase) * float_amplitude)


func apply_definition() -> void:
	var def: PropDecorativeDef = definition if definition != null else DEFAULT_DEFINITION
	def.apply_visual(sprite, self)
	def.apply_collision_shape(collision_shape)
	if def.blocks_movement:
		collision_layer = LAYER_WORLD
		collision_mask = 0
		if collision_shape != null:
			collision_shape.disabled = false
	else:
		collision_layer = 0
		collision_mask = 0
		if collision_shape != null:
			collision_shape.disabled = true
