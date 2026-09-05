extends SceneTree
## 独立无界面服务器入口；服务器没有玩家席位。

const Network = preload("res://src/network/room_network.gd")


func _initialize() -> void:
	call_deferred("_start")


func _start() -> void:
	var port: int = 27840
	var single_cat: bool = false
	var bind_address: String = "*"
	var ready_file: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument == "--single-cat":
			single_cat = true
		elif argument.begins_with("--port="):
			var value := argument.trim_prefix("--port=")
			if not value.is_valid_int():
				printerr("ERROR: Invalid server port")
				quit(1)
				return
			port = value.to_int()
		elif argument.begins_with("--bind="):
			bind_address = argument.trim_prefix("--bind=")
		elif argument.begins_with("--ready-file="):
			ready_file = argument.trim_prefix("--ready-file=")
	var network := root.get_node_or_null("RoomNetwork")
	if network == null:
		network = Network.new()
		network.name = "RoomNetwork"
		root.add_child(network)
	var result: Error = network.start_server(port, single_cat, bind_address)
	if result != OK:
		printerr("ERROR: Server could not bind port %d: %s" % [port, error_string(result)])
		quit(1)
		return
	if not ready_file.is_empty():
		var file := FileAccess.open(ready_file, FileAccess.WRITE)
		if file == null:
			printerr("ERROR: Cannot write server readiness file")
			quit(1)
			return
		file.store_string(JSON.stringify({"pid": OS.get_process_id(), "port": port, "single_cat": single_cat}))
		file.close()
	print("SERVER_READY port=%d mode=%s pid=%d" % [port, "single_cat_debug" if single_cat else "three_players", OS.get_process_id()])
