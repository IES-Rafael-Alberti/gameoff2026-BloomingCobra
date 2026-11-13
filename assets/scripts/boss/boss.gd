class_name Boss
extends Node2D

## Orchestrates the three-part boss: phases, attack patterns, button, heal drops.

signal weakpoint_broken(phase: int)
signal defeated

enum State { IDLE, FIGHTING, WEAKPOINT_EXPOSED, DEAD }

@export var total_phases: int = 3
@export var attack_cooldown: float = 1.6
@export var phase_cooldown_multipliers: PackedFloat32Array = PackedFloat32Array([1.0, 0.8, 0.65])
@export var heal_drop_scene: PackedScene = preload("res://assets/scenes/props/pickups/pickup_heal.tscn")
@export var button_scene: PackedScene = preload("res://assets/scenes/props/interactive/button.tscn")
@export var button_only_in_vigilia: bool = true

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
	_attack_cd = 0.8
	_ensure_button()
	_place_button()
	_sync_button_mode(WorldMode.get_mode())
	if head != null:
		head.hide_weakpoint()
		head.reset_weakpoint_hp()


func is_fighting() -> bool:
	return _state == State.FIGHTING or _state == State.WEAKPOINT_EXPOSED


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
	# Hands
	if left_hand != null and not left_hand.is_busy():
		out.append({"id": "swipe_left", "w": 3.0})
		out.append({"id": "slam_left", "w": 2.0})
	if right_hand != null and not right_hand.is_busy():
		out.append({"id": "swipe_right", "w": 3.0})
		out.append({"id": "slam_right", "w": 2.0})
	# Head
	if head != null and not head.is_busy():
		out.append({"id": "laser_sweep", "w": 2.5})
		out.append({"id": "aoe", "w": 2.0})
		if _phase >= 1:
			out.append({"id": "laser_bounce", "w": 2.0})
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
	if _button != null and is_instance_valid(_button):
		return
	if button_scene == null:
		return
	_button = button_scene.instantiate() as Area2D
	if _button == null:
		return
	_button.name = "BossWeakButton"
	if "stay_pressed" in _button:
		_button.stay_pressed = true
	if "one_shot" in _button:
		_button.one_shot = true
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
	if _state != State.FIGHTING:
		return
	_state = State.WEAKPOINT_EXPOSED
	if head != null:
		head.reset_weakpoint_hp()
		head.expose_weakpoint()


func _on_weakpoint_broken() -> void:
	if _state == State.DEAD:
		return
	_phase += 1
	weakpoint_broken.emit(_phase)
	_spawn_heal_drop()
	if _phase >= total_phases:
		_die()
		return

	_overlap_chance = 0.35 if _phase == 1 else 0.55
	_state = State.FIGHTING
	_attack_cd = _cooldown_for_phase() * 0.6
	if head != null:
		head.hide_weakpoint()
		head.reset_weakpoint_hp()
	_place_button()
	_sync_button_mode(WorldMode.get_mode())


func _spawn_heal_drop() -> void:
	if heal_drop_scene == null:
		return
	var drop := heal_drop_scene.instantiate()
	var parent := get_parent()
	if parent == null:
		parent = self
	parent.add_child(drop)
	var pos := global_position
	if head != null:
		pos = head.global_position + Vector2(0, 36)
	elif _arena.size != Vector2.ZERO:
		pos = _arena.get_center()
	if drop is Node2D:
		(drop as Node2D).global_position = pos


func _on_world_mode_changed(index: int) -> void:
	_sync_button_mode(index)
	if _state == State.IDLE or _state == State.DEAD:
		return
	# Projectiles spawn when shifting into Vigilia.
	if index == WorldMode.MODE_SUENO and head != null:
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
