extends SfxPlayer

## Elite: proximity ambient loop only.

@export_group("Elite SFX")
@export var standard: AudioStream ## (P)


func set_active(active: bool) -> void:
	if active:
		start_standard(standard)
	else:
		stop_standard()
