class_name ParkourRoom
extends Room

## Closed exit until the challenge is done. Falling into the void resets to start.
## Forces dream mode and locks switching to nightmare while inside.
## Enable Button Unlock + assign PropButtons (interactive/button.tscn) to open the exit.
## Falling resets uncommitted buttons; leaving the room with them pressed commits them.

@export var exit_door: Door
@export var respawn_point: Marker2D
@export var void_area: Area2D
@export var keep_exit_closed: bool = true

var _void_connected: bool = false


func _ready() -> void:
	super._ready()
	if exit_door != null and keep_exit_closed:
		exit_door.set_open(false)
	_setup_void_area()


func on_player_entered(_player: Node2D) -> void:
	_force_dream_and_lock()
	if exit_door != null and keep_exit_closed and not _button_unlock_done and not _button_unlock_committed:
		exit_door.set_open(false)
	elif exit_door != null and (_button_unlock_done or _button_unlock_committed):
		exit_door.set_open(true)
	_setup_void_area()
	# If the player already overlaps the void (or re-entered mid-fall), catch it.
	call_deferred("_respawn_if_overlapping_void")


func on_player_exited(player: Node2D) -> void:
	_unlock_switchables()
	# Falling into the void also deactivates the room — don't treat that as success.
	if _is_void_exit(player):
		return
	# Left through the exit with the button pressed → keep it down next visit.
	commit_unlock_buttons()


func _is_void_exit(player: Node2D) -> bool:
	if player == null:
		return false
	if void_area == null:
		void_area = get_node_or_null("Void") as Area2D
	if void_area == null:
		return false
	if void_area.overlaps_body(player):
		return true
	# Player may already be mid-teleport; treat being at/near respawn right after a fall the same.
	return false


func on_button_unlock() -> void:
	if exit_door != null:
		exit_door.set_open(true)
	else:
		set_all_doors_open(true)


func _physics_process(_delta: float) -> void:
	if not is_active():
		return
	_respawn_if_overlapping_void()


func _setup_void_area() -> void:
	if void_area == null:
		void_area = get_node_or_null("Void") as Area2D
	if void_area == null:
		return

	# Keep detecting even if the room briefly deactivates while falling out of bounds.
	void_area.process_mode = Node.PROCESS_MODE_ALWAYS
	void_area.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	# Detect player physics layer only (layer 2 → bit 1).
	void_area.collision_layer = 0
	void_area.collision_mask = 1 << 1
	void_area.monitoring = true
	void_area.monitorable = false

	if not _void_connected:
		void_area.body_entered.connect(_on_void_body_entered)
		_void_connected = true


func _on_void_body_entered(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	_respawn_player(body as Node2D)


func _respawn_if_overlapping_void() -> void:
	if void_area == null or not void_area.monitoring:
		return
	for body in void_area.get_overlapping_bodies():
		if body != null and body.is_in_group("player"):
			_respawn_player(body as Node2D)
			return


func _respawn_player(player: Node2D) -> void:
	if respawn_point == null:
		respawn_point = get_node_or_null("Respawn") as Marker2D
	if respawn_point == null or player == null:
		return

	player.global_position = respawn_point.global_position
	if player is CharacterBody2D:
		var body := player as CharacterBody2D
		body.velocity = Vector2.ZERO
		if "_knockback" in body:
			body.set("_knockback", Vector2.ZERO)

	# Falling can deactivate this room; snap + re-enter so dream lock stays on.
	if not is_active():
		set_active(true, player)

	# Void fall undoes button progress unless it was committed by leaving the room.
	reset_unlock_buttons()
	if keep_exit_closed and exit_door != null and not _button_unlock_committed:
		exit_door.set_open(false)


func _force_dream_and_lock() -> void:
	for node in get_tree().get_nodes_in_group("switchable"):
		if node.has_method("set_mode"):
			node.set_mode(1) # MODE_SUENO
		if node.has_method("set_locked"):
			node.set_locked(true)


func _unlock_switchables() -> void:
	for node in get_tree().get_nodes_in_group("switchable"):
		if node.has_method("set_locked"):
			node.set_locked(false)
