class_name PropButton
extends Area2D

## Floor button: player steps on it to press. Emits `pressed` / `released`.

signal pressed
signal released

@export var unpressed_texture: Texture2D = preload("res://assets/sprittesheets/props/placeholders/interactive/unpressed_button.png")
@export var pressed_texture: Texture2D = preload("res://assets/sprittesheets/props/placeholders/interactive/pressed_button.png")
## If true, stays down after stepping off until reset() (e.g. void fall) or commit().
@export var stay_pressed: bool = true
@export var one_shot: bool = false

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

var _is_pressed: bool = false
var _committed: bool = false
var _bodies_on: int = 0


func _ready() -> void:
	add_to_group("prop_button")
	process_mode = Node.PROCESS_MODE_ALWAYS
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	collision_layer = 0
	collision_mask = 1 << 1 # player body
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	_update_visual()


func is_pressed() -> bool:
	return _is_pressed


func is_committed() -> bool:
	return _committed


## Permanent press after leaving the room successfully. Ignores future reset().
func commit() -> void:
	_committed = true
	_is_pressed = true
	_update_visual()


func reset() -> void:
	if _committed:
		return
	_is_pressed = false
	_bodies_on = 0
	_update_visual()


func force_pressed(emit_pressed_signal: bool = false) -> void:
	var was_pressed := _is_pressed
	_is_pressed = true
	_update_visual()
	if emit_pressed_signal and not was_pressed:
		pressed.emit()


func _on_body_entered(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_bodies_on += 1
	_set_pressed(true)


func _on_body_exited(body: Node2D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_bodies_on = maxi(_bodies_on - 1, 0)
	if _committed or stay_pressed or _bodies_on > 0:
		return
	_set_pressed(false)


func _set_pressed(value: bool) -> void:
	if _committed:
		return
	if value and one_shot and _is_pressed:
		return
	if value == _is_pressed:
		return
	_is_pressed = value
	_update_visual()
	if _is_pressed:
		pressed.emit()
	else:
		released.emit()


func _update_visual() -> void:
	if sprite == null:
		sprite = get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return
	sprite.texture = pressed_texture if _is_pressed else unpressed_texture
