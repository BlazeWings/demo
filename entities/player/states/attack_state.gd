class_name PlayerAttackState
extends PlayerState


var _timer: float = 0.0
var _hitbox_closed: bool = false
var _direction: int = Player.AttackDirection.HORIZONTAL


func enter() -> void:
	_timer = 0.0
	_hitbox_closed = false
	_direction = player.resolve_attack_direction()
	player.begin_attack(_direction)


func exit() -> void:
	player.end_attack()


func physics_update(delta: float) -> String:
	_timer += delta
	if not _hitbox_closed and _timer >= Player.ATTACK_ACTIVE_TIME:
		_hitbox_closed = true
		player.deactivate_attack_hitbox()
	player.apply_gravity(delta)
	if player.is_on_floor():
		player.apply_horizontal_brake(delta)
	player.move_and_slide()
	if _timer >= Player.ATTACK_TOTAL_TIME:
		if player.is_on_floor():
			return PlayerStateMachine.IDLE
		return PlayerStateMachine.FALL
	return ""
