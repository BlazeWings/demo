class_name Player
extends CharacterBody2D

## 长枪骑士控制器（契约 §4 / §10.2 / §11）。
## 数值为契约冻结的手感基线；状态逻辑在 states/ 下的 node-based FSM 中。

enum AttackDirection { HORIZONTAL, UP, DOWN }

const SPEED: float = 170.0
const ACCEL: float = 1600.0
const DECEL: float = 1100.0
const JUMP_VELOCITY: float = -430.0
const JUMP_CUT_MULT: float = 0.45
const FALL_GRAVITY_MULT: float = 1.4
const MAX_FALL_SPEED: float = 520.0
const COYOTE_TIME: float = 0.15
const JUMP_BUFFER_TIME: float = 0.12
const DASH_SPEED: float = 460.0
const DASH_DURATION: float = 0.15
const MAX_DASHES: int = 1
const DASH_ANIM_SPEED_SCALE: float = 2.0
const ATTACK_ACTIVE_TIME: float = 0.12
const ATTACK_TOTAL_TIME: float = 0.33
const POGO_VELOCITY: float = -280.0
const HURT_KNOCKBACK_X: float = 200.0
const HURT_KNOCKBACK_Y: float = -150.0
const HURT_FLASH_TIME: float = 0.12
const HURT_STATE_TIME: float = 0.3
const INVULN_TIME: float = 1.0
const BLINK_PERIOD: float = 0.16
const BLINK_ALPHA: float = 0.35
const HEAL_CHARGE_TIME: float = 0.8
const DEATH_TIME: float = 1.0
const DEATH_ROTATION: float = PI * 0.5
const SOUL_PER_HIT: int = 11
const SOUL_HEAL_COST: int = 33
const INTERACT_RADIUS: float = 24.0
const INTERACT_MASK: int = 8
const SPRITE_ROOT: String = "res://assets/sprites/player/knight/"
const ATTACK_HITBOX_FALLBACK_OFFSET := Vector2(26.0, 0.0)
const DASH_GLOW := Color(1.5, 1.5, 1.5)
const HURT_FLASH := Color(2.5, 2.5, 2.5)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_component: HealthComponent = $Components/HealthComponent
@onready var hurtbox: HurtboxComponent = $Components/HurtboxComponent
@onready var attack_hitbox: HitboxComponent = $AttackHitbox
@onready var state_machine: PlayerStateMachine = $StateMachine
@onready var dash_ghost: CPUParticles2D = $DashGhost
@onready var heal_particles: CPUParticles2D = $HealParticles

var gravity: float = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

var facing: int = 1
var input_x: float = 0.0
var up_held: bool = false
var down_held: bool = false

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0

var dash_requested: bool = false
var attack_requested: bool = false
var heal_requested: bool = false

var dashes_available: int = MAX_DASHES
var current_attack_direction: int = AttackDirection.HORIZONTAL

var _sprite_base_scale := Vector2.ONE
var _sprite_base_position := Vector2.ZERO
## 脚底到原点的偏移（父坐标系像素）：落地挤压锚点 & 上挑/下劈的旋转轴心都用它。
var _squash_anchor_y: float = 0.0
var _squash_offset := Vector2.ZERO
## 上挑/下劈时为保证"脚底不动"而给 sprite 中心加的补偿位移。
var _attack_pivot_offset := Vector2.ZERO
var _attack_hitbox_base_offset := Vector2.ZERO
var _squash_tween: Tween
var _death_tween: Tween

var _is_dashing: bool = false
var _is_dead: bool = false
var _jump_cut_requested: bool = false
var _was_on_floor: bool = false
var _invuln_timer: float = 0.0
var _blink_on: bool = true
var _hurt_flash_timer: float = 0.0


func _ready() -> void:
	add_to_group("player")
	floor_block_on_wall = false
	_build_sprite_frames()
	_cache_sprite_layout()
	_cache_attack_hitbox()
	_wire_components()
	if state_machine != null:
		state_machine.start()


func _physics_process(delta: float) -> void:
	input_x = Input.get_axis("move_left", "move_right")
	up_held = Input.is_action_pressed("move_up")
	down_held = Input.is_action_pressed("move_down")
	_tick_timers(delta)
	_update_sprite_modulate()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_buffer_timer = JUMP_BUFFER_TIME
	elif event.is_action_released("jump"):
		_jump_cut_requested = true
	elif event.is_action_pressed("dash"):
		dash_requested = true
	elif event.is_action_pressed("attack"):
		attack_requested = true
	elif event.is_action_pressed("heal"):
		heal_requested = true
	elif event.is_action_pressed("interact"):
		_try_interact()


