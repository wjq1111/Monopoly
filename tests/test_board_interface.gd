extends SceneTree
## TC-BOARD 的真实 Godot 图形输入检查；不调用游戏动作函数或发按钮信号。
const Report = preload("res://tests/test_report.gd")
var report := Report.new("board_gui")
var main: Node
var network: Node
var input_log: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _settle(frames: int = 5) -> void:
	for i in range(frames):
		await process_frame

func _wait_for(predicate: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			await _settle()
			return true
		await process_frame
	return predicate.call()

func _button(node_name: String) -> Button:
	return main.find_child(node_name, true, false) as Button

func _click_at(point: Vector2, target: String) -> void:
	report.check(root.get_visible_rect().has_point(point), "输入点位于逻辑视口：" + target, str(point))
	point = root.get_final_transform() * point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await _settle(2)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		input_log.append({"case_id":report.current["case_id"], "target":target, "pressed":pressed, "position":str(point)})
		Input.parse_input_event(event)
		await _settle(2)
	await _settle()

func _click(node_name: String) -> void:
	var button := _button(node_name)
	report.check(button != null and button.is_visible_in_tree(), "实际按钮存在且可见：" + node_name)
	if button != null:
		await _click_at(button.get_global_rect().get_center(), node_name)

func _capture(name: String) -> void:
	await _settle(10)
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	report.check(picture != null and not picture.is_empty(), "真实渲染可读取")
	if picture == null or picture.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(report.evidence_dir.path_join("screenshots"))
	var path := "screenshots/" + name + ".png"
	report.check(picture.save_png(report.evidence_dir.path_join(path)) == OK, "截图保存", str(picture.get_size()))
	report.attach(path)

func _state() -> Dictionary:
	return network.get_snapshot()

func _gameplay() -> Dictionary:
	var value := _state().duplicate(true)
	for field in ["revision", "story"]:
		value.erase(field)
	return value

func _open_solo(character: String) -> bool:
	await _click("LocalDebugButton")
	var connected := await _wait_for(func() -> bool: return _state().get("phase") == "lobby")
	report.check(connected, "本机按钮启动独立服务并建立真实ENet连接")
	if not connected:
		return false
	await _click(character + "ChooseButton")
	report.check(await _wait_for(func() -> bool: return _state().get("selection_order", []).has(character)), "服务端确认角色")
	await _click("ReadyButton")
	report.check(await _wait_for(func() -> bool: return _state()["players"][0]["ready"]), "服务端确认准备")
	await _capture("room_" + character)
	await _click("EnterBoardButton")
	var entered := await _wait_for(func() -> bool: return _state().get("phase") == "board")
	report.check(entered, "进入服务器确认的棋盘阶段")
	return entered

func _run() -> void:
	var resolution_sweep := OS.get_cmdline_user_args().has("--resolution-sweep")
	report.metadata = {"input_method":"Input.parse_input_event", "os_mouse_tested":false,
		"scope":"TC-BOARD 有针对性的真实图形输入检查，视觉人工结论和网络边界另关联", "single_cat":true,
		"resolution_sweep_enabled":resolution_sweep, "resolutions":[], "not_run_cases":[]}
	if not resolution_sweep:
		report.metadata["not_run_cases"].append({"case_id":"TC-BOARD-002", "status":"NOT_RUN",
			"reason":"默认功能验收不主动轮转窗口尺寸；须显式传入 --resolution-sweep 才执行四组尺寸用例。"})
	root.title = "我们的家 · 自动验收（会主动调整尺寸；独立测试窗口）" if resolution_sweep else "我们的家 · 功能自动验收（独立测试窗口）"
	report.begin("TC-BOARD-006")
	if DisplayServer.get_name() == "headless":
		report.check(false, "本套必须使用真实图形渲染")
		quit(report.finish())
		return
	network = root.get_node("RoomNetwork")
	main = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(main)
	current_scene = main
	await _settle(20)
	await _capture("entry")
	if not await _open_solo("sanhua"):
		network.disconnect_from_server()
		quit(report.finish())
		return
	report.check(_state()["players"].size() == 1, "只有一个真实玩家，无虚构在线同伴", _state())
	var server_pid: int = network.get("_owned_server_pid")
	report.check(server_pid > 0 and server_pid != OS.get_process_id() and OS.is_process_running(server_pid), "独立服务进程真实存活", server_pid)
	report.metadata["client_pid"] = OS.get_process_id()
	report.metadata["owned_server_pid"] = server_pid
	await _capture("board_initial")
	var board := main.find_child("BoardView", true, false) as HomeBoardView
	var identity := board.get_instance_id()

	report.begin("TC-BOARD-008")
	var expected := [[24,23,22,21,20,19,18],[25,0,0,0,0,0,17],[26,0,0,0,0,0,16],[27,0,0,7,8,9,15],[28,0,0,6,0,0,14],[29,0,0,5,0,0,13],[1,2,3,4,10,11,12]]
	report.check(HomeBoardView.TILES.size() == 29, "原稿29格数量")
	for tile: Array in HomeBoardView.TILES:
		report.check(expected[tile[1]-1][tile[2]-1] == tile[0], "原图行列与格位对应", tile.slice(0,3))
	for tile_id in [1,7,15,29]:
		var before: Dictionary = _state()["players"][0].duplicate(true)
		await _click_at(board.get_global_transform() * board.tile_rect(tile_id).get_center(), "Tile%d" % tile_id)
		report.check(board.selected_id == tile_id, "棋盘实际点选位置", board.selected_id)
		await _click("DebugMoveButton")
		report.check(await _wait_for(func() -> bool: return int(_state()["players"][0]["tile_id"]) == tile_id), "服务端确认调试移动", tile_id)
		var after: Dictionary = _state()["players"][0].duplicate(true)
		before.erase("tile_id")
		after.erase("tile_id")
		report.check(before == after, "调试移动不结算数值/事件", after)
	await _capture("board_tile29")

	report.begin("TC-BOARD-001")
	var before_panels := _gameplay()
	for pair in [["WarehouseButton","warehouse"],["MyCatButton","cat"],["SettingsButton","settings"]]:
		await _click(pair[0])
		report.check(main.find_child("ModalPanel", true, false) != null, "面板打开：" + pair[1])
		await _capture(pair[1])
		await _click("ClosePanelButton")
		report.check(main.find_child("ModalPanel", true, false) == null, "面板关闭")
		report.check(main.find_child("BoardView", true, false).get_instance_id() == identity, "返回原棋盘实例")
		report.check(board.selected_id == 29 and _gameplay() == before_panels, "选格和服务端状态保持")

	report.begin("TC-BOARD-009")
	var before_story := _gameplay()
	for iteration in range(2):
		await _click("StoryDemoButton")
		report.check(await _wait_for(func() -> bool: return not _state().get("story", {}).is_empty()), "服务端创建共读预览")
		var grid := main.find_child("ComicGrid", true, false)
		report.check(grid != null and grid.get_child_count() == 4, "原稿片段四格与文字呈现")
		if iteration == 0:
			await _capture("story")
		await _click("StoryReadButton")
		report.check(await _wait_for(func() -> bool: return _state().get("story", {}).is_empty()), "看完确认经过服务器后返回")
		report.check(main.find_child("BoardView", true, false).get_instance_id() == identity and _gameplay() == before_story, "两次预览均不结算奖励/移动/月耗")

	if resolution_sweep:
		report.begin("TC-BOARD-002")
		report.metadata["resolutions"] = []
		var before_resize := _gameplay()
		var original_size := root.size
		for dimensions in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(1280,720)]:
			root.size = dimensions
			await _settle(30)
			report.check(root.size == dimensions, "真实窗口尺寸", str(root.size))
			var visible := root.get_visible_rect()
			for node_name in ["BoardView","TileDetail","WarehouseButton","MyCatButton","SettingsButton","LeaveBoardButton"]:
				var control := main.find_child(node_name, true, false) as Control
				report.check(control != null and visible.encloses(control.get_global_rect()), "关键区域无越界：" + node_name, str(control.get_global_rect()) if control else "")
			var rect := board.tile_rect(20)
			report.check(is_equal_approx(rect.size.x, rect.size.y), "棋盘格保持正方形，未横向拉伸", str(rect.size))
			await _click_at(board.get_global_transform() * rect.get_center(), "Tile20@" + str(dimensions))
			report.check(board.selected_id == 20, "缩放后仍可准确点击地块")
			await _capture("board_%dx%d" % [dimensions.x,dimensions.y])
			await _click("WarehouseButton")
			var panel := main.find_child("ModalPanel",true,false) as Control
			report.check(visible.encloses(panel.get_global_rect()), "弹层适配窗口")
			await _click("ClosePanelButton")
			await _click("MyCatButton")
			panel = main.find_child("ModalPanel",true,false) as Control
			report.check(visible.encloses(panel.get_global_rect()), "角色面板适配窗口")
			await _capture("cat_%dx%d" % [dimensions.x,dimensions.y])
			await _click("ClosePanelButton")
			await _click("StoryDemoButton")
			report.check(await _wait_for(func() -> bool: return not _state().get("story", {}).is_empty()), "本尺寸漫画打开")
			panel = main.find_child("ModalPanel",true,false) as Control
			report.check(visible.encloses(panel.get_global_rect()), "漫画面板适配窗口")
			await _capture("story_%dx%d" % [dimensions.x,dimensions.y])
			await _click("StoryReadButton")
			report.check(await _wait_for(func() -> bool: return _state().get("story", {}).is_empty()), "本尺寸可确认返回")
			report.check(before_resize == _gameplay() and main.find_child("BoardView",true,false).get_instance_id() == identity, "适配操作不重新建局或更改数值")
			report.metadata["resolutions"].append({"window":str(root.size),"logical":str(visible.size)})
		root.size = original_size
		await _settle(15)

	report.begin("TC-BOARD-005")
	report.check(HomeTheme.cat_texture("sanhua").resource_path.ends_with("sanhua_token_v001.png"), "三花真实引用Q版资源")
	await _capture("token_sanhua")
	await _click("LeaveBoardButton")
	for character in ["buou","nainiu"]:
		if not await _open_solo(character):
			break
		report.check(_state()["players"].size() == 1 and _state()["players"][0]["character_id"] == character, "真实单猫身份与头像一致", character)
		report.check(HomeTheme.cat_texture(character).resource_path.ends_with(character + "_token_v001.png"), "真实引用对应Q版资源")
		await _capture("token_" + character)
		await _click("LeaveBoardButton")
	report.check(not OS.is_process_running(server_pid), "退出仅关闭最初自建服务器")

	report.begin("TC-BOARD-007")
	await _click("ConnectButton")
	report.check(await _wait_for(func() -> bool: return network.get_connection_status() == "connection_failed", 25), "无服务端时连接失败")
	report.check(main.find_child("BoardView",true,false) == null and _state().is_empty(), "失败不伪装入局")
	await _capture("unreachable")
	network.disconnect_from_server()
	if await _open_solo("buou"):
		var owned_pid: int = network.get("_owned_server_pid")
		report.check(owned_pid > 0 and owned_pid != OS.get_process_id(), "仅停止本例自建服务")
		var before_drop := _gameplay()
		OS.kill(owned_pid)
		report.check(await _wait_for(func() -> bool: return network.get_connection_status() == "server_disconnected", 25), "真实服务器停止后识别断开")
		report.check(_button("DebugMoveButton").disabled and _button("StoryDemoButton").disabled, "断开后写入按钮禁用")
		report.check(_gameplay() == before_drop, "保留已有显示，不伪造新状态")
		await _click("MyCatButton")
		report.check(main.find_child("CatIdentity",true,false).text == "布偶", "断线后仍展示原玩家的猫")
		await _capture("disconnected_cat")
		await _click("ClosePanelButton")
		await _capture("disconnected")
		await _click("LeaveBoardButton")
	if await _open_solo("sanhua"):
		await _click("StoryDemoButton")
		report.check(await _wait_for(func() -> bool: return not _state().get("story", {}).is_empty()), "断线前打开共读")
		OS.kill(int(network.get("_owned_server_pid")))
		report.check(await _wait_for(func() -> bool: return network.get_connection_status() == "server_disconnected", 25), "共读期间识别真实断线")
		report.check(_button("StoryReadButton").disabled, "断线禁止虚假确认看完")
		await _capture("disconnected_story")
		await _click("StoryDisconnectExitButton")
		report.check(main.find_child("BoardView",true,false) == null and main.find_child("ModalPanel",true,false) == null, "断线共读能退出，不锁住界面")
	network.disconnect_from_server()
	var log_file := FileAccess.open(report.evidence_dir.path_join("input_events.json"), FileAccess.WRITE)
	log_file.store_string(JSON.stringify(input_log,"\t") + "\n")
	log_file.close()
	report.attach("input_events.json")
	quit(report.finish())
