extends SfxPlayer

## Cat: proximity ambient + global caught sting.

@export_group("Cat SFX")
@export var standard: AudioStream ## (P)
@export var caught: AudioStream ## (G)


func set_active(active: bool) -> void:
	if active:
		start_standard(standard)
	else:
		stop_standard()


func play_caught() -> void:
	stop_standard()
	play_global_detached(caught)
