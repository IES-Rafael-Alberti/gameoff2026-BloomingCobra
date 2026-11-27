@tool
class_name PropDefinition
extends Resource

## Shared visual / collision data for room props.

@export var id: StringName = &""
@export var display_name: String = ""
@export var texture: Texture2D
@export var modulate: Color = Color.WHITE
@export var collision_size: Vector2 = Vector2(16, 16)
@export var z_index: int = 1
## Uniform scale applied to the sprite (HD sheets need ~0.15–0.2).
@export var sprite_scale: float = 1.0
## Tint used when texture is missing (editor / placeholder).
@export var placeholder_color: Color = Color(0.75, 0.75, 0.8, 1.0)


func apply_visual(sprite: Sprite2D, body: Node2D = null) -> void:
	if sprite == null:
		return
	# Scene-authored art (AtlasTexture / definitivo) wins over definition placeholders.
	var keep_scene_visual := sprite.texture != null
	if not keep_scene_visual:
		if texture != null:
			sprite.texture = texture
		else:
			sprite.texture = _make_placeholder_texture()
		sprite.modulate = modulate
		if sprite_scale > 0.0:
			sprite.scale = Vector2(sprite_scale, sprite_scale)
	if body != null:
		body.z_index = maxi(body.z_index, z_index)


func apply_collision_shape(shape_node: CollisionShape2D) -> void:
	if shape_node == null:
		return
	var rect := shape_node.shape as RectangleShape2D
	if rect == null:
		rect = RectangleShape2D.new()
		shape_node.shape = rect
	rect.size = collision_size


func _make_placeholder_texture() -> Texture2D:
	var img := Image.create(
		maxi(roundi(collision_size.x), 8),
		maxi(roundi(collision_size.y), 8),
		false,
		Image.FORMAT_RGBA8
	)
	img.fill(placeholder_color)
	# Dark border so placeholders read clearly on floors.
	var w := img.get_width()
	var h := img.get_height()
	var border := Color(0, 0, 0, 0.85)
	for x in w:
		img.set_pixel(x, 0, border)
		img.set_pixel(x, h - 1, border)
	for y in h:
		img.set_pixel(0, y, border)
		img.set_pixel(w - 1, y, border)
	return ImageTexture.create_from_image(img)
