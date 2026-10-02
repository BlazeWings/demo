class_name PlayerGroundedState
extends PlayerState

## Grounded 父层共享逻辑：重力 / 水平移动 / 通用转出（计划 v5「Grounded/Airborne 父层」）。
## IdleState、MoveState 继承它，只负责各自动画。


func physics_update(delta: float) -> String:
	var next := check_transitions()
	if not next.is_empty():
		return next
	player.apply_gravity(delta)
	player.apply_horizontal_move(delta)
	player.update_facing_from_input()
	player.move_and_slide()
	return poll_sub_state()


func check_transitions() -> String:
	if player.attack_requested:
		return PlayerStateMachine.ATTACK
	if player.heal_requested:
		return PlayerStateMachine.HEAL
	if player.dash_requested and player.can_dash():
		return PlayerStateMachine.DASH
	if player.jump_buffer_timer > 0.0:
		return PlayerStateMachine.JUMP
	if not player.is_on_floor():
		return PlayerStateMachine.FALL
	return ""


func poll_sub_state() -> String:
	if is_zero_approx(player.input_x):
		return PlayerStateMachine.IDLE
	return PlayerStateMachine.MOVE
