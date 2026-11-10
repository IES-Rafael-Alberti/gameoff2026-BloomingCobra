class_name EnemySpawnPoint
extends Marker2D

## Designer-placed spawn: pick an enemy type or assign a custom PackedScene.

enum EnemyType {
	FROM_MARKER,
	HUNTER,
	RANGER,
	ROAMER,
	BOUNCER,
	ELITE,
	DIVIDER,
}

const TYPE_SCENES := {
	EnemyType.HUNTER: "res://assets/scenes/enemies/enemy.tscn",
	EnemyType.RANGER: "res://assets/scenes/enemies/enemy_2.tscn",
	EnemyType.ROAMER: "res://assets/scenes/enemies/enemy_3.tscn",
	EnemyType.BOUNCER: "res://assets/scenes/enemies/enemy_4.tscn",
	EnemyType.ELITE: "res://assets/scenes/enemies/elite.tscn",
	EnemyType.DIVIDER: "res://assets/scenes/enemies/divider_1.tscn",
}

@export var enemy_type: EnemyType = EnemyType.FROM_MARKER:
	set(value):
		enemy_type = value
		_sync_scene_from_type()

@export var enemy_scene: PackedScene
@export var respawn_on_reenter: bool = false

var _instance: Node = null


func _ready() -> void:
	_sync_scene_from_type()


func apply_enemy_type(type: int) -> void:
	if type == EnemyType.FROM_MARKER:
		return
	enemy_type = type as EnemyType


func set_enemy_scene_override(packed: PackedScene) -> void:
	if packed == null:
		return
	# Keep FROM_MARKER so spawn() does not replace this with a typed preset.
	enemy_type = EnemyType.FROM_MARKER
	enemy_scene = packed


func spawn(parent: Node) -> Node:
	_sync_scene_from_type()
	if enemy_scene == null or parent == null:
		return null
	if is_instance_valid(_instance) and not respawn_on_reenter:
		return _instance
	if is_instance_valid(_instance) and respawn_on_reenter:
		_instance.queue_free()
		_instance = null

	_instance = enemy_scene.instantiate()
	parent.add_child(_instance)
	if _instance is Node2D:
		(_instance as Node2D).global_position = global_position
	return _instance


func get_instance() -> Node:
	if is_instance_valid(_instance):
		return _instance
	return null


func clear_instance() -> void:
	if is_instance_valid(_instance):
		_instance.queue_free()
	_instance = null


static func scene_for(type: int) -> PackedScene:
	if type == EnemyType.FROM_MARKER:
		return null
	var path: String = TYPE_SCENES.get(type, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene


func _sync_scene_from_type() -> void:
	var packed := scene_for(enemy_type)
	if packed != null:
		enemy_scene = packed
