class_name PropButton
extends Area2D

## Floor button: player steps on it to press. Visual via AnimatedSprite2D states.

signal pressed
signal released

@export var unpressed_anim: StringName = &"unpressed"
@export var pressed_anim: StringName = &"pressed"
## Optional: swap art when WorldMode changes. Leave empty on mode-specific scenes.
@export var pesadilla_frames: SpriteFrames
@export var vigilia_frames: SpriteFrames
## If true, stays down after stepping off until reset() (e.g. void fall) or commit().
@export var stay_pressed: bool = true
@export var one_shot: bool = false

@onready var animated_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D

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
	if _has_mode_frames() and WorldMode != null:
		if not WorldMode.mode_changed.is_connected(_on_world_mode_changed):
			WorldMode.mode_changed.connect(_on_world_mode_changed)
		_apply_mode_frames(WorldMode.get_mode())
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


func _on_world_mode_changed(mode: int) -> void:
	_apply_mode_frames(mode)
	_update_visual()


func _has_mode_frames() -> bool:
	return pesadilla_frames != null and vigilia_frames != null


func _apply_mode_frames(mode: int) -> void:
	if animated_sprite == null:
		animated_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if animated_sprite == null or not _has_mode_frames():
		return
	animated_sprite.sprite_frames = (
		vigilia_frames if mode == WorldMode.MODE_SUENO else pesadilla_frames
	)


func _update_visual() -> void:
	if animated_sprite == null:
		animated_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	var anim := pressed_anim if _is_pressed else unpressed_anim
	if not animated_sprite.sprite_frames.has_animation(anim):
		return
	if animated_sprite.animation != anim or not animated_sprite.is_playing():
		animated_sprite.play(anim)