# --- 状态机调用的移动助手（只在 _physics_process 链路中调用）---

func apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var multiplier := FALL_GRAVITY_MULT if velocity.y > 0.0 else 1.0
	velocity.y = minf(velocity.y + gravity * multiplier * delta, MAX_FALL_SPEED)


func apply_horizontal_move(delta: float) -> void:
	if is_zero_approx(input_x):
		velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
	else:
		velocity.x = move_toward(velocity.x, input_x * SPEED, ACCEL * delta)


func apply_horizontal_brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)


func update_facing_from_input() -> void:
	if input_x > 0.0:
		set_facing(1)
	elif input_x < 0.0:
		set_facing(-1)


func set_facing(dir: int) -> void:
	if dir == 0 or dir == facing:
		return
	facing = dir
	sprite.flip_h = facing < 0
	_place_attack_hitbox(current_attack_direction)


func is_moving_fast() -> bool:
	return absf(velocity.x) >= SPEED * 0.85


func can_dash() -> bool:
	return dashes_available > 0


func reset_dashes() -> void:
	dashes_available = MAX_DASHES


## 聚气回血前置条件：未满血 且 灵魂足够（契约 §4 Heal）。
func can_heal() -> bool:
	if health_component.get_health() >= health_component.max_health:
		return false
	return GameManager.soul >= SOUL_HEAL_COST


func do_jump() -> void:
	velocity.y = JUMP_VELOCITY
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	set_squash(0.85, 1.18)


func clear_input_requests() -> void:
	dash_requested = false
	attack_requested = false
	heal_requested = false


# --- 攻击 ---

func resolve_attack_direction() -> int:
	if up_held:
		return AttackDirection.UP
	if down_held and not is_on_floor():
		return AttackDirection.DOWN
	return AttackDirection.HORIZONTAL


func begin_attack(direction: int) -> void:
	current_attack_direction = direction
	_place_attack_hitbox(direction)
	match direction:
		AttackDirection.UP:
			_set_attack_rotation(-PI * 0.5)
			play_anim(&"attack2")
		AttackDirection.DOWN:
			_set_attack_rotation(PI * 0.5)
			play_anim(&"attack2")
		_:
			_set_attack_rotation(0.0)
			play_anim(&"attack1")
	attack_hitbox.set_active(true)


func deactivate_attack_hitbox() -> void:
	attack_hitbox.set_active(false)


func end_attack() -> void:
	deactivate_attack_hitbox()
	current_attack_direction = AttackDirection.HORIZONTAL
	_set_attack_rotation(0.0)
	_place_attack_hitbox(AttackDirection.HORIZONTAL)


func _place_attack_hitbox(direction: int) -> void:
	if attack_hitbox == null:
		return
	var angle := 0.0
	match direction:
		AttackDirection.UP:
			angle = -PI * 0.5
		AttackDirection.DOWN:
			angle = PI * 0.5
	var offset := _attack_hitbox_base_offset.rotated(angle)
	offset.x *= float(facing)
	attack_hitbox.rotation = angle
	attack_hitbox.position = offset


func _on_attack_hit_landed() -> void:
	Hitstop.hitstop(0.06)
	get_tree().call_group("game_camera", "add_trauma", 0.3)
	GameManager.add_soul(SOUL_PER_HIT)
	if current_attack_direction == AttackDirection.DOWN and not is_on_floor():
		velocity.y = POGO_VELOCITY
		reset_dashes()


# --- 冲刺 ---

func begin_dash() -> void:
	dashes_available = maxi(dashes_available - 1, 0)
	_is_dashing = true
	sprite.speed_scale = DASH_ANIM_SPEED_SCALE
	play_anim(&"run")
	if dash_ghost != null:
		dash_ghost.restart()
		dash_ghost.emitting = true


func end_dash() -> void:
	_is_dashing = false
	sprite.speed_scale = 1.0
	if dash_ghost != null:
		dash_ghost.emitting = false


# --- 聚气回血 ---

func begin_heal() -> void:
	play_anim(&"idle")
	if heal_particles != null:
		heal_particles.restart()
		heal_particles.emitting = true


func end_heal() -> void:
	if heal_particles != null:
		heal_particles.emitting = false


func finish_heal() -> void:
	if GameManager.try_consume_soul(SOUL_HEAL_COST):
		health_component.heal(1)


# --- 受击 / 死亡 ---

func on_hazard() -> void:
	if _is_dead:
		return
	if hurtbox == null or not hurtbox.is_invulnerable():
		health_component.take_damage(1, global_position + Vector2(0.0, 16.0))
	global_position = GameManager.get_respawn()
	velocity = Vector2.ZERO
	_start_invulnerability()


