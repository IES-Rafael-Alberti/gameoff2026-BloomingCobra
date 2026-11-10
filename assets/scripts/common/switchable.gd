extends Node2D

signal mode_changed(index: int)

const MODE_PESADILLA := 0
const MODE_SUENO := 1

@export var variants: Array[TileMap] = []
@export var start_index: int = 0
@export var mode_count: int = 2

var _index: int = 0
var _locked: bool = false


func _ready() -> void:
	add_to_group("switchable")
	if variants.is_empty():
		for child in get_children():
			if child is TileMap:
				variants.append(child)
	var max_index := maxi(mode_count, variants.size()) - 1
	_index = clampi(start_index, 0, maxi(max_index, 0))
	_apply()
	mode_changed.emit(_index)


func toggle() -> void:
	if _locked:
		return
	var count := maxi(mode_count, variants.size())
	if count < 2:
		return
	_index = (_index + 1) % count
	_apply()
	mode_changed.emit(_index)


func set_mode(index: int) -> void:
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
	_locked = locked


func is_locked() -> bool:
	return _locked


func get_mode() -> int:
	return _index


func _apply() -> void:
	if variants.is_empty():
		return
	for i in variants.size():
		variants[i].visible = i == _index
