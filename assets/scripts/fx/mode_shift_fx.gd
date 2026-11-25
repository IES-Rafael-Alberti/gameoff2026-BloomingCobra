extends CanvasLayer
class_name ModeShiftFX

## Full-screen radial ripple on every dream / nightmare shift.
## Lives on canvas layer 50, below the HUD layers (60 / 80 / 100), so the
## world warps but menus, health bar and map stay perfectly still.
## A BackBufferCopy captures the frame before the overlay samples it.

const SHADER: Shader = preload("res://assets/shaders/mode_shift_wave.gdshader")
const FX_LAYER := 50
## Set to true temporarily to confirm in the Output panel that switches fire.
const DEBUG := false

@export_range(0.2, 2.0, 0.01) var duration: float = 0.8
@export_range(0.0, 1.0, 0.01) var intensity: float = 1.0
@export var dream_color: Color = Color(0.35, 0.85, 1.0)
@export var nightmare_color: Color = Color(1.0, 0.25, 0.45)

var _overlay: ColorRect
var _material: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	layer = FX_LAYER
	_setup()


func _setup() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return

	var screen_copy := BackBufferCopy.new()
	screen_copy.name = "ScreenCopy"
	screen_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(screen_copy)
	screen_copy.visible = true

	_material = ShaderMaterial.new()
	_material.shader = SHADER

	_overlay = ColorRect.new()
	_overlay.name = "WaveOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.material = _material
	_overlay.visible = false
	add_child(_overlay)

	if WorldMode != null and not WorldMode.mode_changed.is_connected(_on_mode_changed):
		WorldMode.mode_changed.connect(_on_mode_changed)


func _on_mode_changed(mode: int) -> void:
	play(mode)


func play(mode: int = -1) -> void:
	_setup()
	if _overlay == null or _material == null:
		return
	if DEBUG:
		print("[ModeShiftFX] play mode=", mode, " center=", _player_screen_uv())

	var tint := nightmare_color if mode == WorldMode.MODE_PESADILLA else dream_color
	_material.set_shader_parameter("center", _player_screen_uv())
	_material.set_shader_parameter("aspect", _viewport_aspect())
	_material.set_shader_parameter("wave_color", tint)
	_material.set_shader_parameter("intensity", intensity)
	_material.set_shader_parameter("progress", 0.0)

	_overlay.visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# tween_method avoids relying on ShaderMaterial's virtual property path.
	_tween.tween_method(_set_progress, 0.0, 1.0, maxf(duration, 0.05))
	_tween.tween_callback(_hide_overlay)


func _set_progress(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter("progress", value)


func _hide_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.visible = false


func _player_screen_uv() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as CanvasItem
	if player == null or not is_instance_valid(player):
		return Vector2(0.5, 0.5)
	var size := _viewport_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector2(0.5, 0.5)
	# Includes the active Camera2D transform, so it works with zoom / follow.
	var screen_pos := player.get_global_transform_with_canvas().origin
	return (screen_pos / size).clamp(Vector2.ZERO, Vector2.ONE)


func _viewport_size() -> Vector2:
	# CanvasLayer is a Node, not a CanvasItem: get_viewport_rect() is not
	# available here in Godot 4.7, so go through the Viewport explicitly.
	var viewport := get_viewport()
	if viewport == null:
		return Vector2.ZERO
	return viewport.get_visible_rect().size


func _viewport_aspect() -> float:
	var size := _viewport_size()
	return size.x / maxf(size.y, 1.0)
