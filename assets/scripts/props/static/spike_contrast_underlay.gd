class_name SpikeContrastUnderlay
extends Node2D

## Dark halo painted under spike tiles so they read clearly against the floor.
## BossRoom installs this sibling just before each spike TileMapLayer; no other
## room gets it. Cell padding is neighbour-aware so overlapping cells never
## double-darken the seams.

var _layer: TileMapLayer
var _cells: Dictionary = {}
var _cell_size: Vector2 = Vector2.ZERO
var _padding: float = 14.0
var _alpha: float = 0.10


func setup(layer: TileMapLayer, padding: float, alpha: float) -> void:
	_layer = layer
	_padding = maxf(padding, 0.0)
	_alpha = clampf(alpha, 0.0, 1.0)
	_cells.clear()
	if _layer == null or _layer.tile_set == null:
		queue_redraw()
		return
	_cell_size = Vector2(_layer.tile_set.tile_size)
	for cell in _layer.get_used_cells():
		_cells[cell] = true
	# Draw in the same local space as the tile layer (its scale/offset included).
	transform = _layer.transform
	z_index = _layer.z_index
	z_as_relative = _layer.z_as_relative
	queue_redraw()


func _draw() -> void:
	if _layer == null or not is_instance_valid(_layer) or _cells.is_empty():
		return
	# Two soft steps: a wide faint halo and a tighter darker core. Both expand
	# only into empty neighbouring cells, so contiguous spike rows stay even.
	_draw_pass(_padding, Color(0.0, 0.0, 0.0, _alpha * 0.35))
	_draw_pass(_padding * 0.35, Color(0.0, 0.0, 0.0, _alpha))


func _draw_pass(padding: float, color: Color) -> void:
	for cell in _cells.keys():
		draw_rect(_cell_rect(cell, padding), color, true)


func _cell_rect(cell: Vector2i, padding: float) -> Rect2:
	var center := _layer.map_to_local(cell)
	var half := _cell_size * 0.5
	var left := padding if not _cells.has(cell + Vector2i(-1, 0)) else 0.0
	var right := padding if not _cells.has(cell + Vector2i(1, 0)) else 0.0
	var top := padding if not _cells.has(cell + Vector2i(0, -1)) else 0.0
	var bottom := padding if not _cells.has(cell + Vector2i(0, 1)) else 0.0
	return Rect2(
		center.x - half.x - left,
		center.y - half.y - top,
		_cell_size.x + left + right,
		_cell_size.y + top + bottom
	)
