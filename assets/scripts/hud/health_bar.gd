extends CanvasLayer

## Fused sheet: 6 frames × 3 max-HP sizes.
## Red tip moves continuously in pixels (no progress-bar cell jumps).
## Frame pairs only pick which art keeps/opens the eye:
##   (0→1) closed, (2→3) opening, (4→5) open.
## Buff icons under the bar: attack / projectile / shield.

const COLS := 6
const ROWS := 3
const CELL := Vector2i(395, 395)
## Visible bar art ends around here — layout height ignores empty cell padding below.
const LAYOUT_HEIGHT := 210
const BUFF_CELL := Vector2i(95, 95)
## Sheet: left = vigilia / sueño, right = pesadilla.
## Full stride per frame on the sheet (includes empty padding on the right).
const MODE_SWITCH_STRIDE := 321
## Opaque art bounds inside each stride — pie must center on this, not the padding.
const MODE_SWITCH_CELL := Vector2i(212, 321)
const MODE_SWITCH_FRAME_VIGILIA := 0
const MODE_SWITCH_FRAME_PESADILLA := 1
## Left edge of the red body inside each cell (round cap sits left of this, x 0..34).
const RED_LEFT := 34.0
## Right edge of the red fill per frame (measured from the sheet).
const RED_RIGHT := [
	[197, 155, 154, 94, 93, 81],
	[257, 183, 182, 108, 107, 81],
	[311, 231, 230, 133, 131, 81],
]

@export var sheet: Texture2D
@export var buff_sheet: Texture2D
@export var mode_switch_sheet: Texture2D
@export var bar_scale: float = 0.42
@export var buff_icon_scale: float = 0.42
@export var mode_switch_scale: float = 0.3
## Gap between the switch icon and the vitality bar (was negative when the atlas had empty padding).
@export var switch_bar_separation: int = 8
@export var base_max_vitality: float = 100.0
@export var vitality_per_size_tier: float = 20.0
## Visible bar eases down to real HP during vigilia drain (ratio / sec).
@export var visual_drain_per_second: float = 0.12
## Hit damage (enemies / spikes) catches up at this rate (ratio / sec).
@export var hit_drain_per_second: float = 3.0
@export var visual_rise_per_second: float = 0.55

@onready var _root: Control = $Margin/Column/TopRow/Root
@onready var _under: TextureRect = $Margin/Column/TopRow/Root/Under
@onready var _fill: TextureRect = $Margin/Column/TopRow/Root/Fill
@onready var _buff_pad: MarginContainer = $Margin/Column/BuffPad
@onready var _buff_attack: VBoxContainer = $Margin/Column/BuffPad/BuffRow/Attack
@onready var _buff_projectile: VBoxContainer = $Margin/Column/BuffPad/BuffRow/Projectile
@onready var _buff_shield: VBoxContainer = $Margin/Column/BuffPad/BuffRow/Shield
@onready var _mode_switch: TextureRect = $Margin/Column/TopRow/ModeSwitch
@onready var _top_row: HBoxContainer = $Margin/Column/TopRow

var _vitality: Node = null
var _buffs: Node = null
var _frames: Array[AtlasTexture] = []
var _buff_icons: Array[AtlasTexture] = []
var _mode_switch_frames: Array[AtlasTexture] = []
var _fill_atlas: AtlasTexture = AtlasTexture.new()
var _size_row: int = -1
var _pair_index: int = -1
var _target_ratio: float = 1.0
var _display_ratio: float = 1.0
var _target_max: float = 100.0
## Remaining ratio that must close at hit speed (queued per hit chunk).
var _hit_catchup: float = 0.0
var _switch_cd_pie: Control = null
var _switch_cd_ratio: float = 0.0
const _SWITCH_CD_PIE_SCRIPT: GDScript = preload("res://assets/scripts/hud/switch_cooldown_pie.gd")


func _ready() -> void:
	layer = 60
	_fill_atlas.atlas = sheet
	_build_frames()
	_build_buff_icons()
	_build_mode_switch_frames()
	_configure_nodes()
	_bind_world_mode()
	call_deferred("_bind_player")


