extends Node2D

var _hitbox_debug: Node2D

@onready var sfx_general: Node = get_node_or_null("SfxGeneral")


func _ready() -> void:
	_hitbox_debug = Node2D.new()
	_hitbox_debug.name = "HitboxDebug"
	_hitbox_debug.set_script(load("res://assets/scripts/game/hitbox_debug.gd"))
	add_child(_hitbox_debug)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch") and not event.is_echo():
		if sfx_general != null and sfx_general.has_method("play_switch"):
			sfx_general.call("play_switch")
		for node in get_tree().get_nodes_in_group("switchable"):
			if node.has_method("toggle"):
				node.toggle()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_hitboxes") and not event.is_echo():
		if _hitbox_debug != null and _hitbox_debug.has_method("toggle"):
			var on: bool = _hitbox_debug.toggle()
			print("[Debug] Hitboxes visible: ", on)
		get_viewport().set_input_as_handled()