func _on_damaged(_amount: int, source_position: Vector2) -> void:
	if _is_dead:
		return
	var away := signf(global_position.x - source_position.x)
	if is_zero_approx(away):
		away = -float(facing)
	velocity = Vector2(HURT_KNOCKBACK_X * away, HURT_KNOCKBACK_Y)
	_hurt_flash_timer = HURT_FLASH_TIME
	_start_invulnerability()
	get_tree().call_group("game_camera", "add_trauma", 0.5)
	if state_machine != null:
		state_machine.transition_to(PlayerStateMachine.HURT)


func _on_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	if state_machine != null:
		state_machine.transition_to(PlayerStateMachine.DEAD)


func on_death_started() -> void:
	velocity = Vector2.ZERO
	if hurtbox != null:
		hurtbox.set_deferred("monitorable", false)
	if dash_ghost != null:
		dash_ghost.emitting = false
	if heal_particles != null:
		heal_particles.emitting = false
	sprite.speed_scale = 1.0
	freeze_frame(&"idle", 0)
	_kill_tween(_death_tween)
	_death_tween = create_tween()
	_death_tween.set_parallel(true)
	_death_tween.tween_property(sprite, "rotation", -DEATH_ROTATION * float(facing), 0.35)
	_death_tween.tween_property(sprite, "modulate:a", 0.0, 0.5).set_delay(0.25)


func respawn() -> void:
	global_position = GameManager.get_respawn()
	velocity = Vector2.ZERO
	health_component.reset_health()
	if hurtbox != null:
		hurtbox.set_deferred("monitorable", true)
	_kill_tween(_death_tween)
	_set_attack_rotation(0.0)
	sprite.modulate = Color.WHITE
	sprite.speed_scale = 1.0
	reset_squash()
	_is_dead = false
	_hurt_flash_timer = 0.0
	set_facing(1)
	_start_invulnerability()
	play_anim(&"idle")


func _start_invulnerability() -> void:
	_invuln_timer = INVULN_TIME
	_blink_on = true
	if hurtbox != null:
		hurtbox.set_invulnerable(INVULN_TIME)


# --- 动画 / 表现 ---

func play_anim(anim_name: StringName) -> void:
	if not _has_anim(anim_name):
		return
	# Godot 4.7 的 AnimatedSprite2D 没有 paused 属性（直接赋值会致命报错）。
	# pause() 之后 is_playing() 返回 false，所以下面的 play() 分支就是"恢复播放"。
	if sprite.animation == anim_name:
		if not sprite.is_playing():
			sprite.play()
	else:
		sprite.play(anim_name)


func freeze_frame(anim_name: StringName, frame: int) -> void:
	if not _has_anim(anim_name):
		return
	sprite.animation = anim_name
	sprite.frame = clampi(frame, 0, sprite.sprite_frames.get_frame_count(anim_name) - 1)
	sprite.pause()


func set_squash(x_scale: float, y_scale: float) -> void:
	if sprite == null:
		return
	sprite.scale = Vector2(_sprite_base_scale.x * x_scale, _sprite_base_scale.y * y_scale)
	_squash_offset = Vector2(0.0, _squash_anchor_y * (1.0 - y_scale))
	_refresh_sprite_position()


## sprite.position 的唯一写入口：基准位 + 挤压偏移 + 攻击轴心偏移。
func _refresh_sprite_position() -> void:
	if sprite == null:
		return
	sprite.position = _sprite_base_position + _squash_offset + _attack_pivot_offset


## 上挑/下劈绕"脚底点"旋转，而不是绕 sprite 中心（绕中心会把身体甩出去，视觉悬空/穿地）。
## 脚底在父坐标系是 f=(0, _squash_anchor_y)；要让脚底旋转后不动，中心需 c = f - R(θ)·f。
## 脚底 x=0，所以 flip_h 的镜像不影响该补偿。
func _set_attack_rotation(angle: float) -> void:
	if sprite == null:
		return
	sprite.rotation = angle
	if is_zero_approx(angle):
		_attack_pivot_offset = Vector2.ZERO
	else:
		var foot := Vector2(0.0, _squash_anchor_y)
		_attack_pivot_offset = foot - foot.rotated(angle)
	_refresh_sprite_position()


func reset_squash() -> void:
	_kill_tween(_squash_tween)
	set_squash(1.0, 1.0)


func play_land_squash() -> void:
	if sprite == null:
		return
	_kill_tween(_squash_tween)
	set_squash(1.22, 0.78)
	_squash_tween = create_tween()
	_squash_tween.tween_method(_squash_lerp, 0.0, 1.0, 0.12)