func _process(delta: float) -> void:
	_sync_target_from_vitality()
	_tick_display_ratio(delta)
	_set_visual(_display_ratio, _target_max)
	_update_buff_icons()
	_update_switch_cooldown_visual()


func _tick_display_ratio(delta: float) -> void:
	if is_equal_approx(_display_ratio, _target_ratio):
		_display_ratio = _target_ratio
		_hit_catchup = 0.0
		return
	if _display_ratio > _target_ratio:
		var gap := _display_ratio - _target_ratio
		if _hit_catchup > 0.0:
			var rate := maxf(hit_drain_per_second, visual_drain_per_second)
			var step := minf(minf(_hit_catchup, gap), rate * delta)
			_display_ratio = maxf(_target_ratio, _display_ratio - step)
			_hit_catchup = maxf(_hit_catchup - step, 0.0)
		else:
			_display_ratio = maxf(_target_ratio, _display_ratio - visual_drain_per_second * delta)
	else:
		_hit_catchup = 0.0
		_display_ratio = minf(_target_ratio, _display_ratio + visual_rise_per_second * delta)


func _build_frames() -> void:
	_frames.clear()
	if sheet == null:
		return
	for row in ROWS:
		for col in COLS:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(col * CELL.x, row * CELL.y, CELL.x, CELL.y)
			_frames.append(atlas)


func _build_buff_icons() -> void:
	_buff_icons.clear()
	if buff_sheet == null:
		return
	for i in 3:
		var atlas := AtlasTexture.new()
		atlas.atlas = buff_sheet
		atlas.region = Rect2(i * BUFF_CELL.x, 0, BUFF_CELL.x, BUFF_CELL.y)
		_buff_icons.append(atlas)


func _build_mode_switch_frames() -> void:
	_mode_switch_frames.clear()
	if mode_switch_sheet == null:
		return
	for i in 2:
		var atlas := AtlasTexture.new()
		atlas.atlas = mode_switch_sheet
		# Crop empty right padding so the ornate circle is centered in the TextureRect.
		atlas.region = Rect2(i * MODE_SWITCH_STRIDE, 0, MODE_SWITCH_CELL.x, MODE_SWITCH_CELL.y)
		_mode_switch_frames.append(atlas)


func _frame(row: int, col: int) -> AtlasTexture:
	return _frames[row * COLS + col]


func _bind_world_mode() -> void:
	if WorldMode != null and WorldMode.has_signal("mode_changed"):
		if not WorldMode.mode_changed.is_connected(_on_world_mode_changed):
			WorldMode.mode_changed.connect(_on_world_mode_changed)
		_on_world_mode_changed(WorldMode.get_mode())
	else:
		_apply_mode_switch_frame(MODE_SWITCH_FRAME_PESADILLA)
	if WorldMode != null and WorldMode.has_signal("switch_cooldown_changed"):
		if not WorldMode.switch_cooldown_changed.is_connected(_on_switch_cooldown_changed):
			WorldMode.switch_cooldown_changed.connect(_on_switch_cooldown_changed)
		_on_switch_cooldown_changed(
			WorldMode.get_switch_cooldown_remaining(),
			WorldMode.get_switch_cooldown_duration()
		)


func _on_world_mode_changed(mode: int) -> void:
	# Sheet order: 1 vigilia / sueño, 2 pesadilla.
	var frame := (
		MODE_SWITCH_FRAME_PESADILLA
		if mode == WorldMode.MODE_PESADILLA
		else MODE_SWITCH_FRAME_VIGILIA
	)
	_apply_mode_switch_frame(frame)


func _on_switch_cooldown_changed(remaining: float, duration: float) -> void:
	if duration <= 0.0:
		_switch_cd_ratio = 0.0
	else:
		_switch_cd_ratio = clampf(remaining / duration, 0.0, 1.0)
	_update_switch_cooldown_visual()


