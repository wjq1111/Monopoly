extends "res://tests/test_board_interface.gd"
## REQ-UI-006 / TC-BOARD-010：普通输入中逐帧记录稳定性，独立服务端口不接管用户房间。
var _monitoring := false
var _stage := "startup"
var _baseline: Dictionary = {}
var _board_baseline: Dictionary = {}
var _last: Dictionary = {}
var _changes: Array[Dictionary] = []
var _violations: Array[Dictionary] = []
var _samples: int = 0
var _started: int = 0
var _board_started: int = 0
var _resize_signals: Array[Dictionary] = []
var _input_stages: Array[Dictionary] = []
var _last_stage := ""
var _fullscreen_samples: Array[Dictionary] = []
var _render_geometry: Dictionary = {}

func _geometry_before_scene() -> Dictionary:
	return {
		"window":str(root.size), "position":str(root.position), "mode":root.mode,
		"outer_size":str(DisplayServer.window_get_size_with_decorations()),
		"outer_position":str(DisplayServer.window_get_position_with_decorations()),
		"logical":str(root.get_visible_rect().size), "scale_size":str(root.content_scale_size),
		"scale_factor":root.content_scale_factor, "transform":str(root.get_final_transform()),
	}

func _geometry() -> Dictionary:
	var value := {
		"window":str(root.size), "position":str(root.position), "mode":root.mode,
		"outer_size":str(DisplayServer.window_get_size_with_decorations()),
		"outer_position":str(DisplayServer.window_get_position_with_decorations()),
		"logical":str(root.get_visible_rect().size), "scale_size":str(root.content_scale_size),
		"scale_factor":root.content_scale_factor, "transform":str(root.get_final_transform()),
	}
	var board := main.find_child("BoardView",true,false) as HomeBoardView
	if board != null:
		value["board"] = str(board.get_global_rect())
		value["tile_1"] = str(board.tile_rect(1))
		value["tile_20"] = str(board.tile_rect(20))
	return value

func _sample_rendered_geometry() -> void:
	if _monitoring:
		_sample_stability()
		_render_geometry = _geometry()

func _sample_stability() -> void:
	if not _monitoring:
		return
	_samples += 1
	if _stage != _last_stage:
		_input_stages.append({"ms":Time.get_ticks_msec()-_started,"stage":_stage,"revision":_state().get("revision",-1)})
		_last_stage = _stage
	var geometry := _geometry()
	if geometry != _last:
		_changes.append({"ms":Time.get_ticks_msec()-_started,"stage":_stage,"geometry":geometry})
		_last = geometry
	var problems := PackedStringArray()
	for field in _baseline:
		if geometry.get(field) != _baseline[field]:
			problems.append(field)
	for field in _board_baseline:
		if geometry.get(field) != _board_baseline[field]:
			problems.append(field)
	if not problems.is_empty() and (_violations.is_empty() or _violations.back()["geometry"] != geometry):
		_violations.append({"ms":Time.get_ticks_msec()-_started,"stage":_stage,"changed_fields":problems,"geometry":geometry,"previous_rendered_geometry":_render_geometry})

