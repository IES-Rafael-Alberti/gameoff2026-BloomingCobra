extends RefCounted

## Softens analog-stick menu spam: one step on press, then slow repeat while held.

const FIRST_REPEAT := 0.32
const REPEAT := 0.14

var _cooldown: float = 0.0
var _held: Vector2i = Vector2i.ZERO


func update(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


## Returns a cardinal step (-1/0/1 on x or y) when navigation should fire, else ZERO.
func poll_step() -> Vector2i:
	var dir := _read_dir()
	if dir == Vector2i.ZERO:
		_held = Vector2i.ZERO
		_cooldown = 0.0
		return Vector2i.ZERO

	if dir != _held:
		_held = dir
		_cooldown = FIRST_REPEAT
		return dir

	if _cooldown <= 0.0:
		_cooldown = REPEAT
		return dir

	return Vector2i.ZERO


func reset() -> void:
	_held = Vector2i.ZERO
	_cooldown = 0.0


func _read_dir() -> Vector2i:
	var x := 0
	var y := 0
	if Input.is_action_pressed(&"ui_left") or Input.is_action_pressed(&"move_left"):
		x -= 1
	if Input.is_action_pressed(&"ui_right") or Input.is_action_pressed(&"move_right"):
		x += 1
	if Input.is_action_pressed(&"ui_up") or Input.is_action_pressed(&"move_up"):
		y -= 1
	if Input.is_action_pressed(&"ui_down") or Input.is_action_pressed(&"move_down"):
		y += 1

	# Prefer the dominant axis so diagonals don't chatter both axes.
	if x != 0 and y != 0:
		var stick := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if absf(stick.x) >= absf(stick.y):
			y = 0
		else:
			x = 0

	return Vector2i(x, y)
