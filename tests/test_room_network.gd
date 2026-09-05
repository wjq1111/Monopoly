extends SceneTree
## 真正的独立Godot服务器与同机ENet客户端；不代表三台设备或GUI验收。
## 来源：策划“联机流程”“初始数值”，以及用户本轮授权的显式单猫调试。
const Network = preload("res://src/network/room_network.gd")
var results: Array[Dictionary] = []
var clients: Array[Node] = []
var children: Array[int] = []
var errors: Dictionary = {}
var folder: String
var port: int = 27942

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = argument.trim_prefix("--port=").to_int()
	folder = ProjectSettings.globalize_path("res://.artifacts/network-tests/run-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	await _normal()
	await _single()
	await _owned()
	await _lobby_release()
	await _connection_timeout()
	for client in clients:
		client.disconnect_from_server()
	for pid in children:
		if OS.is_process_running(pid):
			OS.kill(pid)
	var failures: int = 0
	for result in results:
		if not result["passed"]:
			failures += 1
	var file := FileAccess.open(folder.path_join("results.json"), FileAccess.WRITE)
	if file == null:
		printerr("ERROR: Cannot write network results")
		quit(1)
		return
	file.store_string(JSON.stringify({"engine": Engine.get_version_info()["string"], "scope": "独立Godot服务器+同机ENet；非真实三机或GUI验收", "assertions": results, "failures": failures}, "  "))
	file.close()
	print("NETWORK_RESULT=" + folder)
	print("NETWORK_CHECKS %s: %d assertions" % ["PASSED" if failures == 0 else "FAILED", results.size()])
	quit(0 if failures == 0 else 1)

func _server(server_port: int, single: bool) -> bool:
	var ready := folder.path_join("ready-%d.json" % server_port)
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", folder.path_join("server-%d.log" % server_port), "--script", "res://src/network/server_main.gd", "--", "--bind=127.0.0.1", "--port=%d" % server_port, "--ready-file=" + ready])
	if single:
		args.append("--single-cat")
	var pid := OS.create_process(OS.get_executable_path(), args, false)
	_check("NET-START", pid > 0, "启动独立隐藏服务器", pid)
	if pid < 1:
		return false
	children.append(pid)
	var ok: bool = await _until(func() -> bool: return FileAccess.file_exists(ready) or not OS.is_process_running(pid))
	ok = ok and FileAccess.file_exists(ready) and OS.is_process_running(pid)
	_check("NET-START", ok, "服务器真正绑定端口并写入就绪文件", server_port)
	return ok

func _client(label: String) -> Node:
	var branch := Node.new()
	branch.name = label
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var client := Network.new()
	client.name = "RoomNetwork"
	branch.add_child(client)
	clients.append(client)
	errors[label] = []
	client.command_failed.connect(func(message: String) -> void: errors[label].append(message))
	return client

func _normal() -> void:
	if not await _server(port, false):
		return
	var a := _client("A")
	a.connect_to_server("127.0.0.1", port)
	if not await _players(a, 1):
		return
	_check("NET-001", a.get_local_peer_id() > 1, "服务器不占玩家席位")
	a.choose_character(&"nainiu")
	await _until(func() -> bool: return _own(a).get("character_id") == "nainiu")
	a.set_ready(true)
	await _until(func() -> bool: return _own(a).get("ready", false))
	a.request_start()
	await _rejected("A")
	_check("NET-001", a.get_snapshot()["phase"] == "lobby", "正常模式一人不能开局")
	var b := _client("B")
	var c := _client("C")
	b.connect_to_server("127.0.0.1", port)
	c.connect_to_server("127.0.0.1", port)
	if not await _players(a, 3) or not await _players(b, 3) or not await _players(c, 3):
		return
	b.choose_character(&"nainiu")
	await _rejected("B")
	_check("NET-002", _own(b)["character_id"] == "", "服务器拒绝重复角色")
	b.choose_character(&"sanhua")
	await _until(func() -> bool: return _own(b).get("character_id") == "sanhua")
	c.choose_character(&"buou")
	await _until(func() -> bool: return a.get_snapshot().get("selection_order", []) == ["nainiu", "sanhua", "buou"])
	_check("NET-002", a.get_snapshot()["selection_order"] == ["nainiu", "sanhua", "buou"], "选择顺序由服务器保存")
	b.set_ready(true)
	await _until(func() -> bool: return _own(b).get("ready", false))
	var spoof_command: int = int(a.get("_next_command")) + 1
	a.set("_next_command", spoof_command)
	a.rpc_id(1, &"_submit_command", spoof_command, "set_ready", {"ready": false, "peer_id": b.get_local_peer_id()})
	var sender_checked: bool = await _until(func() -> bool: return not _own(a).get("ready", true))
	_check("NET-010", sender_checked and _own(b).get("ready", false), "RPC载荷不能冒充其他玩家，准备状态只改发送者")
	a.set_ready(true)
	await _until(func() -> bool: return _own(a).get("ready", false))
	errors["A"].clear()
	a.request_start()
	await _rejected("A")
	_check("NET-003", a.get_snapshot()["phase"] == "lobby", "未全员准备不能开局")
	c.set_ready(true)
	await _until(func() -> bool: return _own(c).get("ready", false))
	a.request_start()
	var ok: bool = await _until(func() -> bool: return a.get_snapshot().get("phase") == "board" and b.get_snapshot().get("phase") == "board" and c.get_snapshot().get("phase") == "board")
	_check("NET-003", ok, "三人选角并准备后进入棋盘")
	_check("NET-003", a.get_snapshot() == b.get_snapshot() and b.get_snapshot() == c.get_snapshot(), "三份ENet客户端共享同一状态")
	for player: Dictionary in a.get_snapshot()["players"]:
		_check("NET-003", player["level"] == 1 and player["wildness"] == 0 and player["satiety_units"] == 6 and player["satiety_cap_units"] == 10 and player["tile_id"] == 1, "保留已确认初值和预览落点", player)
	errors["A"].clear()
	a.request_debug_move(29)
	await _rejected("A")
	_check("NET-004", _own(a)["tile_id"] == 1, "普通三人模式禁止单猫调试移动")
	errors["A"].clear()
	a.request_story_demo()
	await _rejected("A")
	_check("NET-004", a.get_snapshot()["story"].is_empty(), "普通三人模式禁止调试剧情入口")
	c.disconnect_from_server()
	ok = await _until(func() -> bool: return not a.get_snapshot().get("waiting_reason", "").is_empty())
	_check("NET-005", ok and a.get_snapshot()["players"].size() == 3, "开局后掉线保留角色且保持等待")
	a.disconnect_from_server()
	b.disconnect_from_server()

func _single() -> void:
	if not await _server(port + 1, true):
		return
	var a := _client("Single")
	a.connect_to_server("127.0.0.1", port + 1)
	if not await _players(a, 1):
		return
	a.choose_character(&"buou")
	await _until(func() -> bool: return _own(a).get("character_id") == "buou")
	a.set_ready(true)
	await _until(func() -> bool: return _own(a).get("ready", false))
	a.request_start()
	var ok: bool = await _until(func() -> bool: return a.get_snapshot().get("phase") == "board")
	_check("NET-006", ok and a.get_snapshot()["mode"] == "single_cat_debug", "显式单猫模式可一猫进入棋盘")
	for tile in [0, 30]:
		errors["Single"].clear()
		a.request_debug_move(tile)
		await _rejected("Single")
		_check("NET-006", _own(a)["tile_id"] == 1, "拒绝范围外格子", tile)
	a.request_debug_move(29)
	await _until(func() -> bool: return _own(a).get("tile_id") == 29)
	_check("NET-006", _own(a)["tile_id"] == 29, "有效调试落点由服务器更新")
	var revision: int = a.get_snapshot()["revision"]
	a.rpc_id(1, &"_submit_command", int(a.get("_next_command")), "debug_move", {"tile_id": 2})
	await create_timer(0.15).timeout
	_check("NET-007", a.get_snapshot()["revision"] == revision and _own(a)["tile_id"] == 29, "重放命令编号不重复结算")
	a.request_story_demo()
	await _until(func() -> bool: return not a.get_snapshot().get("story", {}).is_empty())
	var story: Dictionary = a.get_snapshot()["story"]
	_check("NET-008", story.get("lines", []).size() == 4, "共同剧情预览有四段原稿摘要")
	if not story.is_empty():
		errors["Single"].clear()
		a.request_debug_move(2)
		await _rejected("Single")
		_check("NET-008", _own(a)["tile_id"] == 29, "共同阅读期间不能调试移动")
		a.mark_story_read(story["id"])
		await _until(func() -> bool: return a.get_snapshot().get("story", {}).is_empty())
		revision = a.get_snapshot()["revision"]
		a.mark_story_read(story["id"])
		await create_timer(0.15).timeout
		_check("NET-008", a.get_snapshot()["story"].is_empty() and a.get_snapshot()["revision"] == revision and _own(a)["tile_id"] == 29 and _own(a)["wildness"] == 0, "看完关闭剧情，重复确认不发奖励或移动")
	a.disconnect_from_server()

func _owned() -> void:
	var a := _client("Owned")
	a.start_local_debug_server(port + 2)
	var ok: bool = await _until(func() -> bool: return not a.get_snapshot().is_empty(), 8000)
	_check("NET-009", ok, "客户端启动自有隐藏服务器并连接")
	var pid: int = a.get("_owned_server_pid")
	_check("NET-009", pid > 0 and OS.is_process_running(pid), "自有进程实际存活")
	a.disconnect_from_server()
	await create_timer(0.2).timeout
	_check("NET-009", pid > 0 and not OS.is_process_running(pid), "退出只停止自建服务器")
	a.start_local_debug_server(port + 2)
	var pending_pid: int = a.get("_owned_server_pid")
	a.connect_to_server("127.0.0.1", port)
	await create_timer(0.3).timeout
	_check("NET-012", pending_pid > 0 and not OS.is_process_running(pending_pid) and int(a.get("_owned_server_pid")) == -1 and a.get_connection_status() != "starting_local_server", "切换连接取消正在启动的自有服务，不会稍后覆盖用户连接")
	a.disconnect_from_server()

func _lobby_release() -> void:
	if not await _server(port + 3, false):
		return
	var a := _client("LeaveA")
	var b := _client("LeaveB")
	a.connect_to_server("127.0.0.1", port + 3)
	b.connect_to_server("127.0.0.1", port + 3)
	if not await _players(a, 2) or not await _players(b, 2):
		return
	a.choose_character(&"buou")
	await _until(func() -> bool: return _own(a).get("character_id") == "buou")
	a.disconnect_from_server()
	var ok: bool = await _players(b, 1)
	_check("NET-011", ok and b.get_snapshot()["selection_order"].is_empty(), "开局前退出释放席位及选角顺序")
	b.choose_character(&"buou")
	ok = await _until(func() -> bool: return _own(b).get("character_id") == "buou")
	_check("NET-011", ok and b.get_snapshot()["selection_order"] == ["buou"], "留下的玩家可选择已释放角色")
	b.disconnect_from_server()

func _connection_timeout() -> void:
	var a := _client("Timeout")
	a.set("_connection_timeout_seconds", 0.25)
	errors["Timeout"].clear()
	a.connect_to_server("127.0.0.1", port + 4)
	var ok: bool = await _until(func() -> bool: return a.get_connection_status() == "connection_failed")
	var timeout_received: bool = false
	for message: String in errors["Timeout"]:
		timeout_received = timeout_received or message.contains("连接超时")
	_check("NET-013", ok and timeout_received and a.get_snapshot().is_empty() and a.get_local_peer_id() == 0, "无服务时在显式建连期限后失败并提示重试")
	a.set("_connection_timeout_seconds", 0.5)
	a.connect_to_server("127.0.0.1", port + 4)
	await create_timer(0.1).timeout
	a.connect_to_server("127.0.0.1", port + 3)
	ok = await _players(a, 1)
	await create_timer(0.55).timeout
	_check("NET-014", ok and a.get_connection_status() == "connected" and a.get_snapshot().get("players", []).size() == 1, "改连成功后，旧连接计时器不会关闭新peer，已连接也不再超时")
	a.disconnect_from_server()

func _players(client: Node, count: int) -> bool:
	var ok: bool = await _until(func() -> bool: return client.get_snapshot().get("players", []).size() == count)
	_check("NET-CONNECT", ok, "真实ENet客户端收到预期人数", count)
	return ok

func _own(client: Node) -> Dictionary:
	for player: Dictionary in client.get_snapshot().get("players", []):
		if player["peer_id"] == client.get_local_peer_id():
			return player
	return {}

func _rejected(label: String) -> bool:
	var ok: bool = await _until(func() -> bool: return not errors[label].is_empty())
	_check("NET-REJECT", ok, "客户端收到服务器拒绝原因", errors[label].duplicate())
	return ok

func _until(condition: Callable, timeout: int = 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await create_timer(0.025).timeout
	return false

func _check(case_id: String, passed: bool, detail: String, actual: Variant = null) -> void:
	results.append({"case_id": case_id, "passed": passed, "detail": detail, "actual": actual})
	if not passed:
		printerr("FAIL: %s: %s" % [case_id, detail])
