extends Node

## Global dream/nightmare mode. Rooms sync lazily on enter; only the active room
## applies visuals/enemy mode when this changes.

signal mode_changed(index: int)
## remaining / duration after a successful player switch (HUD cooldown).
signal switch_cooldown_changed(remaining: float, duration: float)

const MODE_PESADILLA := 0
const MODE_SUENO := 1

var mode: int = MODE_PESADILLA
var locked: bool = false

## Seconds before the player can switch again after a toggle. Set from Game inspector.
var switch_cooldown: float = 1.5
var _cooldown_left: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _cooldown_left <= 0.0:
		return
	var before := _cooldown_left
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if not is_equal_approx(before, _cooldown_left):
		switch_cooldown_changed.emit(_cooldown_left, switch_cooldown)


func toggle() -> bool:
	if locked or _cooldown_left > 0.0:
		return false
	mode = MODE_SUENO if mode == MODE_PESADILLA else MODE_PESADILLA
	mode_changed.emit(mode)
	_start_cooldown()
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


func set_switch_cooldown(seconds: float) -> void:
	switch_cooldown = maxf(seconds, 0.0)


func get_switch_cooldown_remaining() -> float:
	return _cooldown_left


func get_switch_cooldown_duration() -> float:
	return switch_cooldown


## 1 = just switched (full shadow), 0 = ready.
func get_switch_cooldown_ratio() -> float:
	if switch_cooldown <= 0.0:
		return 0.0
	return clampf(_cooldown_left / switch_cooldown, 0.0, 1.0)


func is_switch_ready() -> bool:
	return not locked and _cooldown_left <= 0.0


func _start_cooldown() -> void:
	_cooldown_left = maxf(switch_cooldown, 0.0)
	switch_cooldown_changed.emit(_cooldown_left, switch_cooldown)
