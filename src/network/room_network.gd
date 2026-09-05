extends Node
## 客户端与独立服务器共享RPC路径 /root/RoomNetwork；只有服务器可以写入房间状态。

signal snapshot_changed(state: Dictionary)
signal connection_state_changed(status: String)
signal command_failed(message: String)

const RoomState = preload("res://src/network/room_state.gd")
const DEFAULT_PORT: int = 27840

var _snapshot: Dictionary = {}
var _connection_status: String = "disconnected"
var _server: bool = false
var _room: RefCounted
var _last_commands: Dictionary = {}
var _next_command: int = 0
var _owned_server_pid: int = -1
var _startup_generation: int = 0
var _connection_timeout_seconds: float = 10.0
var _connection_timer: Timer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_server(port: int = DEFAULT_PORT, single_cat: bool = false, bind_address: String = "*") -> Error:
	if port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	_close_peer()
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_address)
	var result := peer.create_server(port, 1 if single_cat else 3)
	if result != OK:
		return result
	_server = true
	_room = RoomState.new(single_cat)
	_last_commands.clear()
	multiplayer.multiplayer_peer = peer
	_set_status("server_running")
	_snapshot = _room.get_snapshot()
	snapshot_changed.emit(get_snapshot())
	return OK


func connect_to_server(host: String, port: int) -> void:
	if _server:
		command_failed.emit("服务器进程不能占用玩家席位。")
		return
	if host.strip_edges().is_empty() or port < 1 or port > 65535:
		command_failed.emit("请填写有效服务器地址和端口。")
		return
	_startup_generation += 1
	_stop_owned_server()
	_connect(host, port)


func _connect(host: String, port: int) -> void:
	_close_peer()
	_snapshot = {}
	_next_command = 0
	snapshot_changed.emit(get_snapshot())
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(host.strip_edges(), port)
	if result != OK:
		_set_status("connection_failed")
		command_failed.emit("无法创建连接：%s" % error_string(result))
		return
	multiplayer.multiplayer_peer = peer
	_set_status("connecting")
	_connection_timer = Timer.new()
	_connection_timer.one_shot = true
	add_child(_connection_timer)
	_connection_timer.timeout.connect(_on_connection_timeout.bind(_startup_generation, peer))
	_connection_timer.start(_connection_timeout_seconds)


func _on_connection_timeout(generation: int, peer: ENetMultiplayerPeer) -> void:
	if generation != _startup_generation or multiplayer.multiplayer_peer != peer:
		return
	if _connection_status != "connecting":
		return
	_close_peer()
	_set_status("connection_failed")
	command_failed.emit("连接超时，请检查服务器地址、端口和服务状态后重试。")


func choose_character(id: StringName) -> void:
	_send("choose_character", {"character_id": String(id)})


func set_ready(value: bool) -> void:
	_send("set_ready", {"ready": value})


func request_start() -> void:
	_send("request_start", {})


func request_debug_move(tile_id: int) -> void:
	_send("debug_move", {"tile_id": tile_id})


func request_story_demo() -> void:
	_send("story_demo", {})


func mark_story_read(story_id: String) -> void:
	_send("story_read", {"story_id": story_id})


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_local_peer_id() -> int:
	if _connection_status != "connected":
		return 0
	return multiplayer.get_unique_id()


func get_connection_status() -> String:
	return _connection_status


func disconnect_from_server() -> void:
	_startup_generation += 1
	_close_peer()
	_stop_owned_server()
	_snapshot = {}
	_set_status("disconnected")
	snapshot_changed.emit(get_snapshot())


