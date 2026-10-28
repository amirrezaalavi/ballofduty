class_name InputHandler
extends Node
## Samples the InputMap exactly once per simulation tick. Only the locally
## controlled player has this component; the server feeds network frames into
## LocomotionComponent instead.

var sequence: int = 0


func sample(yaw: float, pitch: float) -> PlayerInputFrame:
	sequence += 1
	var frame := PlayerInputFrame.new()
	frame.seq = sequence
	frame.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	frame.jump = Input.is_action_just_pressed("jump")
	frame.sprint = Input.is_action_pressed("sprint")
	frame.aim = Input.is_action_pressed("aim")
	frame.fire = Input.is_action_pressed("fire")
	frame.yaw = yaw
	frame.pitch = pitch
	return frame
