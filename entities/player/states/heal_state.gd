class_name PlayerHealState
extends PlayerState


var _timer: float = 0.0


func enter() -> void:
	_timer = 0.0
	player.begin_heal()


func exit() -> void:
	player.end_heal()


func physics_update(delta: float) -> String:
	_timer += delta
	player.apply_gravity(delta)
	player.apply_horizontal_brake(delta)
	player.move_and_slide()
	if not player.is_on_floor():
		return PlayerStateMachine.FALL
	if _timer >= Player.HEAL_CHARGE_TIME:
		player.finish_heal()
		return PlayerStateMachine.IDLE
	return ""
