class_name PlayerStateMachine
extends Node

## 玩家状态机（契约 §4）。states 以子节点名称为键；节点名必须等于下面九个常量之一。
## 由 Player._ready() 末尾调用 start()，确保状态 enter() 时玩家节点已初始化完毕。

const IDLE := "Idle"
const MOVE := "Move"
const JUMP := "Jump"
const FALL := "Fall"
const DASH := "Dash"
const ATTACK := "Attack"
const HEAL := "Heal"
const HURT := "Hurt"
const DEAD := "Dead"

@export var initial_state: PlayerState

var player: Player
var current_state: PlayerState
var states: Dictionary = {}


func _ready() -> void:
	player = owner as Player
	if player == null:
		player = get_parent() as Player
	for child in get_children():
		if child is PlayerState:
			var state := child as PlayerState
			states[state.name] = state
			state.player = player
	if initial_state == null and states.has(IDLE):
		initial_state = states[IDLE]


func start() -> void:
	if player == null:
		push_error("PlayerStateMachine: player 未接线（应为父节点 Player），状态机未启动")
		return
	if current_state != null or initial_state == null:
		return
	current_state = initial_state
	current_state.enter()


func _physics_process(delta: float) -> void:
	if current_state == null or player == null:
		return
	var next := current_state.physics_update(delta)
	if not next.is_empty():
		transition_to(next)
	player.clear_input_requests()


func transition_to(state_name: String) -> void:
	if not states.has(state_name):
		push_error("PlayerStateMachine: 未知状态 '%s'" % state_name)
		return
	var next := states[state_name] as PlayerState
	if next == null or next == current_state:
		return
	if current_state != null:
		current_state.exit()
	current_state = next
	current_state.enter()