func _squash_lerp(t: float) -> void:
	set_squash(lerpf(1.22, 1.0, t), lerpf(0.78, 1.0, t))


func _tick_timers(delta: float) -> void:
	if is_on_floor() and velocity.y >= 0.0:
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)
	jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

	if _jump_cut_requested:
		_jump_cut_requested = false
		if velocity.y < 0.0 and not _is_dashing:
			velocity.y *= JUMP_CUT_MULT

	if _invuln_timer > 0.0:
		_invuln_timer = maxf(_invuln_timer - delta, 0.0)
		_blink_on = fmod(_invuln_timer, BLINK_PERIOD) >= BLINK_PERIOD * 0.5
		if _invuln_timer <= 0.0:
			_blink_on = true
	_hurt_flash_timer = maxf(_hurt_flash_timer - delta, 0.0)

	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_on_landed()
	_was_on_floor = on_floor


func _on_landed() -> void:
	if _is_dead:
		return
	reset_dashes()
	play_land_squash()


func _update_sprite_modulate() -> void:
	if _is_dead:
		return
	var color := Color.WHITE
	if _is_dashing:
		color = DASH_GLOW
	if _hurt_flash_timer > 0.0:
		color = HURT_FLASH
	if _invuln_timer > 0.0 and not _blink_on:
		color.a = BLINK_ALPHA
	sprite.modulate = color


# --- interact（契约 §11.2）---

func _try_interact() -> void:
	var shape := CircleShape2D.new()
	shape.radius = INTERACT_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = INTERACT_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hits := get_world_2d().direct_space_state.intersect_shape(query, 8)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider is Area2D and (collider as Area2D).is_in_group("interactable"):
			if collider.has_method("interact"):
				(collider as Node).call("interact")
				break


# --- 初始化 ---

func _build_sprite_frames() -> void:
	var anim_dirs := {
		"idle": {"dir": SPRITE_ROOT + "idle", "fps": 8, "loop": true},
		"walk": {"dir": SPRITE_ROOT + "walk", "fps": 10, "loop": true},
		"run": {"dir": SPRITE_ROOT + "run", "fps": 12, "loop": true},
		"attack1": {"dir": SPRITE_ROOT + "attack1", "fps": 12, "loop": false},
		"attack2": {"dir": SPRITE_ROOT + "attack2", "fps": 12, "loop": false},
	}
	var frames := SpriteFramesBuilder.build(anim_dirs)
	for anim_name: StringName in [&"attack1", &"attack2"]:
		if frames.has_animation(anim_name):
			frames.set_animation_loop_mode(anim_name, SpriteFrames.LOOP_NONE)
	sprite.sprite_frames = frames


func _cache_sprite_layout() -> void:
	_sprite_base_scale = sprite.scale
	_sprite_base_position = sprite.position
	var frame_height := 0.0
	if sprite.sprite_frames != null:
		for anim_name: StringName in [&"idle", &"walk", &"run"]:
			if sprite.sprite_frames.has_animation(anim_name) \
					and sprite.sprite_frames.get_frame_count(anim_name) > 0:
				var texture := sprite.sprite_frames.get_frame_texture(anim_name, 0)
				if texture != null:
					frame_height = float(texture.get_height())
					break
	_squash_anchor_y = frame_height * 0.5 * _sprite_base_scale.y if sprite.centered else 0.0


func _cache_attack_hitbox() -> void:
	var shape_node := attack_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var shape_offset := Vector2.ZERO
	if shape_node != null:
		shape_offset = shape_node.position
		shape_node.position = Vector2.ZERO
	_attack_hitbox_base_offset = attack_hitbox.position + shape_offset
	if _attack_hitbox_base_offset.is_zero_approx():
		_attack_hitbox_base_offset = ATTACK_HITBOX_FALLBACK_OFFSET
	_place_attack_hitbox(AttackDirection.HORIZONTAL)
	attack_hitbox.set_active(false)
	var target_group: Variant = attack_hitbox.get("target_group")
	if target_group == null or str(target_group).is_empty():
		attack_hitbox.set("target_group", &"enemy")


func _wire_components() -> void:
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)
	if hurtbox.health_component == null:
		hurtbox.health_component = health_component
	attack_hitbox.hit_landed.connect(_on_attack_hit_landed)


func _has_anim(anim_name: StringName) -> bool:
	if sprite == null or sprite.sprite_frames == null:
		return false
	if not sprite.sprite_frames.has_animation(anim_name):
		return false
	# 0 帧动画（空目录/加载失败）视为没有该动画，避免 play() 后卡住
	return sprite.sprite_frames.get_frame_count(anim_name) > 0


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
