class_name Skeleton
extends CharacterBody2D

## 骷髅长枪兵（近战）：地面巡逻 → 前摇 → 突刺 → 收招，受击/死亡打断。
## 场景树契约（由关卡波次装配）：
##   $AnimatedSprite2D / $CollisionShape2D / $Components/HealthComponent
##   $Components/HurtboxComponent / $AttackHitbox(HitboxComponent) / $EdgeRay(RayCast2D) / $DeathParticles
## HP 由场景的 HealthComponent.max_health 决定（默认 3），脚本不写死。

enum State { PATROL, WINDUP, ATTACK, RECOVER, HURT, DEAD }

const SPRITE_DIR: String = "res://assets/sprites/enemies/skeleton/"
const ANIM_FPS: Dictionary = {"idle": 8, "walk": 10, "attack": 12, "hurt": 10, "dead": 6}
const NON_LOOPING_ANIMS: PackedStringArray = ["attack", "hurt", "dead"]

const COIN_TEXTURE_PATH: String = "res://assets/sprites/ui/coin.png"

## 位值：2^(层号-1)。enemy=2、terrain=4、hitbox=16、hurtbox=32
const BODY_LAYER: int = 2
const TERRAIN_MASK: int = 4
const HITBOX_LAYER: int = 16
const HURTBOX_MASK: int = 32

const WALK_SPEED: float = 40.0
const DETECT_RANGE_X: float = 100.0
const DETECT_RANGE_Y: float = 40.0

const WINDUP_TIME: float = 0.4
const WINDUP_SPEED_SCALE: float = 0.35
const LUNGE_SPEED: float = 400.0
const LUNGE_DISTANCE: float = 60.0
const ATTACK_TIME: float = 0.15
const RECOVER_TIME: float = 0.5

const HURT_TIME: float = 0.3
const KNOCKBACK_SPEED: float = 150.0
const KNOCKBACK_FRICTION: float = 400.0

const DEATH_FALLBACK_TIME: float = 1.5

## 1 = 素材默认朝右（flip_h=false 即朝右）；若素材实际朝左，改成 -1 即可。
## 场景里 $EdgeRay/$AttackHitbox 按“朝右”摆放，翻转时脚本会镜像它们的 x。
const ART_FACING: int = 1

@export var initial_facing_right: bool = true
## 以出生点为中心的巡逻半程（px）：PATROL 中超出这个范围就掉头回 home，
## 避免骷髅一路巡逻到玩家出生点（出生点 c12/x=400 → 只在 304~496 之间来回）。
@export var patrol_range: float = 96.0

var _state: State = State.PATROL
var _timer: float = 0.0
var _facing: int = 1
var _lunge_origin_x: float = 0.0
## 出生点 x，巡逻以此为界。
var _home_x: float = 0.0
var _player: Node2D = null

var _edge_base_x: float = 0.0
var _edge_target_x: float = 0.0
var _hitbox_base_x: float = 0.0
var _hit_shape_base_x: float = 0.0
var _hurtbox_detached: bool = false

@onready var _gravity: float = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _health: HealthComponent = $Components/HealthComponent
@onready var _hurtbox: HurtboxComponent = $Components/HurtboxComponent
@onready var _attack_hitbox: HitboxComponent = $AttackHitbox
@onready var _attack_shape: CollisionShape2D = _attack_hitbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var _edge_ray: RayCast2D = get_node_or_null("EdgeRay") as RayCast2D
@onready var _death_particles: CPUParticles2D = get_node_or_null("DeathParticles") as CPUParticles2D


func _ready() -> void:
	add_to_group(&"enemy")
	collision_layer = BODY_LAYER
	collision_mask = TERRAIN_MASK
	_facing = 1 if initial_facing_right else -1
	_home_x = global_position.x

	_build_sprites()
	_setup_edge_ray()
	_setup_attack_hitbox()
	_setup_hurtbox()
	_setup_death_particles()
	_apply_facing()

	if _health != null:
		_health.damaged.connect(_on_damaged)
		_health.died.connect(_on_died)
	_sprite.animation_finished.connect(_on_animation_finished)

	_enter_patrol()


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_timer = maxf(_timer - delta, 0.0)
	_apply_gravity(delta)
	match _state:
		State.PATROL:
			_tick_patrol()
		State.WINDUP:
			_tick_windup()
		State.ATTACK:
			_tick_attack()
		State.RECOVER:
			_tick_recover()
		State.HURT:
			_tick_hurt(delta)
	move_and_slide()
	_sync_hurtbox()


