extends Node

signal soul_changed(value: int)

const MAX_SOUL: int = 99

var soul: int = 0
var _respawn: Vector2 = Vector2.ZERO


func add_soul(amount: int = 1) -> void:
	soul = clampi(soul + amount, 0, MAX_SOUL)
	soul_changed.emit(soul)


func try_consume_soul(amount: int) -> bool:
	if amount <= 0:
		return true
	if soul < amount:
		return false
	soul -= amount
	soul_changed.emit(soul)
	return true


func set_respawn(position: Vector2) -> void:
	_respawn = position


func get_respawn() -> Vector2:
	return _respawn
