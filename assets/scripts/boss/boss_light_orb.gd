class_name BossLightOrb
extends Node2D

## Visual epilogue for the defeated boss: a warm light that rises and fades,
## then hands control to the room so it can fade to the title screen.

signal finished

@export var rise_distance: float = 36.0
@export var appear_duration: float = 0.3
@export var rise_duration: float = 1.2
@export var hold_duration: float = 0.5


func _ready() -> void:
	play()


func play() -> void:
	modulate.a = 0.0
	scale = Vector2.ONE * 0.45
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
	finished.emit()