# --- 帧循环外的准备 ---

func _build_sprites() -> void:
	var anim_dirs: Dictionary = {}
	for anim_name: String in ANIM_FPS:
		anim_dirs[anim_name] = {"dir": SPRITE_DIR + anim_name, "fps": ANIM_FPS[anim_name]}
	var frames: SpriteFrames = SpriteFramesBuilder.build(anim_dirs)
	for anim_name: String in NON_LOOPING_ANIMS:
		if frames.has_animation(anim_name):
			frames.set_animation_loop(anim_name, false)
	_sprite.sprite_frames = frames


func _setup_edge_ray() -> void:
	if _edge_ray == null:
		return
	_edge_ray.enabled = true
	_edge_ray.collision_mask = TERRAIN_MASK
	_edge_base_x = absf(_edge_ray.position.x)
	_edge_target_x = absf(_edge_ray.target_position.x)


func _setup_attack_hitbox() -> void:
	if _attack_hitbox == null:
		return
	_hitbox_base_x = absf(_attack_hitbox.position.x)
	if _attack_shape != null:
		_hit_shape_base_x = absf(_attack_shape.position.x)
	_attack_hitbox.collision_layer = HITBOX_LAYER
	_attack_hitbox.collision_mask = HURTBOX_MASK
	_attack_hitbox.monitorable = false
	_attack_hitbox.set(&"target_mask", HURTBOX_MASK)
	_attack_hitbox.set(&"target_group", &"player")
	_attack_hitbox.set_active(false)


func _setup_hurtbox() -> void:
	if _hurtbox == null:
		return
	# Godot 陷阱：CanvasItem（Area2D）的直接父节点若是普通 Node，它的全局变换就不再继承
	# 上层 Node2D —— 物理世界里受击盒会停在原点，谁都打不中。契约里的 $Components 是普通 Node，
	# 所以这里兜底：提升为 top_level 并每帧同步本体变换（若场景用 Node2D 装配则不会触发）。
	_hurtbox_detached = not (_hurtbox.get_parent() is CanvasItem)
	if _hurtbox_detached:
		_hurtbox.top_level = true
		_sync_hurtbox()
		push_warning("Skeleton: HurtboxComponent 的直接父节点不是 CanvasItem，已用 top_level + 每帧同步兜底；建议把场景里的 Components 改成 Node2D")


func _sync_hurtbox() -> void:
	if _hurtbox_detached and _hurtbox != null and is_instance_valid(_hurtbox):
		_hurtbox.global_transform = global_transform


func _setup_death_particles() -> void:
	if _death_particles == null:
		return
	if _death_particles.texture == null:
		_death_particles.texture = load(COIN_TEXTURE_PATH) as Texture2D
	_death_particles.one_shot = true
	_death_particles.emitting = false


func _apply_facing() -> void:
	_sprite.flip_h = _facing * ART_FACING < 0
	if _edge_ray != null:
		_edge_ray.position.x = _edge_base_x * float(_facing)
		_edge_ray.target_position.x = _edge_target_x * float(_facing)
	if _attack_hitbox != null:
		_attack_hitbox.position.x = _hitbox_base_x * float(_facing)
		if _attack_shape != null:
			_attack_shape.position.x = _hit_shape_base_x * float(_facing)


func _flip() -> void:
	_facing = -_facing
	_apply_facing()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y += _gravity * delta


# --- 状态：进入 ---

func _enter_patrol() -> void:
	_state = State.PATROL
	_timer = 0.0
	_sprite.speed_scale = 1.0
	if _attack_hitbox != null:
		_attack_hitbox.set_active(false)
	_play_anim(&"walk")


func _enter_windup() -> void:
	_state = State.WINDUP
	_timer = WINDUP_TIME
	velocity.x = 0.0
	_sprite.speed_scale = WINDUP_SPEED_SCALE
	_play_anim(&"attack", true)


func _enter_attack() -> void:
	_state = State.ATTACK
	_timer = ATTACK_TIME
	_lunge_origin_x = global_position.x
	_sprite.speed_scale = 1.0
	_play_anim(&"attack")
	if _attack_hitbox != null:
		_attack_hitbox.set_active(true)


