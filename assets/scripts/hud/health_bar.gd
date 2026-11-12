extends CanvasLayer

## Body (empty bar + clouds) stays fixed. Only the dark tube fills with red.

const BODY_SIZE := Vector2(383, 162)
## Dark tube inside the body — clouds are decoration, not part of the fill range.
const FILL_ORIGIN := Vector2(27, 65)
const FILL_SIZE := Vector2(274, 56)
const EYE_CELL := Vector2i(427, 427)
const EYE_FRAME_COUNT := 4

@export var body_texture: Texture2D
@export var fill_texture: Texture2D
@export var eye_sheet: Texture2D
@export var bar_scale: float = 0.55
@export var eye_scale: float = 0.28

@onready var _eye: TextureRect = $Margin/Row/Eye
@onready var _root: Control = $Margin/Row/BarRoot
@onready var _body: TextureRect = $Margin/Row/BarRoot/Body
@onready var _fill: TextureProgressBar = $Margin/Row/BarRoot/Fill

var _vitality: Node = null
var _eye_frames: Array[AtlasTexture] = []
var _eye_index: int = -1


func _ready() -> void:
	layer = 60
	_configure_visuals()
	call_deferred("_bind_player_vitality")


func _process(_delta: float) -> void:
	if _vitality != null and _vitality.has_method("get_ratio"):
		_set_ratio(float(_vitality.call("get_ratio")))


func _configure_visuals() -> void:
	var s := bar_scale
	_root.custom_minimum_size = BODY_SIZE * s
	_root.size = BODY_SIZE * s
	_root.clip_contents = false

	_body.texture = body_texture
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_body.stretch_mode = TextureRect.STRETCH_SCALE
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.position = Vector2.ZERO
	_body.size = BODY_SIZE
	_body.scale = Vector2(s, s)
	_body.z_index = 0

	_fill.min_value = 0.0
	_fill.max_value = 1.0
	_fill.step = 0.0
	_fill.value = 1.0
	_fill.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	_fill.nine_patch_stretch = false
	_fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fill.texture_under = null
	_fill.texture_over = null
	_fill.texture_progress = fill_texture
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Native tube pixels, then same scale as body — 0%..100% = tube only.
	_fill.position = FILL_ORIGIN * s
	_fill.size = FILL_SIZE
	_fill.scale = Vector2(s, s)
	_fill.z_index = 1

	_eye_frames.clear()
	if eye_sheet != null:
		for i in EYE_FRAME_COUNT:
			_eye_frames.append(_atlas(eye_sheet, Rect2(i * EYE_CELL.x, 0, EYE_CELL.x, EYE_CELL.y)))
	_eye.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var eye_size := Vector2(EYE_CELL) * eye_scale
	_eye.custom_minimum_size = eye_size
	_eye.size = eye_size

	_set_ratio(1.0)


func _atlas(sheet: Texture2D, region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = region
	return atlas


func _set_ratio(ratio: float) -> void:
	var r := clampf(ratio, 0.0, 1.0)
	_fill.value = r
	_update_eye(r)


func _update_eye(ratio: float) -> void:
	if _eye_frames.is_empty():
		return
	var n := _eye_frames.size()
	var idx := clampi(int(round(clampf(ratio, 0.0, 1.0) * float(n - 1))), 0, n - 1)
	if idx == _eye_index:
		return
	_eye_index = idx
	_eye.texture = _eye_frames[idx]


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
		_set_ratio(float(vit.call("get_ratio")))


func _on_vitality_changed(_current: float, _max_vitality: float, ratio: float) -> void:
	_set_ratio(ratio)