func _run() -> void:
	report = Report.new("resolution_stability")
	report.metadata = {"input_method":"Input.parse_input_event","os_mouse_tested":false,
		"requirement":"REQ-UI-006","server_port":27944,"setup":"实际本地服务接口创建独立前置；后续控件均正常输入"}
	report.begin("TC-BOARD-010")
	if DisplayServer.get_name() == "headless":
		report.check(false,"必须真实Godot图形窗口")
		quit(report.finish())
		return
	network = root.get_node("RoomNetwork")
	_started = Time.get_ticks_msec()
	_baseline = _geometry_before_scene()
	_last = _baseline.duplicate(true)
	report.metadata["requested_window"] = str(Vector2i(ProjectSettings.get_setting("display/window/size/window_width_override"), ProjectSettings.get_setting("display/window/size/window_height_override")))
	report.metadata["first_actual_geometry"] = _baseline.duplicate(true)
	report.metadata["screen_rect"] = str(DisplayServer.screen_get_usable_rect(root.current_screen))
	report.metadata["screen_dpi"] = DisplayServer.screen_get_dpi(root.current_screen)
	report.metadata["os_scale"] = "未单独采集Windows缩放百分比；screen_dpi仅记录引擎返回值"
	report.metadata["client_pid"] = OS.get_process_id()
	main = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	_monitoring = true
	process_frame.connect(_sample_stability)
	RenderingServer.frame_post_draw.connect(_sample_rendered_geometry)
	root.size_changed.connect(func() -> void:
		if _monitoring:
			_resize_signals.append({"ms":Time.get_ticks_msec()-_started,"stage":_stage,"geometry":_geometry()})
	)
	root.add_child(main)
	current_scene = main
	root.title = "我们的家 · 稳定性自动验收（独立测试窗口）"
	await _settle(30)
	_stage = "entry_idle"
	await create_timer(2).timeout
	_stage = "connecting"
	network.start_local_debug_server(27944)
	if not await _wait_for(func() -> bool: return _state().get("phase") == "lobby"):
		report.check(false,"独立本地服务连接")
		network.disconnect_from_server()
		quit(report.finish())
		return
	_stage = "select_and_ready"
	await _click("buouChooseButton")
	report.check(await _wait_for(func() -> bool: return _state().get("selection_order",[]).has("buou")),"服务端确认布偶")
	await _click("ReadyButton")
	report.check(await _wait_for(func() -> bool: return _state()["players"][0]["ready"]),"服务端确认准备")
	await _click("EnterBoardButton")
	report.check(await _wait_for(func() -> bool: return _state().get("phase") == "board"),"真实进入棋盘")
	await _settle(30)
	var board := main.find_child("BoardView",true,false) as HomeBoardView
	var current := _geometry()
	for field in ["board","tile_1","tile_20"]:
		_board_baseline[field] = current[field]
	_board_started = Time.get_ticks_msec()
	await _capture("before")
	if OS.get_cmdline_user_args().has("--inject-size-glitch"):
		report.metadata["fault_injection"] = true
		report.metadata["scope"] = "检测器负向校验，非产品自然故障"
		_stage = "injected_resize"
		var original_size := root.size
		root.size = original_size + Vector2i(32, 18)
		await _settle(2)
		root.size = original_size
		await _settle(4)
		_monitoring = false
		report.check(_violations.is_empty(), "故意注入的短暂尺寸变化应使本运行失败", _violations)
		_finish_evidence()
		return
	for cycle in range(3):
		for tile_id in range(1,30):
			_stage = "tile_%d_cycle_%d" % [tile_id,cycle]
			await _click_at(board.get_global_transform() * board.tile_rect(tile_id).get_center(),"Tile%d" % tile_id)
			report.check(board.selected_id == tile_id,"实际输入选中对应地块",tile_id)
			if tile_id in [1,9,20,24,29]:
				await _click("DebugMoveButton")
				report.check(await _wait_for(func() -> bool: return int(_state()["players"][0]["tile_id"]) == tile_id),"移动收到真实服务器快照",tile_id)
		for button in ["WarehouseButton","MyCatButton","SettingsButton"]:
			_stage = "panel_" + button
			await _click(button)
			await _settle(20)
			await _click("ClosePanelButton")
		_stage = "story"
		await _click("StoryDemoButton")
		report.check(await _wait_for(func() -> bool: return not _state().get("story",{}).is_empty()),"真实故事预览")
		await _settle(20)
		await _click("StoryReadButton")
		report.check(await _wait_for(func() -> bool: return _state().get("story",{}).is_empty()),"服务器确认看完")
	_stage = "board_idle"
	while Time.get_ticks_msec() - _board_started < 60000:
		await process_frame
	report.check(Time.get_ticks_msec()-_board_started >= 60000,"固定窗口棋盘持续观察至少60秒")
	await _capture("after")
	_monitoring = false
	# 同一个已入局棋盘验证主动显示往返，不重新创建一个无关的房间前置。
	_stage = "fullscreen_round_trip"
	report.check(main.find_child("BoardView",true,false) == board, "显示设置检查保留同一棋盘前置")
	var window_size := root.size
	var window_position := root.position
	_fullscreen_samples.append({"stage":"before","geometry":_geometry()})
	for cycle in range(2):
		await _click("SettingsButton")
		await _click("FullscreenButton")
		await _settle(45)
		_fullscreen_samples.append({"stage":"fullscreen_%d" % cycle,"geometry":_geometry()})
		report.check(root.mode == Window.MODE_FULLSCREEN,"用户主动按钮进入全屏")
		await _click("FullscreenButton")
		await _settle(45)
		_fullscreen_samples.append({"stage":"restored_%d" % cycle,"geometry":_geometry()})
		report.check(root.mode == Window.MODE_WINDOWED and root.size == window_size and root.position == window_position,"退出全屏恢复原窗口尺寸和位置",_geometry())
		await _click("ClosePanelButton")
	_board_baseline.clear()
	_stage = "return_entry"
	_monitoring = true
	await _click("LeaveBoardButton")
	await _settle(30)
	_monitoring = false
	report.check(_violations.is_empty(),"正常流程逐帧无窗口/缩放/棋盘区域跳变",_violations)
	report.check(_resize_signals.is_empty(),"未经主动调整未出现尺寸变更信号",_resize_signals)
	_finish_evidence()

func _finish_evidence() -> void:
	network.disconnect_from_server()
	var file := FileAccess.open(report.evidence_dir.path_join("geometry_timeline.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"baseline":_baseline,"samples":_samples,"changes":_changes,"violations":_violations,"resize_signals":_resize_signals,"action_stages":_input_stages,"fullscreen_round_trips":_fullscreen_samples}, "\t")+"\n")
	file.close()
	report.attach("geometry_timeline.json")
	report.metadata["samples"] = _samples
	report.metadata["observed_ms"] = Time.get_ticks_msec()-_started
	var log_file := FileAccess.open(report.evidence_dir.path_join("input_events.json"),FileAccess.WRITE)
	log_file.store_string(JSON.stringify(input_log,"\t")+"\n")
	log_file.close()
	report.attach("input_events.json")
	quit(report.finish())
