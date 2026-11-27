class_name Boss
extends Node2D

## Orchestrates the three-part boss: phases, attack patterns, button, cat spawns.

signal weakpoint_broken(phase: int)
signal defeated

enum State { IDLE, FIGHTING, WEAKPOINT_EXPOSED, DEAD }

@export var total_phases: int = 3
@export var attack_cooldown: float = 2.6
@export var phase_cooldown_multipliers: PackedFloat32Array = PackedFloat32Array([1.0, 0.9, 0.8])
@export var button_scene: PackedScene = preload("res://assets/scenes/props/vigilia/interactive/buttonVigilia.tscn")
@export var button_only_in_vigilia: bool = true
## When false the room owns the weak-point button (boss room vigilia layouts) and
## calls trigger_weakpoint() on press, so the boss must not spawn its own.
@export var manage_button: bool = true

@export_group("Nightmare Cats")
@export var cat_scene: PackedScene = preload("res://assets/scenes/enemies/cat.tscn")
## Seconds between cat spawns while fighting in nightmare mode.
@export var cat_spawn_interval: float = 12.0
## Minimum wait after a cat is caught before another can appear.
@export var cat_respawn_delay: float = 10.0
@export var cat_spawn_margin: float = 32.0

@onready var head: BossHead = get_node_or_null("BossCabeza") as BossHead
@onready var left_hand: BossHand = get_node_or_null("BossManoIzquierda") as BossHand
@onready var right_hand: BossHand = get_node_or_null("BossManoDerecha") as BossHand
@onready var projectiles: Node2D = get_node_or_null("Projectiles") as Node2D

var _state: int = State.IDLE
var _phase: int = 0
var _attack_cd: float = 0.0
var _last_attack: StringName = &""
var _button: Area2D = null
var _button_slots: Array[Marker2D] = []
var _last_slot_index: int = -1
var _arena: Rect2 = Rect2()
var _overlap_chance: float = 0.0
var _cat_spawn_timer: float = 0.0


func _ready() -> void:
	if head != null:
		head.set_projectiles_parent(projectiles if projectiles != null else self)
		if not head.weakpoint_broken.is_connected(_on_weakpoint_broken):
			head.weakpoint_broken.connect(_on_weakpoint_broken)
	if not WorldMode.mode_changed.is_connected(_on_world_mode_changed):
		WorldMode.mode_changed.connect(_on_world_mode_changed)
	_set_parts_idle()


func _physics_process(delta: float) -> void:
	if _state != State.FIGHTING and _state != State.WEAKPOINT_EXPOSED:
		return
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	if _state == State.FIGHTING and _attack_cd <= 0.0:
		_schedule_attack()
	_tick_cat_spawn(delta)


func start_fight(arena: Rect2 = Rect2(), button_slots: Array = []) -> void:
	if _state == State.FIGHTING or _state == State.WEAKPOINT_EXPOSED:
		return
	_arena = arena
	_button_slots.clear()
	for slot in button_slots:
		if slot is Marker2D:
			_button_slots.append(slot as Marker2D)
	_apply_arena_to_parts()
	_phase = 0
	_overlap_chance = 0.0
	_state = State.FIGHTING
	_attack_cd = 1.4
	_cat_spawn_timer = maxf(cat_spawn_interval, 0.1)
	_ensure_button()
	_place_button()
	_sync_button_mode(WorldMode.get_mode())
	if head != null:
		head.hide_weakpoint()
		head.reset_weakpoint_hp()


func is_fighting() -> bool:
	return _state == State.FIGHTING or _state == State.WEAKPOINT_EXPOSED


## The layout button uses this so re-entering vigilia with an exposed weakpoint
## returns to nightmare without re-triggering (and without getting stuck).
func can_trigger_weakpoint() -> bool:
	return _state == State.FIGHTING


func get_phase() -> int:
	return _phase


func _apply_arena_to_parts() -> void:
	for part in [head, left_hand, right_hand]:
		if part != null:
			part.set_arena(_arena)
			part.set_home_position(part.global_position)


func _set_parts_idle() -> void:
	for part in [head, left_hand, right_hand]:
		if part != null:
			part.play_anim(&"Idle")


func _cooldown_for_phase() -> float:
	var mul := 1.0
	if _phase >= 0 and _phase < phase_cooldown_multipliers.size():
		mul = phase_cooldown_multipliers[_phase]
	return attack_cooldown * mul


func _schedule_attack() -> void:
	var choices := _attack_choices_for_phase()
	if choices.is_empty():
		_attack_cd = _cooldown_for_phase()
		return

	# Avoid repeating the last attack when possible.
	var filtered: Array[Dictionary] = []
	for c in choices:
		if StringName(c["id"]) != _last_attack:
			filtered.append(c)
	if filtered.is_empty():
		filtered = choices

	var pick := _weighted_pick(filtered)
	_last_attack = StringName(pick["id"])
	_attack_cd = _cooldown_for_phase()
	_run_attack(String(pick["id"]))

	# Phase 2+ can overlap a hand attack with a head attack.
	if _phase >= 1 and randf() < _overlap_chance:
		var hand_id := _pick_idle_hand_attack()
		if not hand_id.is_empty():
			_run_attack(hand_id)


