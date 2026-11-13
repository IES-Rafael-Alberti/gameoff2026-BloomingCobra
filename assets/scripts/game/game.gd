extends Node2D

var _hitbox_debug: Node2D

@onready var sfx_general: Node = get_node_or_null("SfxGeneral")
@onready var room_manager: Node = get_node_or_null("RoomManager")


func _ready() -> void:
	_hitbox_debug = Node2D.new()
	_hitbox_debug.name = "HitboxDebug"
	_hitbox_debug.set_script(load("res://assets/scripts/game/hitbox_debug.gd"))
	add_child(_hitbox_debug)
	_setup_debug_boss_button()


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
		return

	if event.is_action_pressed("debug_boss_room") and not event.is_echo():
		_debug_teleport_to_boss()
		get_viewport().set_input_as_handled()


func _setup_debug_boss_button() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugUI"
	layer.layer = 100
	add_child(layer)

	var button := Button.new()
	button.name = "DebugBossTeleport"
	button.text = "Boss Room (F3)"
	button.position = Vector2(12, 12)
	button.custom_minimum_size = Vector2(140, 28)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_debug_teleport_to_boss)
	layer.add_child(button)


func _debug_teleport_to_boss() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		print("[Debug] Boss teleport failed: no player")
		return

	var boss_room: Room = null
	for node in get_tree().get_nodes_in_group("rooms"):
		if node is Room and String(node.name).begins_with("BossRoom"):
			boss_room = node as Room
			break
	if boss_room == null:
		boss_room = get_node_or_null("Habitaciones/BossRoom") as Room
	if boss_room == null:
		print("[Debug] Boss teleport failed: BossRoom not found")
		return

	# Activate the room first so camera limits update, then place the player.
	if room_manager != null and room_manager.has_method("enter_room"):
		room_manager.call("enter_room", boss_room, player)
	else:
		boss_room.set_active(true, player)

	var bounds := boss_room.get_camera_bounds()
	var target := bounds.get_center() if bounds.size != Vector2.ZERO else boss_room.global_position
	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity = Vector2.ZERO
	player.global_position = target

	var cam := player.get_node_or_null("Camera2D")
	if cam != null and cam.has_method("snap_to_room"):
		cam.call("snap_to_room", boss_room)
	elif cam is Camera2D:
		var camera := cam as Camera2D
		camera.make_current()
		camera.reset_smoothing()
		camera.force_update_scroll()

	# Keep debug teleport snappy even if room_changed fired with stale/empty bounds.
	call_deferred("_debug_resnap_camera", boss_room)


func _debug_resnap_camera(boss_room: Room) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or boss_room == null:
		return
	var cam := player.get_node_or_null("Camera2D")
	if cam != null and cam.has_method("snap_to_room"):
		cam.call("snap_to_room", boss_room)
	print("[Debug] Teleported to BossRoom bounds=", boss_room.get_camera_bounds())


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
