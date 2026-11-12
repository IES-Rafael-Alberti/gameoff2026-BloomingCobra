extends SfxPlayer

## Duplicator: proximity ambient + global duplication when it splits.

@export_group("Duplicator SFX")
@export var standard: AudioStream ## (P)
@export var duplication: AudioStream ## (G) on split / spawn copies


func set_active(active: bool) -> void:
	if active:
		start_standard(standard)
	else:
		stop_standard()


func play_duplication() -> void:
	# Detached so it keeps playing after this enemy is freed.
	play_global_detached(duplication)
