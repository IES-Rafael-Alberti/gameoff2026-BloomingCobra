extends CharacterBody2D

const SPEED := 75.0

## Scale used by walk / attack / hurt pixel sheets.
const PIXEL_SPRITE_SCALE := 1.1
## Walk frame + opaque content (used to size HD idle).
const WALK_FRAME_SIZE := Vector2(32, 39)
const WALK_CONTENT_RECT := Rect2(7, 3, 17, 23)
## Idle HD frame + opaque content inside each 992 cell.
const IDLE_FRAME_SIZE := Vector2(992, 992)
const IDLE_CONTENT_RECT := Rect2(245, 153, 509, 720)

@export var dream_acceleration: float = 220.0
@export var dream_max_speed: float = 95.0
@export var dream_friction: float = 140.0
@export var dream_brake: float = 280.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var bubble: Node2D = $Bubble
@onready var switchable: Node2D = $Switchable
@onready var damageable: Node2D = $Damageable
@onready var attack: Node2D = $Attack
@onready var vitality: Node = get_node_or_null("Vitality")
@onready var sfx: Node = get_node_or_null("SfxPlayer")
@onready var _audio_listener: AudioListener2D = get_node_or_null("AudioListener2D")

@export var hurt_anim_time: float = 0.55
@export var charge_shake_amplitude: float = 1.2
@export var charge_ready_flash_time: float = 0.28

## Last non-zero move facing used by attacks.
var facing: Vector2 = Vector2.DOWN
var _in_dream: bool = false
var _knockback: Vector2 = Vector2.ZERO
var _hurt_lock: float = 0.0
var _anim_before_hurt: StringName = &""
var _flip_before_hurt: bool = false
var _playing_before_hurt: bool = false
var _charging_attack: bool = false
var _charge_shake: bool = false
var _charge_flash: float = 0.0
var _sprite_base_pos: Vector2 = Vector2.ZERO
var _flash_mat: ShaderMaterial
var _dead: bool = false


func _ready() -> void:
	add_to_group("player")
	# Draw above floor props (spikes use z_index 1).
	z_index = maxi(z_index, 2)
	# world + enemy + door_player (open doors omit this layer)
	# Does NOT collide with spikes_enemy — player can step on spikes for damage.
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 2) | (1 << 4)
	_sprite_base_pos = animated_sprite.position
	_ensure_audio_listener()
	_setup_white_flash_material()
	if switchable.has_signal("mode_changed"):
		switchable.mode_changed.connect(_on_mode_changed)
		_on_mode_changed(switchable.get_mode())
	if attack.has_method("setup"):
		attack.setup(self)
	# Prototype: hits are feedback only — no HP gate / death.
	damageable.immortal = true
	if float(damageable.invulnerability_time) <= 0.0:
		damageable.invulnerability_time = maxf(hurt_anim_time, 0.55)
	if damageable.has_signal("damaged"):
		damageable.damaged.connect(_on_damaged)
	if vitality != null and vitality.has_signal("depleted"):
		vitality.depleted.connect(_on_vitality_depleted)
	if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.connect(_on_animation_finished)
	_ensure_attack_anims_once()
	_ensure_hurt_anims_once()
	_sync_sprite_visual()


func _physics_process(delta: float) -> void:
	if _dead:
		velocity = Vector2.ZERO
		_stop_steps()
		move_and_slide()
		return

	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction != Vector2.ZERO:
		facing = _cardinal_from(direction)

	if _hurt_lock > 0.0:
		_hurt_lock = maxf(_hurt_lock - delta, 0.0)
		if _hurt_lock <= 0.0:
			_restore_anim_after_hurt()

	if _knockback.length() > 5.0:
		velocity = _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 600.0 * delta)
	elif _in_dream:
		_move_dream(direction, delta)
	else:
		_move_nightmare(direction)

	var attacking: bool = attack != null and attack.has_method("is_busy") and bool(attack.call("is_busy"))
	var walking := false
	if _hurt_lock <= 0.0 and not attacking and _knockback.length() <= 5.0:
		if direction:
			walking = true
			_play_walk_animation(direction)
		elif velocity.length() < 8.0:
			_play_idle_animation()
	if not walking:
		_stop_steps()

	_update_charge_feedback(delta)
	if vitality != null and vitality.has_method("tick"):
		vitality.call("tick", delta, _in_dream)
	move_and_slide()