func _enter_recover() -> void:
	_state = State.RECOVER
	_timer = RECOVER_TIME
	velocity.x = 0.0
	_sprite.speed_scale = 1.0
	if _attack_hitbox != null:
		_attack_hitbox.set_active(false)
	_play_anim(&"idle", true)


func _enter_hurt(direction: int) -> void:
	_state = State.HURT
	_timer = HURT_TIME
	velocity.x = float(direction) * KNOCKBACK_SPEED
	_sprite.speed_scale = 1.0
	if _attack_hitbox != null:
		# 受击来自 HurtboxComponent→HealthComponent 的信号链，此刻正处于物理查询 flush 中，
		# 直接改 monitoring 会被引擎拒绝，必须延后一帧。
		_attack_hitbox.call_deferred(&"set_active", false)
	_play_anim(&"hurt", true)


func _enter_dead() -> void:
	_state = State.DEAD
	_timer = 0.0
	velocity = Vector2.ZERO
	_sprite.speed_scale = 1.0
	if _attack_hitbox != null:
		_attack_hitbox.call_deferred(&"set_active", false)
	_collision_shape.set_deferred(&"disabled", true)
	if _hurtbox != null:
		_hurtbox.set_deferred(&"monitoring", false)
		_hurtbox.set_deferred(&"monitorable", false)
	if _edge_ray != null:
		_edge_ray.set_deferred(&"enabled", false)
	if _death_particles != null:
		_death_particles.explosiveness = 1.0
		_death_particles.restart()
		_death_particles.emitting = true
	_play_anim(&"dead", true)
	get_tree().create_timer(DEATH_FALLBACK_TIME).timeout.connect(_on_death_timeout)


# --- 状态：每帧 ---

func _tick_patrol() -> void:
	velocity.x = float(_facing) * WALK_SPEED
	_play_anim(&"walk")
	if _player_in_front():
		_enter_windup()
		return
	if is_on_wall():
		_flip()
	elif is_on_floor() and not _edge_ray_has_ground():
		_flip()
	elif _beyond_patrol_range() and signf(_home_x - global_position.x) != float(_facing):
		_flip()


func _beyond_patrol_range() -> bool:
	return absf(global_position.x - _home_x) > patrol_range


func _tick_windup() -> void:
	velocity.x = 0.0
	if _timer <= 0.0:
		_enter_attack()


func _tick_attack() -> void:
	velocity.x = float(_facing) * LUNGE_SPEED
	if _timer <= 0.0 or absf(global_position.x - _lunge_origin_x) >= LUNGE_DISTANCE:
		_enter_recover()


func _tick_recover() -> void:
	velocity.x = 0.0
	if _timer <= 0.0:
		_enter_patrol()


func _tick_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, KNOCKBACK_FRICTION * delta)
	if _timer <= 0.0:
		_enter_patrol()


# --- 感知 ---

func _get_player() -> Node2D:
	if is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	_player = get_tree().get_first_node_in_group(&"player") as Node2D
	return _player


func _player_in_front() -> bool:
	var player: Node2D = _get_player()
	if player == null:
		return false
	var offset: Vector2 = player.global_position - global_position
	if absf(offset.x) >= DETECT_RANGE_X or absf(offset.y) >= DETECT_RANGE_Y:
		return false
	if is_zero_approx(offset.x):
		return true
	return signf(offset.x) == float(_facing)


func _edge_ray_has_ground() -> bool:
	if _edge_ray == null or not _edge_ray.enabled:
		return true
	_edge_ray.force_raycast_update()
	return _edge_ray.is_colliding()


# --- 信号回调 ---

func _on_damaged(_amount: int, source_position: Vector2) -> void:
	if _state == State.DEAD:
		return
	var away: float = signf(global_position.x - source_position.x)
	_enter_hurt(-1 if is_zero_approx(away) else int(away))


func _on_died() -> void:
	if _state == State.DEAD:
		return
	_enter_dead()


func _on_animation_finished() -> void:
	if _state == State.DEAD:
		queue_free()


func _on_death_timeout() -> void:
	if is_inside_tree() and _state == State.DEAD:
		queue_free()


# --- 表现 ---

func _play_anim(anim: StringName, restart: bool = false) -> void:
	if _sprite == null:
		return
	var frames: SpriteFrames = _sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		return
	if not restart and _sprite.animation == anim:
		return
	_sprite.play(anim)