func _attack_choices_for_phase() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Hands — swipe is the readable half-room sweep; slam is the shadow drop.
	if left_hand != null and not left_hand.is_busy():
		out.append({"id": "swipe_left", "w": 3.5})
		out.append({"id": "slam_left", "w": 2.2})
	if right_hand != null and not right_hand.is_busy():
		out.append({"id": "swipe_right", "w": 3.5})
		out.append({"id": "slam_right", "w": 2.2})
	# Head
	if head != null and not head.is_busy():
		out.append({"id": "laser_sweep", "w": 2.2})
		out.append({"id": "aoe", "w": 1.8})
		if _phase >= 1:
			out.append({"id": "laser_bounce", "w": 2.4})
	return out


func _weighted_pick(choices: Array[Dictionary]) -> Dictionary:
	var total := 0.0
	for c in choices:
		total += float(c.get("w", 1.0))
	var r := randf() * total
	var acc := 0.0
	for c in choices:
		acc += float(c.get("w", 1.0))
		if r <= acc:
			return c
	return choices[choices.size() - 1]


func _pick_idle_hand_attack() -> String:
	var opts: Array[String] = []
	if left_hand != null and not left_hand.is_busy():
		opts.append("swipe_left")
		opts.append("slam_left")
	if right_hand != null and not right_hand.is_busy():
		opts.append("swipe_right")
		opts.append("slam_right")
	if opts.is_empty():
		return ""
	return opts[randi() % opts.size()]


func _run_attack(attack_id: String) -> void:
	match attack_id:
		"swipe_left":
			if left_hand != null:
				left_hand.attack_swipe()
		"swipe_right":
			if right_hand != null:
				right_hand.attack_swipe()
		"slam_left":
			if left_hand != null:
				left_hand.attack_slam()
		"slam_right":
			if right_hand != null:
				right_hand.attack_slam()
		"laser_sweep":
			if head != null:
				head.attack_laser_sweep()
		"laser_bounce":
			if head != null:
				head.attack_laser_bounce()
		"aoe":
			if head != null:
				head.attack_aoe()
		_:
			pass


func _ensure_button() -> void:
	if not manage_button:
		return
	if _button != null and is_instance_valid(_button):
		return
	if button_scene == null:
		return
	_button = button_scene.instantiate() as Area2D
	if _button == null:
		return
	_button.name = "BossWeakButton"
	_button.z_index = 10
	_button.z_as_relative = false
	_button.add_to_group("boss_button")
	if "stay_pressed" in _button:
		_button.stay_pressed = true
	if "one_shot" in _button:
		_button.one_shot = true
	if "permanent_press" in _button:
		# Weak point resets every phase; do not make presses permanent across the run.
		_button.permanent_press = false
	add_child(_button)
	if _button.has_signal("pressed") and not _button.pressed.is_connected(_on_button_pressed):
		_button.pressed.connect(_on_button_pressed)


func _place_button() -> void:
	if _button == null or not is_instance_valid(_button):
		return
	var target := global_position
	if not _button_slots.is_empty():
		var idx := randi() % _button_slots.size()
		if _button_slots.size() > 1:
			while idx == _last_slot_index:
				idx = randi() % _button_slots.size()
		_last_slot_index = idx
		target = _button_slots[idx].global_position
	elif _arena.size != Vector2.ZERO:
		target = Vector2(
			randf_range(_arena.position.x + 24.0, _arena.end.x - 24.0),
			randf_range(_arena.position.y + 24.0, _arena.end.y - 24.0)
		)
	_button.global_position = target
	if _button.has_method("reset"):
		_button.reset()


func _on_button_pressed() -> void:
	trigger_weakpoint()


## Exposes the weak point. Used by the room-owned layout button.
func trigger_weakpoint() -> void:
	if _state != State.FIGHTING:
		return
	_state = State.WEAKPOINT_EXPOSED
	for part in [left_hand, right_hand, head]:
		if part != null:
			part.request_cancel()
	if head != null:
		head.reset_weakpoint_hp()
		await head.expose_weakpoint()


func _on_weakpoint_broken() -> void:
	if _state == State.DEAD:
		return
	_phase += 1
	weakpoint_broken.emit(_phase)
	# No heal drop on a phase break: the boss fight must not refill the player.
	if _phase >= total_phases:
		if head != null:
			head.hide_weakpoint()
		_die()
		return

	if head != null:
		await head.retreat_to_perch()
		head.reset_weakpoint_hp()
	_overlap_chance = 0.18 if _phase == 1 else 0.3
	_state = State.FIGHTING
	_attack_cd = _cooldown_for_phase() * 0.85
	_place_button()
	_sync_button_mode(WorldMode.get_mode())