func _apply_mode_switch_frame(frame: int) -> void:
	if _mode_switch == null or _mode_switch_frames.is_empty():
		return
	var idx := clampi(frame, 0, _mode_switch_frames.size() - 1)
	_mode_switch.texture = _mode_switch_frames[idx]


func _configure_nodes() -> void:
	for node in [_under, _fill]:
		if node == null:
			continue
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_SCALE
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if _fill != null:
		_fill.texture = _fill_atlas
		_fill.z_index = 1
	if _under != null:
		_under.z_index = 0
	if _mode_switch != null:
		_mode_switch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mode_switch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_mode_switch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_mode_switch.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_mode_switch.clip_contents = false
		_mode_switch.material = null
		_mode_switch.modulate = Color.WHITE
		var switch_size := Vector2(MODE_SWITCH_CELL) * mode_switch_scale
		_ensure_switch_cooldown_overlay(switch_size)
		if _buff_pad != null:
			var top_sep := -10
			if _top_row != null:
				top_sep = _top_row.get_theme_constant("separation")
			_buff_pad.add_theme_constant_override(
				"margin_left",
				maxi(0, roundi(switch_size.x + float(top_sep)))
			)
	if _root != null:
		_root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _top_row != null:
		_top_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_top_row.add_theme_constant_override("separation", switch_bar_separation)
	_configure_buff_slot(_buff_attack, 0)
	_configure_buff_slot(_buff_projectile, 1)
	_configure_buff_slot(_buff_shield, 2)
	_target_max = base_max_vitality
	_target_ratio = 1.0
	_display_ratio = 1.0
	_apply_size_row(0, true)
	_set_visual(1.0, base_max_vitality, true)
	_update_buff_icons()


func _configure_buff_slot(slot: VBoxContainer, icon_index: int) -> void:
	if slot == null:
		return
	var icon := slot.get_node_or_null("Icon") as TextureRect
	if icon == null:
		return
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_size := Vector2(BUFF_CELL) * buff_icon_scale
	icon.custom_minimum_size = icon_size
	icon.size = icon_size
	if icon_index >= 0 and icon_index < _buff_icons.size():
		icon.texture = _buff_icons[icon_index]


func _size_tier(max_vitality: float) -> int:
	var gained := maxf(max_vitality - base_max_vitality, 0.0)
	return clampi(floori(gained / maxf(vitality_per_size_tier, 0.001)), 0, ROWS - 1)


func _fill_ratio_for_col(row: int, col: int) -> float:
	var tips: Array = RED_RIGHT[row]
	var span := float(tips[0]) - RED_LEFT
	if span <= 0.0:
		return 0.0
	return clampf((float(tips[col]) - RED_LEFT) / span, 0.0, 1.0)


func _pair_for_ratio(row: int, ratio: float) -> Dictionary:
	var r := clampf(ratio, 0.0, 1.0)
	var lo_closed := _fill_ratio_for_col(row, 1)
	var lo_opening := _fill_ratio_for_col(row, 3)
	if r >= lo_closed:
		return {"pair": 0, "progress": 0, "under": 1}
	if r >= lo_opening:
		return {"pair": 1, "progress": 2, "under": 3}
	return {"pair": 2, "progress": 4, "under": 5}


func _apply_size_row(row: int, force: bool = false) -> void:
	if not force and row == _size_row:
		return
	if _frames.is_empty() or row < 0 or row >= ROWS:
		return
	_size_row = row
	_pair_index = -1
	var draw_size := Vector2(CELL) * bar_scale
	var layout_size := Vector2(float(CELL.x), float(LAYOUT_HEIGHT)) * bar_scale
	if _root != null:
		_root.custom_minimum_size = layout_size
		_root.size = layout_size
		_root.clip_contents = false
		_root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if _under != null:
		_under.position = Vector2.ZERO
		_under.size = draw_size
	# Keep switch and bar on the same vertical center axis.
	if _mode_switch != null:
		var switch_h := float(MODE_SWITCH_CELL.y) * mode_switch_scale
		var row_h := maxf(layout_size.y, switch_h)
		if _top_row != null:
			_top_row.custom_minimum_size.y = row_h


