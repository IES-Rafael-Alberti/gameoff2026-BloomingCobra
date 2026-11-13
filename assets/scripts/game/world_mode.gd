extends Node

## Global dream/nightmare mode. Rooms sync lazily on enter; only the active room
## applies visuals/enemy mode when this changes.

signal mode_changed(index: int)

const MODE_PESADILLA := 0
const MODE_SUENO := 1

var mode: int = MODE_PESADILLA
var locked: bool = false


func toggle() -> bool:
	if locked:
		return false
	mode = MODE_SUENO if mode == MODE_PESADILLA else MODE_PESADILLA
	mode_changed.emit(mode)
	return true


func set_mode(index: int) -> void:
	var next := clampi(index, MODE_PESADILLA, MODE_SUENO)
	if next == mode:
		return
	mode = next
	mode_changed.emit(mode)


func set_locked(value: bool) -> void:
	locked = value


func is_locked() -> bool:
	return locked


func get_mode() -> int:
	return mode
