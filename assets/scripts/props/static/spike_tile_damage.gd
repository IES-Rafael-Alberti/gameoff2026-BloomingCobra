class_name SpikeTileDamage
extends Node

## Child helper: damages the player while overlapping spike cells on the
## parent TileMapLayer. Room installs this automatically on spike tilesets.

const CUSTOM_SPIKES := &"spikes"

@export var damage: int = 1
@export var damage_interval: float = 0.55

var _layer: TileMapLayer
var _players_on: Dictionary = {}
var _tick_left: float = 0.0


func _ready() -> void:
	_layer = get_parent() as TileMapLayer
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _layer == null or not is_instance_valid(_layer):
		return
	if not _is_damage_active():
		_players_on.clear()
		_tick_left = 0.0
		return

	_refresh_players_on_spikes()
	if _players_on.is_empty():
		_tick_left = 0.0
		return

	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = maxf(damage_interval, 0.05)
	for player: Node2D in _players_on.keys():
		_damage_player(player)


func _is_damage_active() -> bool:
	if not _layer.visible or not _layer.is_visible_in_tree():
		return false
	if not _layer.can_process():
		return false
	var room := _find_room()
	if room != null and room.has_method("is_active") and not bool(room.call("is_active")):
		return false
	return true


func _find_room() -> Node:
	var n: Node = _layer
	while n != null:
		if n.is_in_group("rooms"):
			return n
		n = n.get_parent()
	return null


func _refresh_players_on_spikes() -> void:
	var previous := _players_on.duplicate()
	_players_on.clear()
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("player"):
		var player := node as Node2D
		if player == null or not is_instance_valid(player):
			continue
		if not _overlaps_player(player):
			continue
		_players_on[player] = true
		if not previous.has(player):
			_damage_player(player)
			_tick_left = maxf(damage_interval, 0.05)


func _overlaps_player(player: Node2D) -> bool:
	var prect := _player_rect(player)
	var ts := _layer.tile_set
	if ts == null:
		return false
	# Honour TileMapLayer scale (rooms often use 0.3 on 128px tiles).
	var cell_size := Vector2(ts.tile_size) * _layer.global_scale.abs()
	if cell_size.x <= 0.0 or cell_size.y <= 0.0:
		return false
	for cell in _layer.get_used_cells():
		if not _cell_is_spike(cell):
			continue
		var center := _layer.to_global(_layer.map_to_local(cell))
		var srect := Rect2(center - cell_size * 0.5, cell_size)
		if srect.intersects(prect):
			return true
	return false


func _cell_is_spike(cell: Vector2i) -> bool:
	var data := _layer.get_cell_tile_data(cell)
	if data != null and data.get_custom_data(CUSTOM_SPIKES):
		return true
	# Dedicated spike tilesets flag every painted cell.
	return _tileset_is_dedicated_spikes(_layer.tile_set) and _layer.get_cell_source_id(cell) != -1


static func tileset_has_spikes(ts: TileSet) -> bool:
	if ts == null:
		return false
	if _tileset_is_dedicated_spikes(ts):
		return true
	for i in ts.get_custom_data_layers_count():
		if ts.get_custom_data_layer_name(i) == CUSTOM_SPIKES:
			return true
	return false


static func _tileset_is_dedicated_spikes(ts: TileSet) -> bool:
	if ts == null:
		return false
	var path := ts.resource_path
	return path.ends_with("tileset_spikes_pesadilla.tres") or path.ends_with("tileset_spikes_vigilia.tres")


func _player_rect(player: Node2D) -> Rect2:
	var cs := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var size := (cs.shape as RectangleShape2D).size * cs.global_scale.abs()
		var center := cs.global_position
		return Rect2(center - size * 0.5, size)
	return Rect2(player.global_position - Vector2(6, 6), Vector2(12, 12))


func _damage_player(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var dmg := player.get_node_or_null("Damageable")
	if dmg != null and dmg.has_method("take_damage"):
		dmg.take_damage(damage)