func _set_visual(ratio: float, max_vitality: float, force: bool = false) -> void:
	if _frames.is_empty() or sheet == null or _fill == null or _under == null:
		return
	var r := clampf(ratio, 0.0, 1.0)
	var row := _size_tier(max_vitality)
	_apply_size_row(row, force)

	var seg: Dictionary = _pair_for_ratio(row, r)
	var pair: int = int(seg["pair"])
	var progress_col: int = int(seg["progress"])
	var under_col: int = int(seg["under"])
	if force or pair != _pair_index:
		_pair_index = pair
		_under.texture = _frame(row, under_col)

	## Continuous tip in sheet pixels — independent of cell padding.
	## The round cap (x 0..RED_LEFT) always stays; only the red body shrinks.
	var full_tip := float(RED_RIGHT[row][0])
	var span := full_tip - RED_LEFT
	var tip_px := RED_LEFT + span * r
	if r <= 0.0 or span <= 0.0:
		_fill.visible = false
		return
	_fill.visible = true
	_fill_atlas.atlas = sheet
	_fill_atlas.region = Rect2(progress_col * CELL.x, row * CELL.y, tip_px, float(CELL.y))
	_fill.position = Vector2.ZERO
	_fill.size = Vector2(tip_px, float(CELL.y)) * bar_scale


func _update_buff_icons() -> void:
	if _buffs == null:
		_set_buff_slot(_buff_attack, false, 0)
		_set_buff_slot(_buff_projectile, false, 0)
		_set_buff_slot(_buff_shield, false, 0)
		return

	var attack_on := _buffs.has_method("has_attack_boost") and bool(_buffs.call("has_attack_boost"))
	var attack_count := 0
	if attack_on and _buffs.has_method("get_attack_stacks"):
		attack_count = int(_buffs.call("get_attack_stacks"))
	_set_buff_slot(_buff_attack, attack_on, attack_count)

	var proj_on := _buffs.has_method("has_projectile_boost") and bool(_buffs.call("has_projectile_boost"))
	var proj_count := 0
	if proj_on and _buffs.has_method("get_projectile_stacks"):
		proj_count = int(_buffs.call("get_projectile_stacks"))
	_set_buff_slot(_buff_projectile, proj_on, proj_count)

	var shield_hits := 0
	if _buffs.has_method("get_shield_hits"):
		shield_hits = int(_buffs.call("get_shield_hits"))
	_set_buff_slot(_buff_shield, shield_hits > 0, shield_hits)


func _set_buff_slot(slot: VBoxContainer, active: bool, count: int) -> void:
	if slot == null:
		return
	slot.visible = active
	if not active:
		return
	var label := slot.get_node_or_null("Count") as Label
	if label != null:
		label.text = "x%d" % maxi(count, 0)


func _sync_target_from_vitality() -> void:
	if _vitality == null:
		return
	if _vitality is PlayerVitality:
		var pv := _vitality as PlayerVitality
		_target_ratio = pv.get_ratio()
		_target_max = pv.max_vitality
		return
	if _vitality.has_method("get_ratio"):
		_target_ratio = float(_vitality.call("get_ratio"))
	var max_value: Variant = _vitality.get("max_vitality")
	if max_value != null:
		_target_max = float(max_value)


func _bind_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var vit: Node = player.get_node_or_null("Vitality")
	if vit == null and player.has_method("get_vitality"):
		vit = player.call("get_vitality") as Node
	_unbind_vitality_signals()
	_vitality = vit
	_buffs = player.get_node_or_null("Buffs")
	if _buffs == null and player.has_method("get_buffs"):
		_buffs = player.call("get_buffs") as Node
	_bind_vitality_signals()
	if _vitality != null:
		_sync_target_from_vitality()
		_display_ratio = _target_ratio
		_hit_catchup = 0.0
		_set_visual(_display_ratio, _target_max, true)
	_update_buff_icons()


