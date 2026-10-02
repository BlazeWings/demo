class_name GameCamera
extends Camera2D

## Follow camera: manual smoothing + velocity look-ahead + trauma screen shake.
##
## Contract: memory/api-contract-v1.md §6 and §11.4.
## Every other system talks to the camera only through the "game_camera" group:
##   get_tree().call_group("game_camera", "add_trauma", 0.5)
##   get_tree().call_group("game_camera", "set_limits", left, top, right, bottom)
## The level spawns the player at runtime, so `target` is re-resolved while it is missing.

@export var target_path: NodePath
## Follow catch-up rate (higher = snappier), applied in _process.
@export var follow_speed: float = 8.0
## Horizontal look-ahead distance in pixels.
@export var look_ahead_distance: float = 80.0
## How fast the look-ahead offset steers toward the movement direction.
@export var look_ahead_speed: float = 4.0
## Maximum shake offset in pixels (both axes).
@export var max_shake_offset: float = 20.0
## Maximum shake roll in degrees.
@export var max_shake_roll_degrees: float = 15.0
## Trauma lost per second (trauma lives in 0..1).
@export var trauma_decay: float = 1.5
## Shake noise frequency; higher = more jittery.
@export var shake_noise_speed: float = 60.0
@export var use_noise_shake: bool = true
## How often a missing target is looked up again, in seconds.
@export var target_retry_interval: float = 0.25

## Node2D followed by this camera. Resolved from `target_path`, else from group "player".
var target: Node2D

var _trauma: float = 0.0
var _noise_time: float = 0.0
var _look_ahead: Vector2 = Vector2.ZERO
## Last non-zero horizontal facing, so the look-ahead does not snap back at jump apex.
var _facing: float = 1.0
var _retry_timer: float = 0.0
var _noise: FastNoiseLite


func _ready() -> void:
	add_to_group("game_camera")
	position_smoothing_enabled = false
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = randi()
	if _acquire_target():
		snap_to_target()


func _process(delta: float) -> void:
	if _has_target():
		_follow(delta)
	else:
		_retry_timer -= delta
		if _retry_timer <= 0.0:
			_retry_timer = target_retry_interval
			if _acquire_target():
				snap_to_target()
	_update_shake(delta)


## Adds trauma (0..1, clamped). Callers pass small values like 0.3 / 0.5.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func get_trauma() -> float:
	return _trauma


## Level bounds in world pixels; called through the "game_camera" group.
func set_limits(left: int, top: int, right: int, bottom: int) -> void:
	limit_left = left
	limit_top = top
	limit_right = right
	limit_bottom = bottom


## Jumps straight to the focus point, dropping any smoothing backlog.
func snap_to_target() -> void:
	if not _has_target():
		return
	_look_ahead = Vector2.ZERO
	global_position = _focus_position()


func _has_target() -> bool:
	return target != null and is_instance_valid(target)


func _acquire_target() -> bool:
	if target_path != NodePath():
		var bound := get_node_or_null(target_path)
		if bound is Node2D:
			target = bound as Node2D
			return true
	if not is_inside_tree():
		return false
	var player := get_tree().get_first_node_in_group("player")
	if player is Node2D:
		target = player as Node2D
		return true
	return false


func _focus_position() -> Vector2:
	return target.global_position + _look_ahead


func _follow(delta: float) -> void:
	var velocity_x := _target_velocity().x
	if absf(velocity_x) > 1.0:
		_facing = signf(velocity_x)
	var desired_ahead := Vector2(_facing * look_ahead_distance, 0.0)
	_look_ahead = _look_ahead.lerp(desired_ahead, clampf(look_ahead_speed * delta, 0.0, 1.0))
	global_position = global_position.lerp(_focus_position(), clampf(follow_speed * delta, 0.0, 1.0))


## Duck-typed read of CharacterBody2D.velocity; anything else counts as standing still.
func _target_velocity() -> Vector2:
	if not _has_target():
		return Vector2.ZERO
	var value: Variant = target.get("velocity")
	if value is Vector2:
		return value
	return Vector2.ZERO


func _update_shake(delta: float) -> void:
	if _trauma <= 0.0:
		_trauma = 0.0
		offset = Vector2.ZERO
		rotation = 0.0
		return
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	_noise_time += delta * shake_noise_speed
	var shake := _trauma * _trauma
	var noise_x := randf_range(-1.0, 1.0)
	var noise_y := randf_range(-1.0, 1.0)
	var noise_roll := randf_range(-1.0, 1.0)
	if use_noise_shake:
		noise_x = _noise.get_noise_2d(_noise_time, 0.0)
		noise_y = _noise.get_noise_2d(0.0, _noise_time)
		noise_roll = _noise.get_noise_2d(_noise_time, _noise_time)
	offset = Vector2(max_shake_offset * shake * noise_x, max_shake_offset * shake * noise_y)
	rotation = deg_to_rad(max_shake_roll_degrees) * shake * noise_roll
