class_name SfxCue
extends Resource

## Designer-facing id used by code: walk, attack, hurt, death, charge, sleep...
@export var id: StringName = &""
@export var stream: AudioStream
@export_range(-40.0, 6.0, 0.1) var volume_db: float = 0.0
## Random pitch jitter around 1.0 (0 = none).
@export_range(0.0, 0.5, 0.01) var pitch_variance: float = 0.0
## Minimum seconds between replays of this cue (useful for walk footsteps).
@export_range(0.0, 2.0, 0.01) var min_interval: float = 0.0
