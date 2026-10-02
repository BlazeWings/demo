class_name PlayerHurtState
extends PlayerState


var _timer: float = 0.0


func enter() -> void:
	_timer = 0.0
	player.freeze_frame(&"idle", 0)


func physics_update(delta: float) -> String:
	_timer += delta
	player.apply_gravity(delta)
	if player.is_on_floor():
		player.apply_horizontal_brake(delta)
	player.move_and_slide()
	if _timer >= Player.HURT_STATE_TIME:
		if player.is_on_floor():
			return PlayerStateMachine.IDLE
		return PlayerStateMachine.FALL
	return ""
