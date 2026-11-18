extends Node2D

signal mode_changed(index: int)

const MODE_PESADILLA := 0
const MODE_SUENO := 1

## Mode roots (Pesadilla / Sueño). Put TileMapLayer(s) + mode-only props under each.
## If empty, auto-detects children named Pesadilla/Sueño (or direct tile layers).
@export var variants: Array[Node2D] = []
@export var start_index: int = 0
@export var mode_count: int = 2
## When true, mirrors WorldMode (player). Rooms/enemies sync via Room.sync_mode().
@export var follow_world: bool = false

var _index: int = 0
var _locked: bool = false


func _ready() -> void:
	add_to_group("switchable")
	if variants.is_empty():
		_auto_detect_variants()

	if follow_world:
		_index = WorldMode.mode
		if not WorldMode.mode_changed.is_connected(_on_world_mode_changed):
			WorldMode.mode_changed.connect(_on_world_mode_changed)
	else:
		var max_index := maxi(mode_count, variants.size()) - 1
		_index = clampi(start_index, 0, maxi(max_index, 0))

	_apply()
	mode_changed.emit(_index)


func _auto_detect_variants() -> void:
	var pes := get_node_or_null("Pesadilla") as Node2D
	var sue := get_node_or_null("Sueño") as Node2D
	if sue == null:
		sue = get_node_or_null("Sueno") as Node2D
	if pes != null or sue != null:
		if pes != null:
			variants.append(pes)
		if sue != null:
			variants.append(sue)
		return
	# Fallback: mode roots that are themselves tile layers.
	for child in get_children():
		if child is TileMapLayer or child is TileMap:
			variants.append(child as Node2D)


func toggle() -> void:
	if follow_world:
		WorldMode.toggle()
		return
	if _locked:
		return
	var count := maxi(mode_count, variants.size())
	if count < 2:
		return
	_index = (_index + 1) % count
	_apply()
	mode_changed.emit(_index)


func set_mode(index: int) -> void:
	if follow_world:
		WorldMode.set_mode(index)
		return
	var count := maxi(mode_count, variants.size())
	if count <= 0:
		return
	var next := clampi(index, 0, count - 1)
	if next == _index:
		_apply()
		return
	_index = next
	_apply()
	mode_changed.emit(_index)


func set_locked(locked: bool) -> void:
	if follow_world:
		WorldMode.set_locked(locked)
		return
	_locked = locked


func is_locked() -> bool:
	if follow_world:
		return WorldMode.is_locked()
	return _locked


func get_mode() -> int:
	if follow_world:
		return WorldMode.mode
	return _index


func get_mode_root(index: int = -1) -> Node2D:
	var i := _index if index < 0 else index
	if i < 0 or i >= variants.size():
		return null
	return variants[i]


func _on_world_mode_changed(index: int) -> void:
	if index == _index:
		_apply()
		return
	_index = index
	_apply()
	mode_changed.emit(_index)


func _apply() -> void:
	if variants.is_empty():
		return
	# Enable the active mode root before disabling others so the canvas never goes empty.
	var on_root: Node2D = null
	var off_roots: Array[Node2D] = []
	for i in variants.size():
		var root := variants[i]
		if root == null:
			continue
		if i == _index:
			on_root = root
		else:
			off_roots.append(root)

	if on_root != null:
		on_root.visible = true
		on_root.process_mode = Node.PROCESS_MODE_INHERIT
		_set_subtree_collisions(on_root, true)

	for root in off_roots:
		root.visible = false
		root.process_mode = Node.PROCESS_MODE_DISABLED
		# Rooms force DISABLE_MODE_KEEP_ACTIVE on props so walls stay solid while
		# paused — process_mode alone is not enough; disable shapes explicitly.
		_set_subtree_collisions(root, false)


func _set_subtree_collisions(node: Node, enabled: bool) -> void:
	if node is CollisionShape2D:
		(node as CollisionShape2D).set_deferred("disabled", not enabled)
	elif node is CollisionPolygon2D:
		(node as CollisionPolygon2D).set_deferred("disabled", not enabled)
	elif node is TileMapLayer:
		(node as TileMapLayer).collision_enabled = enabled
	elif node is TileMap:
		# Debug only. Disabling layers drops collision; bounds code re-enables briefly to measure.
		var tm := node as TileMap
		for i in tm.get_layers_count():
			tm.set_layer_enabled(i, enabled)

	for child in node.get_children():
		_set_subtree_collisions(child, enabled)
