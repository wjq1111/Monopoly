extends SceneTree
## 旧 M0 本地三猫预览回归；真实窗口与输入，不覆盖新的联机入口和棋盘。

const Report = preload("res://tests/test_report.gd")
const LEGACY_M0_SCENE: String = "res://src/app/main.tscn"
const LEGACY_M0_SIZE: Vector2i = Vector2i(1100, 760)
var report := Report.new("gui")
var main: Node
var input_log: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _settle(frames: int = 4) -> void:
	for _index in range(frames):
		await process_frame


func _button(node_name: String) -> Button:
	return main.find_child(node_name, true, false) as Button


func _preview() -> VBoxContainer:
	return main.find_child("SessionPreview", true, false) as VBoxContainer


func _order_text() -> String:
	var label := main.find_child("SelectionOrder", true, false) as Label
	return label.text if label != null else ""


func _click(node_name: String) -> void:
	var button := _button(node_name)
	report.check(button != null and button.is_visible_in_tree(), "输入目标存在且可见：" + node_name)
	if button == null:
		return
	var position := button.get_global_rect().get_center()
	report.check(root.get_visible_rect().has_point(position), "点击点位于游戏视口内", {"x": position.x, "y": position.y})
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await _settle(2)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		input_log.append({
			"case_id": report.current["case_id"], "target": node_name,
			"pressed": pressed, "x": position.x, "y": position.y,
			"frame": Engine.get_process_frames(),
		})
		Input.parse_input_event(event)
		await _settle(2)
	await _settle(4)


func _capture(name: String) -> void:
	await _settle(10)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	report.check(image != null and not image.is_empty(), "实际渲染视口可读取")
	if image == null or image.is_empty():
		return
	var relative := "screenshots/" + name + ".png"
	var directory := report.evidence_dir.path_join("screenshots")
	DirAccess.make_dir_recursive_absolute(directory)
	var code := image.save_png(report.evidence_dir.path_join(relative))
	report.check(code == OK, "截图保存成功", code)
	report.attach(relative)


func _run() -> void:
	report.metadata["scope"] = "legacy_m0"
	report.metadata["scene_path"] = LEGACY_M0_SCENE
	report.metadata["configured_main_scene"] = str(ProjectSettings.get_setting("application/run/main_scene"))
	report.metadata["input_method"] = "Input.parse_input_event"
	report.metadata["os_mouse_tested"] = false
	report.metadata["movie_writer"] = OS.has_feature("movie")
	report.begin("TC-GUI-001")
	report.check(DisplayServer.get_name() != "headless", "真实图形窗口，不能使用无头渲染替代")
	if DisplayServer.get_name() == "headless":
		quit(report.finish())
		return
	# 仅覆盖本次测试窗口；新主场景的尺寸设置不改变旧用例的视觉基线。
	root.min_size = Vector2i.ZERO
	root.content_scale_size = LEGACY_M0_SIZE
	root.size = LEGACY_M0_SIZE
	var scene: PackedScene = load(LEGACY_M0_SCENE)
	report.check(scene != null, "加载旧 M0 本地预览回归场景")
	if scene == null:
		quit(report.finish())
		return
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _settle(15)
	report.metadata["viewport"] = {"width": root.size.x, "height": root.size.y}
	var start := _button("StartPreviewButton")
	report.check(start != null and _preview() != null, "入口关键控件存在")
	if start == null or _preview() == null:
		quit(report.finish())
		return
	report.check(start.disabled, "未选角时开始按钮禁用")
	await _click("StartPreviewButton")
	report.check(_preview().get_child_count() == 0, "点击禁用开始按钮不会创建状态")
	await _capture("01_initial")

	report.begin("TC-GUI-002")
	await _click("nainiuButton")
	var once := _order_text()
	await _click("nainiuButton")
	report.check(_order_text() == once, "重复点击已选角色没有重复加入", _order_text())
	report.check(_button("nainiuButton").disabled, "已选奶牛禁用")
	await _click("sanhuaButton")
	report.check(start.disabled and _preview().get_child_count() == 0, "只有两名不同角色时不能创建")
	await _capture("02_partial")

	report.begin("TC-GUI-003")
	await _click("buouButton")
	report.check(not start.disabled, "三名不同角色选满后可以创建")
	await _click("StartPreviewButton")
	report.check(_preview().get_child_count() == 3, "真实输入后展示三猫")
	var names := ["奶牛", "三花", "布偶"]
	if _preview().get_child_count() == 3:
		for index in range(3):
			var label := _preview().get_child(index) as Label
			report.check(label != null, "结果为可读标签")
			if label != null:
				report.check(label.text.begins_with(names[index]), "显示顺序与玩家选择一致", label.text)
				report.check(label.text.contains("等级 1") and label.text.contains("野性 0/10") and label.text.contains("饱食度 3/5"), "显示确认的开局数值", label.text)
	await _capture("03_selected")

	report.begin("TC-GUI-004")
	var before := _order_text()
	report.check(start.disabled, "已有预览时开始按钮禁用")
	await _click("StartPreviewButton")
	await _click("buouButton")
	report.check(_preview().get_child_count() == 3 and _order_text() == before, "重复点击未新增角色或改变顺序")
	await _capture("04_repeated")

	report.begin("TC-GUI-005")
	await _click("ResetButton")
	report.check(start.disabled and _preview().get_child_count() == 0, "重新选择清空预览")
	for node_name in ["sanhuaButton", "buouButton", "nainiuButton"]:
		report.check(not _button(node_name).disabled, "重新选择恢复角色按钮")
	await _capture("05_reset")
	for node_name in ["buouButton", "nainiuButton", "sanhuaButton"]:
		await _click(node_name)
	await _click("StartPreviewButton")
	var reordered := ["布偶", "奶牛", "三花"]
	report.check(_preview().get_child_count() == 3, "再次建立三猫预览")
	if _preview().get_child_count() == 3:
		for index in range(3):
			var label := _preview().get_child(index) as Label
			report.check(label != null and label.text.begins_with(reordered[index]), "第二次顺序没有继承上次数据", label.text if label else "")
	await _capture("06_reselected")
	var log_file := FileAccess.open(report.evidence_dir.path_join("input_events.json"), FileAccess.WRITE)
	if log_file != null:
		log_file.store_string(JSON.stringify(input_log, "\t") + "\n")
		log_file.close()
	else:
		report.check(false, "输入日志写入失败")
	report.attach("input_events.json")
	await _settle(15)
	quit(report.finish())
