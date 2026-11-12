extends CanvasLayer

## Continuous vigil life bar (empty under / full progress). Follows vitality ratio
## smoothly so the fill never jumps in discrete chunks.

@export var empty_texture: Texture2D
@export var full_texture: Texture2D
@export var bar_scale: float = 3.0
## Higher = snappier visual follow. Drain is already continuous; this softens heals.
@export var follow_speed: float = 14.0

@onready var _bar: TextureProgressBar = $Margin/Bar

var _target_ratio: float = 1.0
var _shown_ratio: float = 1.0
var _vitality: Node = null


func _ready() -> void:
	layer = 60
	_configure_bar()
	call_deferred("_bind_player_vitality")


func _process(delta: float) -> void:
	if _vitality != null and _vitality.has_method("get_ratio"):
		_target_ratio = float(_vitality.call("get_ratio"))
	# Exponential ease — continuous drain looks natural; heals ease in.
	var t := 1.0 - exp(-follow_speed * delta)
	_shown_ratio = lerpf(_shown_ratio, _target_ratio, t)
	_bar.value = _shown_ratio


func _configure_bar() -> void:
	if empty_texture != null:
		_bar.texture_under = empty_texture
	if full_texture != null:
		_bar.texture_progress = full_texture
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.value = 1.0
	_bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_bar.nine_patch_stretch = false
	_bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_size := Vector2(64, 16)
	if full_texture != null:
		tex_size = Vector2(full_texture.get_width(), full_texture.get_height())
	elif empty_texture != null:
		tex_size = Vector2(empty_texture.get_width(), empty_texture.get_height())
	_bar.custom_minimum_size = tex_size * bar_scale
	_bar.size = _bar.custom_minimum_size


func _bind_player_vitality() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var vit: Node = player.get_node_or_null("Vitality")
	if vit == null and player.has_method("get_vitality"):
		vit = player.call("get_vitality") as Node
	if vit == null:
		return
	_vitality = vit
	if vit.has_signal("vitality_changed") and not vit.vitality_changed.is_connected(_on_vitality_changed):
		vit.vitality_changed.connect(_on_vitality_changed)
	if vit.has_method("get_ratio"):
		_target_ratio = float(vit.call("get_ratio"))
		_shown_ratio = _target_ratio
		_bar.value = _shown_ratio


func _on_vitality_changed(_current: float, _max_vitality: float, ratio: float) -> void:
	_target_ratio = clampf(ratio, 0.0, 1.0)