## One cat at a time, only in nightmare. The timer pauses in vigilia so the
## delay after a catch is respected in active play time, not wall-clock time.
func _tick_cat_spawn(delta: float) -> void:
	if WorldMode.get_mode() != WorldMode.MODE_PESADILLA:
		return
	_cat_spawn_timer = maxf(_cat_spawn_timer - delta, 0.0)
	if _cat_spawn_timer > 0.0:
		return
	if _has_live_cat():
		# Check again shortly in case the existing cat is caught in the meantime.
		_cat_spawn_timer = 0.5
		return
	if _has_pending_cat_heal():
		# Don't queue another cat while its heal is still on the floor: otherwise
		# the player can stack heals by ignoring the drop and waiting out the timer.
		_cat_spawn_timer = maxf(_cat_spawn_timer, maxf(cat_respawn_delay, 0.0))
		return
	_spawn_cat()
	_cat_spawn_timer = maxf(cat_spawn_interval, 0.1)


func _has_live_cat() -> bool:
	if get_tree() == null:
		return false
	for cat in get_tree().get_nodes_in_group(&"cat"):
		if is_instance_valid(cat):
			return true
	return false


## True while a cat-heal pickup from a previous catch is still there uncollected.
func _has_pending_cat_heal() -> bool:
	if get_tree() == null:
		return false
	for pickup in get_tree().get_nodes_in_group(&"prop_pickup"):
		if not is_instance_valid(pickup) or not pickup.has_method("get_pickup_type"):
			continue
		if pickup.call("get_pickup_type") != &"cat_heal":
			continue
		if pickup.has_method("was_consumed") and bool(pickup.call("was_consumed")):
			continue
		return true
	return false


func _spawn_cat() -> void:
	if cat_scene == null:
		return
	var cat := cat_scene.instantiate()
	if cat == null or not (cat is Node2D):
		return
	# Boss-spawned cats are not registered by the room, so make them follow the
	# global mode directly (otherwise they would stay active in vigilia).
	var switchable := cat.get_node_or_null("Switchable")
	if switchable != null and "follow_world" in switchable:
		switchable.set("follow_world", true)
	if cat.has_signal(&"caught") and not cat.is_connected(&"caught", Callable(self, "_on_cat_caught")):
		cat.connect(&"caught", Callable(self, "_on_cat_caught"))
	var parent := get_parent()
	if parent == null:
		parent = self
	parent.add_child(cat)
	(cat as Node2D).global_position = _random_cat_spawn_point()


func _random_cat_spawn_point() -> Vector2:
	if _arena.size == Vector2.ZERO:
		return global_position + Vector2(randf_range(-64.0, 64.0), randf_range(-32.0, 32.0))
	var inner := _arena.grow(-minf(cat_spawn_margin, minf(_arena.size.x, _arena.size.y) * 0.25))
	if inner.size.x <= 1.0 or inner.size.y <= 1.0:
		inner = _arena
	return Vector2(
		randf_range(inner.position.x, inner.end.x),
		randf_range(inner.position.y, inner.end.y)
	)


func _on_cat_caught() -> void:
	_cat_spawn_timer = maxf(_cat_spawn_timer, maxf(cat_respawn_delay, 0.0))


func _on_world_mode_changed(index: int) -> void:
	_sync_button_mode(index)
	if _state == State.IDLE or _state == State.DEAD:
		return
	# Escaping the charge AoE by shifting should cancel it cleanly (no projectile tax).
	var cancelled_charge := false
	if head != null and head.has_method("is_charging_aoe") and head.is_charging_aoe():
		cancelled_charge = true
		if head.has_method("interrupt_charge"):
			head.interrupt_charge()
	elif head != null and head.has_method("interrupt_charge"):
		head.interrupt_charge()
	# Projectiles spawn when shifting into Vigilia, unless that shift cancelled the charge.
	if not cancelled_charge and index == WorldMode.MODE_SUENO and head != null:
		head.fire_shift_burst()


func _sync_button_mode(mode: int) -> void:
	if _button == null or not is_instance_valid(_button):
		return
	if not button_only_in_vigilia:
		_button.visible = true
		_button.set_deferred("monitoring", true)
		return
	var in_vigilia := mode == WorldMode.MODE_SUENO
	_button.visible = in_vigilia
	_button.set_deferred("monitoring", in_vigilia)
	for child in _button.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred("disabled", not in_vigilia)


func _die() -> void:
	_state = State.DEAD
	if _button != null and is_instance_valid(_button):
		_button.queue_free()
		_button = null
	if head != null:
		head.hide_weakpoint()
	for part in [head, left_hand, right_hand]:
		if part == null:
			continue
		var tween := create_tween()
		tween.tween_property(part, "modulate:a", 0.0, 0.7)
	if is_inside_tree() and get_tree() != null:
		await get_tree().create_timer(0.75).timeout
	defeated.emit()
	queue_free()
