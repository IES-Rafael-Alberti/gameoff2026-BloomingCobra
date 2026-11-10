extends Node

## Hunter brain: idle → aggressive (chase / melee).

@export var speed: float = 55.0
@export var attack_range: float = 28.0
@export var attack_cooldown: float = 0.8

var detection_radius: float = 110.0
var aggro_delay: float = 0.0

var _enemy: CharacterBody2D
var _active: bool = true
var _state_name: StringName = &""
var _states: Dictionary = {}


func setup(enemy: CharacterBody2D) -> void:
	_enemy = enemy
	# Solid vs walls/doors/other hunters; no solid push vs player (hurtbox handles contact).
	_enemy.collision_layer = 1 << 2 # enemy
	# world + enemy + door_enemy + spikes_enemy
	_enemy.collision_mask = (1 << 0) | (1 << 2) | (1 << 3) | (1 << 5)
	_setup_states()
	change_state(&"idle")


func set_active(active: bool) -> void:
	_active = active
	if not _active and _enemy != null:
		_enemy.velocity = Vector2.ZERO


func physics_update(delta: float) -> void:
	if not _active or _enemy == null:
		return
	var state: Node = _states.get(_state_name) as Node
	if state != null and state.has_method("physics_update"):
		state.physics_update(delta)


func change_state(next: StringName) -> void:
	if next == _state_name:
		return
	var current: Node = _states.get(_state_name) as Node
	if current != null and current.has_method("exit"):
		current.exit(next)
	var previous := _state_name
	_state_name = next
	var state: Node = _states.get(_state_name) as Node
	if state != null and state.has_method("enter"):
		state.enter(previous)


func get_enemy() -> CharacterBody2D:
	return _enemy


func get_player() -> Node2D:
	if _enemy == null:
		return null
	return _enemy.get_tree().get_first_node_in_group("player") as Node2D


func _setup_states() -> void:
	_register_state(&"idle", "Idle")
	_register_state(&"aggressive", "Aggresive")


func _register_state(key: StringName, path: String) -> void:
	var node := get_node_or_null(path)
	if node == null:
		push_warning("Hunter missing state node: %s" % path)
		return
	if node.has_method("setup"):
		node.setup(self)
	_states[key] = node
