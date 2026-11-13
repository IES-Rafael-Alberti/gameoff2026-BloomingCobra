extends Node2D

var _hitbox_debug: Node2D

@onready var sfx_general: Node = get_node_or_null("SfxGeneral")


func _ready() -> void:
	_hitbox_debug = Node2D.new()
	_hitbox_debug.name = "HitboxDebug"
	_hitbox_debug.set_script(load("res://assets/scripts/game/hitbox_debug.gd"))
	add_child(_hitbox_debug)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and not event.is_echo():
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("switch") and not event.is_echo():
		if WorldMode.toggle():
			if sfx_general != null and sfx_general.has_method("play_switch"):
				sfx_general.call("play_switch")
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_hitboxes") and not event.is_echo():
		if _hitbox_debug != null and _hitbox_debug.has_method("toggle"):
			var on: bool = _hitbox_debug.toggle()
			print("[Debug] Hitboxes visible: ", on)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("debug_god_mode") and not event.is_echo():
		var player := get_tree().get_first_node_in_group("player")
		var vit: Node = null
		if player != null:
			vit = player.get_node_or_null("Vitality")
		if vit != null and vit.has_method("toggle_invulnerable"):
			var on: bool = bool(vit.call("toggle_invulnerable"))
			print("[Debug] God mode (no vitality loss): ", on)
		get_viewport().set_input_as_handled()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
