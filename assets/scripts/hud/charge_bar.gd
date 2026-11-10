extends Node2D

## Discrete charge states (Isaac-like steps):
## empty → half → full green → red.

@export var empty_texture: Texture2D
@export var green_texture: Texture2D
@export var half_texture: Texture2D
@export var full_texture: Texture2D
@export var offset: Vector2 = Vector2(0, -18)
## When the half sprite appears (matches thrust unlock).
@export var half_threshold: float = 0.5
## When the full green ("entera") sprite appears, before red at 1.0.
@export var full_green_threshold: float = 0.85

@onready var _empty: Sprite2D = $Empty
@onready var _green: Sprite2D = $Green
@onready var _half: Sprite2D = $Half
@onready var _full: Sprite2D = $Full


func _ready() -> void:
	if empty_texture != null:
		_empty.texture = empty_texture
	if green_texture != null:
		_green.texture = green_texture
	if half_texture != null:
		_half.texture = half_texture
	if full_texture != null:
		_full.texture = full_texture

	# No radial shader: each state is a solid sprite.
	_green.material = null
	_empty.z_index = 0
	_half.z_index = 0
	_green.z_index = 0
	_full.z_index = 0

	position = offset
	hide_bar()


func show_charge(ratio: float) -> void:
	visible = true
	ratio = clampf(ratio, 0.0, 1.0)

	_empty.visible = false
	_half.visible = false
	_green.visible = false
	_full.visible = false

	if ratio >= 1.0:
		_full.visible = true
	elif ratio >= full_green_threshold:
		_green.visible = true
	elif ratio >= half_threshold:
		_half.visible = true
	else:
		_empty.visible = true


func hide_bar() -> void:
	visible = false
	_empty.visible = false
	_half.visible = false
	_green.visible = false
	_full.visible = false
