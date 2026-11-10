class_name MemoryInteractable
extends Area2D

## Placeholder memory entity. Interaction UI comes later; for now prints text.

signal memory_triggered(text: String)

@export_multiline var memory_text: String = "..."
@export var interact_action: StringName = &"switch"

var _player_inside: bool = false


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1 << 1 # player
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if not _player_inside:
		return
	if event.is_action_pressed(interact_action) and not event.is_echo():
		trigger()
		get_viewport().set_input_as_handled()


func trigger() -> void:
	print("[Memory] ", memory_text)
	memory_triggered.emit(memory_text)


func _on_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_player_inside = true


func _on_body_exited(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		_player_inside = false
