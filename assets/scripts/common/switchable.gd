extends Node2D

signal mode_changed(index: int)

const MODE_PESADILLA := 0
const MODE_SUENO := 1

## TileMap or TileMapLayer children used as mode variants.
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
		for child in get_children():
			if _is_tile_variant(child):
				variants.append(child)

	if follow_world:
		_index = WorldMode.mode
		if not WorldMode.mode_changed.is_connected(_on_world_mode_changed):
			WorldMode.mode_changed.connect(_on_world_mode_changed)
	else:
		var max_index := maxi(mode_count, variants.size()) - 1
		_index = clampi(start_index, 0, maxi(max_index, 0))

	_apply()
	mode_changed.emit(_index)


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


func _on_world_mode_changed(index: int) -> void:
	if index == _index:
		_apply()
		return
	_index = index
	_apply()
	mode_changed.emit(_index)


func _is_tile_variant(node: Node) -> bool:
	return node is TileMap or node is TileMapLayer


func _apply() -> void:
	if variants.is_empty():
		return
	# Enable the new map before disabling the old one so the canvas never goes empty.
	var on_map: Node2D = null
	var off_maps: Array[Node2D] = []
	for i in variants.size():
		var tilemap := variants[i]
		if tilemap == null or not _is_tile_variant(tilemap):
			continue
		if i == _index:
			on_map = tilemap
		else:
			off_maps.append(tilemap)

	if on_map != null:
		on_map.visible = true
		on_map.process_mode = Node.PROCESS_MODE_INHERIT

	for tilemap in off_maps:
		tilemap.visible = false
		tilemap.process_mode = Node.PROCESS_MODE_DISABLED
