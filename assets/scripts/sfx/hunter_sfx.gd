extends SfxPlayer

## Hunter: walking is room-global; standard ambient is proximity (optional).

@export_group("Hunter SFX")
@export var walking: AudioStream ## (G) while moving
@export var standard: AudioStream ## (P) ambient loop — leave empty to disable
@export_range(0.05, 2.0, 0.01) var walking_interval: float = 0.35


func set_active(active: bool) -> void:
	if active:
		start_standard(standard)
	else:
		stop_standard()


func play_walking() -> void:
	play_global(walking, &"walking", walking_interval)
