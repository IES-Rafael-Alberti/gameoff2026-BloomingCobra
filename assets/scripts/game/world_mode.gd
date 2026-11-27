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

## Seconds before the player can switch again, depending on the destination mode.
## Set from Game inspector.
var switch_cooldown_to_vigilia: float = 1.5
var switch_cooldown_to_pesadilla: float = 1.5
var _cooldown_left: float = 0.0
var _cooldown_duration: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _cooldown_left <= 0.0:
		return
	var before := _cooldown_left
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if not is_equal_approx(before, _cooldown_left):
		switch_cooldown_changed.emit(_cooldown_left, _cooldown_duration)


func toggle() -> bool:
	if locked or _cooldown_left > 0.0:
		return false
	mode = MODE_SUENO if mode == MODE_PESADILLA else MODE_PESADILLA
	mode_changed.emit(mode)
	_start_cooldown(_cooldown_for(mode))
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


func set_switch_cooldowns(to_vigilia: float, to_pesadilla: float) -> void:
	switch_cooldown_to_vigilia = maxf(to_vigilia, 0.0)
	switch_cooldown_to_pesadilla = maxf(to_pesadilla, 0.0)


## Cooldown applied when switching into `target_mode`.
func _cooldown_for(target_mode: int) -> float:
	if target_mode == MODE_SUENO:
		return switch_cooldown_to_vigilia
	return switch_cooldown_to_pesadilla


func get_switch_cooldown_remaining() -> float:
	return _cooldown_left


func get_switch_cooldown_duration() -> float:
	return _cooldown_duration


## 1 = just switched (full shadow), 0 = ready.
func get_switch_cooldown_ratio() -> float:
	if _cooldown_duration <= 0.0:
		return 0.0
	return clampf(_cooldown_left / _cooldown_duration, 0.0, 1.0)


func is_switch_ready() -> bool:
	return not locked and _cooldown_left <= 0.0


func _start_cooldown(duration: float) -> void:
	_cooldown_duration = maxf(duration, 0.0)
	_cooldown_left = _cooldown_duration
	switch_cooldown_changed.emit(_cooldown_left, _cooldown_duration)
