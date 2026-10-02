class_name PlayerDeadState
extends PlayerState


var _timer: float = 0.0


func enter() -> void:
	_timer = 0.0
	player.on_death_started()


func physics_update(delta: float) -> String:
	_timer += delta
	player.velocity.x = 0.0
	player.apply_gravity(delta)
	player.move_and_slide()
	if _timer >= Player.DEATH_TIME:
		player.respawn()
		return PlayerStateMachine.IDLE
	return ""
