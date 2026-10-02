class_name Arrow
extends Area2D

## 弓手射出的箭矢：直线飞行，撞地形销毁，3s 兜底自毁，可被玩家攻击打落。
## 场景树契约：Arrow(Area2D) / $Sprite2D(texture=enemies/archer/arrow.png) /
##   $CollisionShape2D / $HitboxComponent(damage=1, mask=32, target_group="player")
## 箭头朝右绘制；朝左飞行时用 flip_v 抵消 180° 旋转造成的上下颠倒。

const SPEED: float = 260.0
const LIFETIME: float = 3.0
const ARROW_TEXTURE_PATH: String = "res://assets/sprites/enemies/archer/arrow.png"

## 位值：2^(层号-1)。terrain=4、projectile=64、hurtbox=32
const TERRAIN_MASK: int = 4
const PROJECTILE_LAYER: int = 64
const HURTBOX_MASK: int = 32

var _direction: Vector2 = Vector2.RIGHT
var _life: float = LIFETIME
var _launched: bool = false
var _destroyed: bool = false

@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var _hitbox: HitboxComponent = get_node_or_null("HitboxComponent") as HitboxComponent


func _ready() -> void:
	collision_layer = PROJECTILE_LAYER
	collision_mask = TERRAIN_MASK
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	_setup_sprite()
	_setup_hitbox()
	rotation = _direction.angle()


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_destroy()
		return
	if not _launched:
		return
	position += _direction * SPEED * delta


func launch(direction: Vector2) -> void:
	if direction.length_squared() > 0.0:
		_direction = direction.normalized()
	rotation = _direction.angle()
	if _sprite != null:
		_sprite.flip_v = _direction.x < 0.0
	if _hitbox != null:
		_hitbox.set_active(true)
	_launched = true


## 被玩家攻击打落（HitboxComponent 检测到本节点时调用）。
func on_shot_down() -> void:
	if _destroyed:
		return
	GameManager.add_soul(2)
	_destroy()


func get_direction() -> Vector2:
	return _direction


func _setup_sprite() -> void:
	if _sprite == null:
		return
	if _sprite.texture == null:
		_sprite.texture = load(ARROW_TEXTURE_PATH) as Texture2D


func _setup_hitbox() -> void:
	if _hitbox == null:
		return
	_hitbox.damage = 1
	_hitbox.collision_layer = 16
	_hitbox.collision_mask = HURTBOX_MASK
	_hitbox.monitorable = false
	_hitbox.set(&"target_mask", HURTBOX_MASK)
	_hitbox.set(&"target_group", &"player")
	_hitbox.set_active(false)
	if _hitbox.has_signal(&"hit_landed"):
		_hitbox.hit_landed.connect(_on_hit_landed)


func _on_hit_landed() -> void:
	_destroy()


func _on_body_entered(_body: Node2D) -> void:
	_destroy()


func _destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	set_physics_process(false)
	queue_free()
