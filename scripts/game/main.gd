extends Node3D
## Entry point. Client: load arena + local player. Headless: run authoritative
## server mode (transport lands in CP4a; CP0 only proves the headless boot path).

const DEFAULT_PORT := 9080


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--server"):
		_start_server(user_args)
	elif DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _start_server(args: PackedStringArray) -> void:
	var port := DEFAULT_PORT
	var port_index := args.find("--port")
	if port_index >= 0 and port_index + 1 < args.size():
		port = int(args[port_index + 1])

	# The headless server has no local viewer. It keeps the arena for collision
	# authority and will spawn player actors on join in CP4a.
	var local_player := get_node_or_null("Player")
	if local_player:
		local_player.queue_free()

	print("BALL_OF_DUTY server stub listening on port %d (transport arrives in CP4a)" % port)
