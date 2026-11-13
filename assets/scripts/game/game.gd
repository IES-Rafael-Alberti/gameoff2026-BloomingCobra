extends Node2D

var _hitbox_debug: Node2D
var _bg_pesadilla: Sprite2D
var _bg_sueno: Sprite2D
var _player: Node2D

@onready var sfx_general: Node = get_node_or_null("SfxGeneral")
@onready var room_manager: Node = get_node_or_null("RoomManager")


func _ready() -> void:
	_hitbox_debug = Node2D.new()
	_hitbox_debug.name = "HitboxDebug"
	_hitbox_debug.set_script(load("res://assets/scripts/game/hitbox_debug.gd"))
	add_child(_hitbox_debug)
	_setup_debug_boss_button()
	_setup_world_backgrounds()
	if room_manager != null and room_manager.has_signal("room_changed"):
		if not room_manager.room_changed.is_connected(_on_room_changed_backgrounds):
			room_manager.room_changed.connect(_on_room_changed_backgrounds)
	set_process(true)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return
	_snap_backgrounds(_background_follow_target())


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

	_snap_backgrounds(target)

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


func _setup_world_backgrounds() -> void:
	var root := get_node_or_null("WorldBackgrounds") as Node2D
	if root == null:
		root = Node2D.new()
		root.name = "WorldBackgrounds"
		root.z_index = -100
		add_child(root)
		move_child(root, 0)

	_bg_pesadilla = root.get_node_or_null("BackgroundPesadilla") as Sprite2D
	_bg_sueno = root.get_node_or_null("BackgroundSueño") as Sprite2D

	if _bg_pesadilla == null:
		_bg_pesadilla = _make_bg_sprite(
			"BackgroundPesadilla",
			preload("res://assets/scenary/fondopedasilla.png")
		)
		root.add_child(_bg_pesadilla)
	if _bg_sueno == null:
		_bg_sueno = _make_bg_sprite(
			"BackgroundSueño",
			preload("res://assets/scenary/fondopevigilia.png")
		)
		root.add_child(_bg_sueno)

	if not WorldMode.mode_changed.is_connected(_on_world_mode_changed_backgrounds):
		WorldMode.mode_changed.connect(_on_world_mode_changed_backgrounds)
	_on_world_mode_changed_backgrounds(WorldMode.get_mode())


func _make_bg_sprite(node_name: String, texture: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.z_index = -100
	sprite.centered = true
	# 3840x2160 art; cover zoomed gameplay view with margin.
	sprite.scale = Vector2(0.12, 0.12)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return sprite


func _on_world_mode_changed_backgrounds(mode: int) -> void:
	if _bg_pesadilla != null:
		_bg_pesadilla.visible = mode == WorldMode.MODE_PESADILLA
	if _bg_sueno != null:
		_bg_sueno.visible = mode == WorldMode.MODE_SUENO
	_snap_backgrounds(_background_follow_target())


func _background_follow_target() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return Vector2.ZERO
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	if cam != null and cam.is_current():
		return cam.get_screen_center_position()
	return _player.global_position


func _snap_backgrounds(pos: Vector2) -> void:
	if _bg_pesadilla != null:
		_bg_pesadilla.global_position = pos
	if _bg_sueno != null:
		_bg_sueno.global_position = pos


func _on_room_changed_backgrounds(_previous: Room, _next: Room) -> void:
	_snap_backgrounds(_background_follow_target())