func get_vitality() -> Node:
	return vitality


func heal_vitality(amount: float) -> float:
	if _dead or vitality == null or not vitality.has_method("heal"):
		return 0.0
	return float(vitality.call("heal", amount))


func heal_vitality_from_cat() -> float:
	if _dead:
		return 0.0
	if vitality != null and vitality.has_method("heal_from_cat"):
		return float(vitality.call("heal_from_cat"))
	return heal_vitality(40.0)


func _on_vitality_depleted() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	_knockback = Vector2.ZERO
	_clear_charge_feedback()
	_stop_steps()
	if attack != null and attack.has_method("set_enabled"):
		attack.set_enabled(false)
	# Brief death beat, then restart the run.
	play_hurt_animation(facing)
	await get_tree().create_timer(0.35).timeout
	get_tree().reload_current_scene()


func _on_damaged(amount: int, _current_health: int) -> void:
	if _dead:
		return
	if vitality != null and vitality.has_method("apply_hit_damage"):
		vitality.call("apply_hit_damage", amount)
	if _dead:
		return
	if _hurt_lock <= 0.0:
		_anim_before_hurt = animated_sprite.animation
		_flip_before_hurt = animated_sprite.flip_h
		_playing_before_hurt = animated_sprite.is_playing()
	_hurt_lock = hurt_anim_time
	play_hurt_animation(facing)
	_play_hurt_sfx()


func _play_hurt_sfx() -> void:
	if sfx != null and sfx.has_method("play_hurt"):
		sfx.call("play_hurt")


func play_hurt_animation(direction: Vector2) -> void:
	_clear_charge_feedback()
	var dir := direction if direction != Vector2.ZERO else Vector2.DOWN
	var anim_name := StringName("hurt_%s" % _facing_suffix(_cardinal_from(dir)))
	animated_sprite.flip_h = false

	var frames := animated_sprite.sprite_frames
	if frames != null and frames.has_animation(anim_name):
		frames.set_animation_loop(anim_name, false)

	animated_sprite.animation = anim_name
	animated_sprite.frame = 0
	animated_sprite.play(anim_name)
	_sync_sprite_visual()
	_sync_bubble_visible()


func _on_animation_finished() -> void:
	if _hurt_lock <= 0.0:
		return
	if not str(animated_sprite.animation).begins_with("hurt"):
		return
	_hurt_lock = 0.0
	_restore_anim_after_hurt()


func _restore_anim_after_hurt() -> void:
	var prev := _anim_before_hurt
	_anim_before_hurt = &""
	if prev == &"" or str(prev).begins_with("hurt"):
		return
	animated_sprite.flip_h = _flip_before_hurt
	animated_sprite.animation = prev
	if _playing_before_hurt:
		animated_sprite.play(prev)
	else:
		animated_sprite.stop()
		animated_sprite.frame = 0
	_sync_sprite_visual()
	_sync_bubble_visible()


func _ensure_hurt_anims_once() -> void:
	var frames := animated_sprite.sprite_frames
	if frames == null:
		return
	for anim_name in [&"hurt_down", &"hurt_left", &"hurt_right", &"hurt_up"]:
		if frames.has_animation(anim_name):
			frames.set_animation_loop(anim_name, false)


func _ensure_attack_anims_once() -> void:
	var frames := animated_sprite.sprite_frames
	if frames == null:
		return
	for anim_name in [&"attack_down", &"attack_left", &"attack_right", &"attack_up"]:
		if frames.has_animation(anim_name):
			frames.set_animation_loop(anim_name, false)


func apply_knockback(direction: Vector2, force: float) -> void:
	if direction == Vector2.ZERO:
		return
	_knockback = direction.normalized() * force


## Hold frame 0 of attack_* while charging starts.
func begin_attack_charge(direction: Vector2) -> void:
	_charging_attack = true
	_charge_shake = false
	_set_attack_pose(direction, 0)


