extends Node2D

signal mode_changed(index: int)

const MODE_PESADILLA := 0
const MODE_SUENO := 1

@export var variants: Array[TileMap] = []
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
			if child is TileMap:
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


func _apply() -> void:
	if variants.is_empty():
		return
	for i in variants.size():
		var tilemap := variants[i]
		if tilemap == null:
			continue
		var on := i == _index
		tilemap.visible = on
		# Inactive mode tilemaps stay out of the render/process path.
		tilemap.process_mode = (
			Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		)
