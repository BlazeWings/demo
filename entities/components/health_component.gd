class_name HealthComponent
extends Node

signal health_changed(current: int, maximum: int)
signal damaged(amount: int, source_position: Vector2)
signal healed(amount: int)
signal died()

@export var max_health: int = 5

var _health: int = 0
var _dead: bool = false


func _ready() -> void:
	_health = maxi(max_health, 0)


func take_damage(amount: int, source_position: Vector2 = Vector2.ZERO) -> void:
	if _dead or amount <= 0:
		return
	var applied: int = mini(amount, _health)
	_health -= applied
	damaged.emit(applied, source_position)
	health_changed.emit(_health, max_health)
	if _health <= 0:
		_dead = true
		died.emit()


func heal(amount: int) -> void:
	if _dead or amount <= 0:
		return
	var applied: int = mini(amount, max_health - _health)
	if applied <= 0:
		return
	_health += applied
	healed.emit(applied)
	health_changed.emit(_health, max_health)


func get_health() -> int:
	return _health


func reset_health() -> void:
	_health = maxi(max_health, 0)
	_dead = false
	health_changed.emit(_health, max_health)