func start_local_debug_server(port: int = DEFAULT_PORT) -> void:
	if port < 1 or port > 65535:
		command_failed.emit("端口必须为 1–65535。")
		return
	if not OS.has_feature("editor"):
		command_failed.emit("本地调试启动目前仅支持工程运行；导出包尚未验收。")
		return
	disconnect_from_server()
	var generation := _startup_generation
	var directory := ProjectSettings.globalize_path("res://.artifacts/server/local-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var ready_path := directory.path_join("ready.json")
	var arguments := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", directory.path_join("server.log"),
		"--script", "res://src/network/server_main.gd", "--",
		"--port=%d" % port, "--single-cat", "--bind=127.0.0.1", "--ready-file=" + ready_path,
	])
	_owned_server_pid = OS.create_process(OS.get_executable_path(), arguments, false)
	if _owned_server_pid < 0:
		_set_status("connection_failed")
		command_failed.emit("无法启动本地调试服务器。")
		return
	_set_status("starting_local_server")
	for _attempt in range(60):
		await get_tree().create_timer(0.1).timeout
		if generation != _startup_generation:
			return
		if not OS.is_process_running(_owned_server_pid):
			_owned_server_pid = -1
			_set_status("connection_failed")
			command_failed.emit("本地服务器提前退出；端口可能已被占用。日志：" + directory)
			return
		if FileAccess.file_exists(ready_path):
			var ready: Variant = JSON.parse_string(FileAccess.get_file_as_string(ready_path))
			if ready is Dictionary and int(ready.get("pid", -1)) == _owned_server_pid:
				_connect("127.0.0.1", port)
				return
	_stop_owned_server()
	_set_status("connection_failed")
	command_failed.emit("本地服务器未在规定时间内就绪。日志：" + directory)


func _send(action: String, payload: Dictionary) -> void:
	if _server or _connection_status != "connected":
		command_failed.emit("当前没有连接到可操作的房间。")
		return
	_next_command += 1
	_submit_command.rpc_id(1, _next_command, action, payload)


@rpc("any_peer", "call_remote", "reliable")
func _submit_command(command_id: int, action: String, payload: Dictionary) -> void:
	if not _server:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not multiplayer.get_peers().has(sender):
		return
	if command_id < 1:
		_receive_error.rpc_id(sender, "命令编号无效。")
		return
	if command_id <= int(_last_commands.get(sender, 0)):
		_receive_snapshot.rpc_id(sender, _room.get_snapshot())
		return
	_last_commands[sender] = command_id
	var result: Dictionary = _room.apply_command(sender, action, payload)
	if not result["error"].is_empty():
		_receive_error.rpc_id(sender, result["error"])
	elif result["changed"]:
		_broadcast_snapshot()


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(state: Dictionary) -> void:
	if _server or multiplayer.get_remote_sender_id() != 1:
		return
	if not _snapshot.is_empty() and int(state.get("revision", -1)) < int(_snapshot.get("revision", -1)):
		return
	_snapshot = state.duplicate(true)
	snapshot_changed.emit(get_snapshot())


@rpc("authority", "call_remote", "reliable")
func _receive_error(message: String) -> void:
	if not _server and multiplayer.get_remote_sender_id() == 1:
		command_failed.emit(message)


func _on_peer_connected(peer_id: int) -> void:
	if not _server:
		return
	var message: String = _room.join(peer_id)
	if not message.is_empty():
		_receive_error.rpc_id(peer_id, message)
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	_broadcast_snapshot()


func _on_peer_disconnected(peer_id: int) -> void:
	if _server and _room.leave(peer_id):
		_last_commands.erase(peer_id)
		_broadcast_snapshot()


func _on_connected() -> void:
	_cancel_connection_timer()
	_set_status("connected")


func _on_connection_failed() -> void:
	_close_peer()
	_set_status("connection_failed")
	command_failed.emit("连接失败，请检查服务器地址、端口和服务状态。")


func _on_server_disconnected() -> void:
	_close_peer()
	_set_status("server_disconnected")
	command_failed.emit("与服务器断开，当前进度保持显示；自动重连与恢复尚未实现。")


func _broadcast_snapshot() -> void:
	_snapshot = _room.get_snapshot()
	for peer_id in multiplayer.get_peers():
		_receive_snapshot.rpc_id(peer_id, _snapshot)
	snapshot_changed.emit(get_snapshot())


func _set_status(status: String) -> void:
	_connection_status = status
	connection_state_changed.emit(status)


func _cancel_connection_timer() -> void:
	if is_instance_valid(_connection_timer):
		_connection_timer.stop()
		_connection_timer.queue_free()
		_connection_timer = null


func _close_peer() -> void:
	_cancel_connection_timer()
	var peer := multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _stop_owned_server() -> void:
	if _owned_server_pid > 0 and OS.is_process_running(_owned_server_pid):
		OS.kill(_owned_server_pid)
	_owned_server_pid = -1


func _exit_tree() -> void:
	_startup_generation += 1
	_close_peer()
	_stop_owned_server()
