class_name PlayerDashState
extends PlayerState


var _timer: float = 0.0


func enter() -> void:
	_timer = 0.0
	player.begin_dash()


func exit() -> void:
	player.end_dash()


func physics_update(delta: float) -> String:
	_timer += delta
	player.velocity = Vector2(Player.DASH_SPEED * float(player.facing), 0.0)
	player.move_and_slide()
	if _timer >= Player.DASH_DURATION:
		return landing_state()
	return ""


func landing_state() -> String:
	if not player.is_on_floor():
		return PlayerStateMachine.FALL
	if is_zero_approx(player.input_x):
		return PlayerStateMachine.IDLE
	return PlayerStateMachine.MOVE