## Frames 0-1 = charge. Frame 1 vibrates until release.
func update_attack_charge(ratio: float, half: float = 0.5) -> void:
	if not _charging_attack:
		return
	var frame := 1 if ratio >= half else 0
	_charge_shake = frame >= 1
	var anim := _attack_anim_name(_cardinal_from(facing))
	if animated_sprite.animation != anim:
		_set_attack_pose(facing, frame)
	elif animated_sprite.frame != frame:
		animated_sprite.frame = frame
		animated_sprite.pause()


func on_attack_charge_ready() -> void:
	_charge_flash = charge_ready_flash_time
	_set_white_flash(1.0)
	# Extra punch: engine modulate stacks after the shader COLOR.
	animated_sprite.modulate = Color(1.8, 1.8, 1.8, 1.0)


func play_attack_release(direction: Vector2) -> void:
	_charging_attack = false
	_charge_shake = false
	_set_attack_pose(direction, 2)


func cancel_attack_charge() -> void:
	_clear_charge_feedback()


func play_attack_animation(direction: Vector2) -> void:
	play_attack_release(direction)


func _ensure_audio_listener() -> void:
	# Positional AudioStreamPlayer2D needs a current listener (or screen center).
	if _audio_listener == null:
		_audio_listener = AudioListener2D.new()
		_audio_listener.name = "AudioListener2D"
		add_child(_audio_listener)
	_audio_listener.make_current()


func _setup_white_flash_material() -> void:
	var shader := load("res://assets/shaders/white_flash.gdshader") as Shader
	if shader == null:
		return
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = shader
	_flash_mat.set_shader_parameter("flash", 0.0)
	animated_sprite.material = _flash_mat


func _set_white_flash(amount: float) -> void:
	if _flash_mat == null:
		return
	_flash_mat.set_shader_parameter("flash", clampf(amount, 0.0, 1.0))


func _set_attack_pose(direction: Vector2, frame: int) -> void:
	var anim := _attack_anim_name(_cardinal_from(direction))
	var frames := animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		return
	frames.set_animation_loop(anim, false)
	animated_sprite.flip_h = false
	animated_sprite.animation = anim
	var max_frame := maxi(frames.get_frame_count(anim) - 1, 0)
	var clamped := clampi(frame, 0, max_frame)
	# Hold the chosen frame (charge wind-up or strike release).
	animated_sprite.set_frame_and_progress(clamped, 0.0)
	animated_sprite.pause()
	_sync_sprite_visual()
	_sync_bubble_visible()


func _attack_anim_name(cardinal: Vector2) -> StringName:
	return StringName("attack_%s" % _facing_suffix(cardinal))


func _update_charge_feedback(delta: float) -> void:
	if _charge_flash > 0.0:
		_charge_flash = maxf(_charge_flash - delta, 0.0)
		var t := _charge_flash / maxf(charge_ready_flash_time, 0.01)
		_set_white_flash(t)
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(1.8, 1.8, 1.8, 1.0), t)
	else:
		_set_white_flash(0.0)
		if animated_sprite.modulate != Color.WHITE:
			animated_sprite.modulate = Color.WHITE

	if _charge_shake:
		var shake := Vector2(
			randf_range(-charge_shake_amplitude, charge_shake_amplitude),
			randf_range(-charge_shake_amplitude, charge_shake_amplitude) * 0.5
		)
		animated_sprite.position = _sprite_base_pos + shake
	elif animated_sprite.position != _sprite_base_pos:
		animated_sprite.position = _sprite_base_pos


func _clear_charge_feedback() -> void:
	_charging_attack = false
	_charge_shake = false
	_charge_flash = 0.0
	_set_white_flash(0.0)
	animated_sprite.modulate = Color.WHITE
	animated_sprite.position = _sprite_base_pos


func _move_nightmare(direction: Vector2) -> void:
	if direction:
		velocity = direction * SPEED
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED)


func _move_dream(direction: Vector2, delta: float) -> void:
	if direction:
		# Accelerate like a hamster ball; opposite input brakes harder.
		var aligning := velocity.dot(direction)
		var accel := dream_acceleration if aligning >= 0.0 else dream_brake
		velocity += direction * accel * delta
		if velocity.length() > dream_max_speed:
			velocity = velocity.limit_length(dream_max_speed)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, dream_friction * delta)


