class_name ParkourRoom
extends Room

## Closed exit until the challenge is done. Falling into the void resets to start.
## Forces dream mode and locks switching to nightmare while inside.
## Enable Button Unlock + assign PropButtons (interactive/button.tscn) to open the exit.
## Falling resets uncommitted buttons; leaving the room with them pressed commits them.
## Void uses coyote time, then a shrink fall beat, then respawn.

@export var exit_door: Door
@export var respawn_point: Marker2D
@export var void_area: Area2D
@export var keep_exit_closed: bool = true
## Grace time over a hole before the fall commits (lets the player step back).
@export var void_coyote_time: float = 0.2
## Shrink / fall beat before teleporting back to the respawn marker.
@export var void_fall_duration: float = 0.7

var _void_connected: bool = false
var _void_overlap_time: float = 0.0
var _void_falling: bool = false


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
	# If the player already overlaps the void (or re-entered mid-fall), resume coyote.
	_void_overlap_time = 0.0


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
	if _void_falling:
		return true
	if player.has_method("is_void_falling") and bool(player.call("is_void_falling")):
		return true
	if void_area == null:
		void_area = get_node_or_null("Void") as Area2D
	if void_area == null:
		return false
	if void_area.overlaps_body(player):
		return true
	return false


func on_button_unlock() -> void:
	if exit_door != null:
		exit_door.set_open(true)
	else:
		set_all_doors_open(true)


func _physics_process(delta: float) -> void:
	if not is_active() or _void_falling:
		return
	_process_void_coyote(delta)


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
		# Coyote is driven from _physics_process; exiting the hole resets the grace timer.
		void_area.body_exited.connect(_on_void_body_exited)
		_void_connected = true


func _on_void_body_exited(body: Node) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if not _void_falling:
		_void_overlap_time = 0.0


func _process_void_coyote(delta: float) -> void:
	var player := _get_player_in_void()
	if player == null:
		_void_overlap_time = 0.0
		return
	if player.has_method("is_void_falling") and bool(player.call("is_void_falling")):
		return

	_void_overlap_time += delta
	if _void_overlap_time >= maxf(void_coyote_time, 0.0):
		_void_overlap_time = 0.0
		_begin_void_fall(player)


func _get_player_in_void() -> Node2D:
	if void_area == null or not void_area.monitoring:
		return null
	for body in void_area.get_overlapping_bodies():
		if body != null and body.is_in_group("player"):
			return body as Node2D
	return null


func _begin_void_fall(player: Node2D) -> void:
	if _void_falling or player == null:
		return
	_void_falling = true
	_void_overlap_time = 0.0

	if player.has_method("play_void_fall"):
		await player.call("play_void_fall", void_fall_duration)
	else:
		await get_tree().create_timer(maxf(void_fall_duration, 0.01)).timeout

	if not is_instance_valid(player):
		_void_falling = false
		return

	_respawn_player(player)
	_void_falling = false


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
	if player.has_method("finish_void_fall"):
		player.call("finish_void_fall")

	# Falling can deactivate this room; snap + re-enter so dream lock stays on.
	var manager := get_tree().get_first_node_in_group("room_manager")
	if manager != null and manager.has_method("enter_room"):
		manager.call("enter_room", self, player)
	elif not is_active():
		set_active(true, player)

	# Void fall undoes button progress unless it was committed by leaving the room.
	reset_unlock_buttons()
	if keep_exit_closed and exit_door != null and not _button_unlock_committed:
		exit_door.set_open(false)


func _force_dream_and_lock() -> void:
	WorldMode.set_mode(WorldMode.MODE_SUENO)
	WorldMode.set_locked(true)


func _unlock_switchables() -> void:
	WorldMode.set_locked(false)
