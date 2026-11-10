class_name PusherProp
extends AnimatableBody2D

## Ping-pong moving block that pushes CharacterBody2Ds (player / enemies).

const LAYER_WORLD := 1 << 0
const DEFAULT_DEFINITION := preload("res://assets/resources/props/pusher_horizontal.tres")

@export var definition: PropPusherDef = DEFAULT_DEFINITION
## Overrides definition.travel when non-zero (handy per-instance in rooms).
@export var travel_override: Vector2 = Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _point_a: Vector2
var _point_b: Vector2
var _speed: float = 40.0
var _t: float = 0.0
var _forward: bool = true


func _ready() -> void:
	add_to_group("prop_pusher")
	z_index = maxi(z_index, 1)
	collision_layer = LAYER_WORLD
	collision_mask = 0
	sync_to_physics = true
	apply_definition()
	_point_a = global_position
	var def: PropPusherDef = definition if definition != null else DEFAULT_DEFINITION
	var travel := def.travel
	if travel_override != Vector2.ZERO:
		travel = travel_override
	_point_b = _point_a + travel
	_t = clampf(def.start_offset, 0.0, 1.0)
	_speed = maxf(def.move_speed, 1.0)
	global_position = _point_a.lerp(_point_b, _t)


func apply_definition() -> void:
	var def: PropPusherDef = definition if definition != null else DEFAULT_DEFINITION
	def.apply_visual(sprite, self)
	def.apply_collision_shape(collision_shape)
	_speed = maxf(def.move_speed, 1.0)


func _physics_process(delta: float) -> void:
	var dist := _point_a.distance_to(_point_b)
	if dist <= 0.001:
		return
	var step := (_speed * delta) / dist
	if _forward:
		_t = minf(_t + step, 1.0)
		if _t >= 1.0:
			_forward = false
	else:
		_t = maxf(_t - step, 0.0)
		if _t <= 0.0:
			_forward = true
	global_position = _point_a.lerp(_point_b, _t)