func _on_mode_changed(index: int) -> void:
	_in_dream = index == 1
	if not _in_dream:
		velocity = Vector2.ZERO
	# Attacks only in nightmare (index 0).
	if attack != null and attack.has_method("set_enabled"):
		attack.set_enabled(not _in_dream)
	# Swap idle set (nightmare <-> bubble) when the mode flips.
	if _hurt_lock <= 0.0:
		_play_idle_animation()
	else:
		_sync_bubble_visible()


func _facing_suffix(cardinal: Vector2) -> StringName:
	if absf(cardinal.x) >= absf(cardinal.y):
		return &"right" if cardinal.x > 0.0 else &"left"
	return &"up" if cardinal.y < 0.0 else &"down"


## Placeholder Bubble node is unused: idle_bubble / walking_bubble include it.
func _sync_bubble_visible() -> void:
	if bubble == null:
		return
	bubble.visible = false


func _play_walk_animation(direction: Vector2) -> void:
	var cardinal := _cardinal_from(direction)
	var prefix := "walking_bubble" if _in_dream else "walking"
	var anim := StringName("%s_%s" % [prefix, _facing_suffix(cardinal)])
	animated_sprite.flip_h = false
	var frames := animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		# Fallback if bubble walk clips are missing.
		anim = StringName("walking_%s" % _facing_suffix(cardinal))
		if frames == null or not frames.has_animation(anim):
			return
	if animated_sprite.animation != anim or not animated_sprite.is_playing():
		animated_sprite.play(anim)
	if sfx != null and sfx.has_method("play_steps"):
		sfx.call("play_steps", _in_dream)
	_sync_sprite_visual()
	_sync_bubble_visible()


func _stop_steps() -> void:
	if sfx != null and sfx.has_method("stop_steps"):
		sfx.call("stop_steps")


func _play_idle_animation() -> void:
	_stop_steps()
	var cardinal := _cardinal_from(facing)
	var prefix := "idle_bubble" if _in_dream else "idle_nightmare"
	var anim := StringName("%s_%s" % [prefix, _facing_suffix(cardinal)])
	# Sheets have dedicated left/right clips (no flip_h).
	animated_sprite.flip_h = false
	var frames := animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		return
	if animated_sprite.animation != anim or not animated_sprite.is_playing():
		animated_sprite.play(anim)
	_sync_sprite_visual()
	_sync_bubble_visible()


## Definitivo sheets (idle/walk/attack/hurt) are HD 992px cells.
## Scale them down to match the old walk on-screen size.
func _sync_sprite_visual() -> void:
	if animated_sprite == null:
		return
	var anim := str(animated_sprite.animation)
	var use_hd := (
		anim.begins_with("idle")
		or anim.begins_with("walking")
		or anim.begins_with("attack")
		or anim.begins_with("hurt")
	)
	if use_hd:
		var target_h := WALK_CONTENT_RECT.size.y * PIXEL_SPRITE_SCALE
		var s := target_h / IDLE_CONTENT_RECT.size.y
		animated_sprite.scale = Vector2(s, s)
		animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var walk_foot_from_center := (
			(WALK_CONTENT_RECT.position.y + WALK_CONTENT_RECT.size.y) - WALK_FRAME_SIZE.y * 0.5
		) * PIXEL_SPRITE_SCALE
		var idle_foot_from_center_px := (
			(IDLE_CONTENT_RECT.position.y + IDLE_CONTENT_RECT.size.y) - IDLE_FRAME_SIZE.y * 0.5
		)
		animated_sprite.offset = Vector2(0.0, walk_foot_from_center / s - idle_foot_from_center_px)
	else:
		animated_sprite.scale = Vector2(PIXEL_SPRITE_SCALE, PIXEL_SPRITE_SCALE)
		animated_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		animated_sprite.offset = Vector2.ZERO


func _cardinal_from(direction: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		return facing if facing != Vector2.ZERO else Vector2.DOWN
	if absf(direction.x) >= absf(direction.y):
		return Vector2.RIGHT if direction.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if direction.y > 0.0 else Vector2.UP
