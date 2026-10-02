class_name HurtboxComponent
extends Area2D

signal hit_received(hitbox: HitboxComponent)

@export var health_component: HealthComponent

var _invulnerable: bool = false
var _invulnerability_token: int = 0


func _ready() -> void:
	collision_layer = 32
	collision_mask = 0
	monitoring = false
	monitorable = true
	if health_component == null:
		health_component = _find_health_component()
	if health_component == null:
		push_warning("HurtboxComponent on %s has no HealthComponent wired." % owner)


## 无敌中（受击后 1s / 危险区保护期）。纯增量查询，供 on_hazard 等判断。
func is_invulnerable() -> bool:
	return _invulnerable


func receive_hit(hitbox: HitboxComponent) -> void:
	if _invulnerable or hitbox == null or health_component == null:
		return
	health_component.take_damage(hitbox.damage, hitbox.global_position)
	hit_received.emit(hitbox)


func set_invulnerable(duration: float) -> void:
	if duration <= 0.0:
		return
	_invulnerable = true
	_invulnerability_token += 1
	var token: int = _invulnerability_token
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void:
		if token == _invulnerability_token:
			_invulnerable = false
	)


func _find_health_component() -> HealthComponent:
	var parent := get_parent()
	if parent != null:
		var sibling := parent.get_node_or_null("HealthComponent") as HealthComponent
		if sibling != null:
			return sibling
	if owner != null:
		return owner.get_node_or_null("Components/HealthComponent") as HealthComponent
	return null
