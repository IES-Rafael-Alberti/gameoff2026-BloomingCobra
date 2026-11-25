class_name SpikesTileLayer
extends TileMapLayer

## Optional script on a spike TileMapLayer. Prefer Room auto-install of
## SpikeTileDamage — this script just ensures the helper exists.

const _SPIKE_DAMAGE_SCRIPT: Script = preload("res://assets/scripts/props/static/spike_tile_damage.gd")

func _ready() -> void:
	add_to_group("prop_spikes")
	z_index = maxi(z_index, 1)
	_ensure_damage_helper()


func _ensure_damage_helper() -> void:
	if get_node_or_null("SpikeTileDamage") != null:
		return
	var helper: Node = _SPIKE_DAMAGE_SCRIPT.new()
	helper.name = "SpikeTileDamage"
	add_child(helper)
