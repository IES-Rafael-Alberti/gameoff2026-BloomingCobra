class_name BossLightOrb
extends Node2D

## Visual epilogue for the defeated boss: a warm light rises, blooms until the
## screen turns white, then hands control to the room for the title transition.

signal finished

@export var rise_distance: float = 36.0
@export var appear_duration: float = 0.3
@export var rise_duration: float = 1.2
@export var hold_duration: float = 0.5

@export_group("Bloom")
## Growth of the light while the screen fades to white.
@export var bloom_duration: float = 1.1
@export var bloom_scale: float = 14.0
## Above the HUD/room fades (120), below the scene transition (200).
@export var white_layer: int = 150

var _white_fade: ColorRect = null


func _ready() -> void:
	_build_white_fade()
	play()


func _build_white_fade() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WhiteFadeLayer"
	layer.layer = white_layer
	add_child(layer)
	_white_fade = ColorRect.new()
	_white_fade.name = "WhiteFade"
	_white_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white_fade.color = Color(1, 1, 1, 0)
	_white_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_white_fade)


func play() -> void:
	modulate.a = 0.0
	scale = Vector2.ONE * 0.45
	if _white_fade != null:
		_white_fade.color.a = 0.0
	var glow := get_node_or_null("Glow") as PointLight2D
	var end_y := position.y - rise_distance
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, appear_duration)
	tween.tween_property(self, "scale", Vector2.ONE, appear_duration * 1.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:y", end_y, rise_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished
	if not is_inside_tree():
		return
	if hold_duration > 0.0:
		await get_tree().create_timer(hold_duration).timeout
	if not is_inside_tree():
		return
	await _bloom_to_white(glow)
	if not is_inside_tree():
		return
	finished.emit()


func _bloom_to_white(glow: PointLight2D) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * bloom_scale, bloom_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if glow != null:
		tween.tween_property(glow, "color", Color.WHITE, bloom_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if _white_fade != null:
		tween.tween_property(_white_fade, "color:a", 1.0, bloom_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