func _bind_vitality_signals() -> void:
	if _vitality == null:
		return
	if _vitality.has_signal("hit_applied") and not _vitality.hit_applied.is_connected(_on_vitality_hit):
		_vitality.hit_applied.connect(_on_vitality_hit)


func _unbind_vitality_signals() -> void:
	if _vitality == null:
		return
	if _vitality.has_signal("hit_applied") and _vitality.hit_applied.is_connected(_on_vitality_hit):
		_vitality.hit_applied.disconnect(_on_vitality_hit)


func _on_vitality_hit(lost: float, _current: float, max_vitality: float) -> void:
	if lost <= 0.0:
		return
	var cap := maxf(max_vitality, 0.001)
	## Queue a visual chunk matching the hit (1 dmg → vitality_per_damage_point / max).
	_hit_catchup += lost / cap
	_sync_target_from_vitality()


func _switch_icon_size() -> Vector2:
	return Vector2(MODE_SWITCH_CELL) * mode_switch_scale


func _layout_top_left(ctrl: Control, rect_size: Vector2) -> void:
	if ctrl == null:
		return
	# Explicit pixel layout — no anchors (avoids HBox stretch / TextureRect quirks).
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0
	ctrl.position = Vector2.ZERO
	ctrl.size = rect_size


func _ensure_switch_cooldown_overlay(switch_size: Vector2) -> void:
	if _mode_switch == null or _top_row == null:
		return

	var slot := _mode_switch.get_parent() as Control
	if slot == null or slot.name != "SwitchSlot":
		var row := _mode_switch.get_parent()
		if row == null:
			return
		var index := _mode_switch.get_index()
		slot = Control.new()
		slot.name = "SwitchSlot"
		row.add_child(slot)
		row.move_child(slot, index)
		_mode_switch.reparent(slot)

	# Fixed square in the HBox — never expand, or the pie center drifts right.
	slot.custom_minimum_size = switch_size
	slot.size = switch_size
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.clip_contents = true

	_layout_top_left(_mode_switch, switch_size)
	_mode_switch.custom_minimum_size = switch_size
	_mode_switch.size_flags_horizontal = 0
	_mode_switch.size_flags_vertical = 0

	for legacy_name in ["CooldownShade", "CooldownOverlay", "CooldownPie"]:
		var under_icon := _mode_switch.get_node_or_null(legacy_name)
		if under_icon != null:
			under_icon.queue_free()
		var under_slot := slot.get_node_or_null(legacy_name)
		if under_slot != null and legacy_name != "CooldownPie":
			under_slot.queue_free()

	_switch_cd_pie = slot.get_node_or_null("CooldownPie") as Control
	if _switch_cd_pie == null:
		_switch_cd_pie = Control.new()
		_switch_cd_pie.name = "CooldownPie"
		_switch_cd_pie.set_script(_SWITCH_CD_PIE_SCRIPT)
		slot.add_child(_switch_cd_pie)

	_switch_cd_pie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_switch_cd_pie.z_index = 4
	_layout_top_left(_switch_cd_pie, switch_size)
	_switch_cd_pie.set("ratio", 0.0)


func _update_switch_cooldown_visual() -> void:
	var switch_size := _switch_icon_size()
	if _switch_cd_pie == null and _mode_switch != null:
		_ensure_switch_cooldown_overlay(switch_size)
	if _switch_cd_pie == null:
		return

	# Keep slot / icon / pie locked to the same square every frame.
	var slot := _switch_cd_pie.get_parent() as Control
	if slot != null and slot.name == "SwitchSlot":
		slot.custom_minimum_size = switch_size
		slot.size = switch_size
		slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_layout_top_left(_mode_switch, switch_size)
	_layout_top_left(_switch_cd_pie, switch_size)

	var ratio := 0.0
	if WorldMode != null and WorldMode.has_method("get_switch_cooldown_ratio"):
		ratio = float(WorldMode.call("get_switch_cooldown_ratio"))
	_switch_cd_ratio = clampf(ratio, 0.0, 1.0)
	_switch_cd_pie.set("ratio", _switch_cd_ratio)
