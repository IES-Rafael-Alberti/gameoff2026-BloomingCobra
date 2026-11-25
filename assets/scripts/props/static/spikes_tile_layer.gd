class_name SpikesTileLayer
extends TileMapLayer

## Paint spike tiles from tileset_spikes_*.tres.
## Damages the player while standing on cells with custom data `spikes`.
## Physics layer on the tileset blocks enemies (layer 6).

const CUSTOM_SPIKES := &"spikes"
const LAYER_SPIKES_ENEMY := 1 << 5

@export var damage: int = 1
@export var damage_interval: float = 0.55

var _players_on: Dictionary = {} # Node2D -> true
var _tick_left: float = 0.0


func _ready() -> void:
	add_to_group("prop_spikes")
	z_index = maxi(z_index, 1)
	# Keep ticking even if a parent room briefly pauses.
	process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not visible or not is_visible_in_tree():
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
	for player in _players_on.keys():
		_damage_player(player)


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
		if _is_on_spikes(player.global_position):
			_players_on[player] = true
			if not previous.has(player):
				# Immediate tick on step-on.
				_damage_player(player)
				_tick_left = maxf(damage_interval, 0.05)


func _is_on_spikes(global_pos: Vector2) -> bool:
	var local := to_local(global_pos)
	var cell := local_to_map(local)
	var data := get_cell_tile_data(cell)
	if data == null:
		return false
	if data.get_custom_data(CUSTOM_SPIKES):
		return true
	# Fallback: any painted cell on this dedicated spikes layer counts.
	return get_cell_source_id(cell) != -1


func _damage_player(player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var dmg := player.get_node_or_null("Damageable")
	if dmg != null and dmg.has_method("take_damage"):
		dmg.take_damage(damage)
