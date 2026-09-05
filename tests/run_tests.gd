extends SceneTree
## 无第三方依赖的脚手架验收；退出码非零表示失败。

const RULES: GameRules = preload("res://data/rules/default_rules.tres")
const MAIN_SCENE: PackedScene = preload("res://src/app/main.tscn")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_session()
	_test_invalid_input()
	await _test_entry_ui()
	if _failures == 0:
		print("CHECKS PASSED: %d" % _checks)
	else:
		printerr("CHECKS FAILED: %d of %d" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _test_session() -> void:
	var order: Array[StringName] = [&"nainiu", &"sanhua", &"buou"]
	var session := GameSession.create(RULES, order)
	_check(session != null, "有效的三人选择应建立开局")
	if session == null:
		return
	var state := session.snapshot()
	_check(state["selection_order"] == order, "保留玩家选择顺序")
	_check(state["players"].size() == 3, "恰好建立三名玩家")
	for index in range(3):
		var player: Dictionary = state["players"][index]
		_check(player["player_slot"] == index + 1, "玩家席位跟随选择顺序")
		_check(player["character_id"] == order[index], "角色分配跟随选择顺序")
		_check(player["level"] == 1 and player["wildness"] == 0, "开局为 1 级 0 野性")
		_check(
			player["satiety_units"] == 6 and player["satiety_cap_units"] == 10,
			"开局饱食度为 3/5，不重复增加等级奖励"
		)
	# 调用方改动输入与输出，均不能污染已经创建的会话。
	order[0] = &"buou"
	state["selection_order"][0] = &"buou"
	state["players"][0]["satiety_units"] = 0
	var unchanged := session.snapshot()
	_check(unchanged["selection_order"][0] == &"nainiu", "输入和快照的顺序均与内部隔离")
	_check(unchanged["players"][0]["satiety_units"] == 6, "快照嵌套状态与内部隔离")
	var another_order: Array[StringName] = [&"sanhua", &"buou", &"nainiu"]
	var another := GameSession.create(RULES, another_order)
	_check(another.snapshot()["players"][0]["satiety_units"] == 6, "新会话没有继承其他会话的数据")
	_check(GameRules.satiety_text(1) == "0.5", "半点饱食度正确显示")
	_check(GameRules.satiety_text(6) == "3", "整数饱食度正确显示")


func _test_invalid_input() -> void:
	var missing: Array[StringName] = [&"sanhua", &"buou"]
	var repeated: Array[StringName] = [&"sanhua", &"sanhua", &"nainiu"]
	var unknown: Array[StringName] = [&"sanhua", &"buou", &"dog"]
	var valid: Array[StringName] = [&"sanhua", &"buou", &"nainiu"]
	_check(GameSession.create(RULES, missing) == null, "拒绝人数不足")
	_check(GameSession.create(RULES, repeated) == null, "拒绝角色重复")
	_check(GameSession.create(RULES, unknown) == null, "拒绝未知角色")
	_check(GameSession.create(null, valid) == null, "拒绝缺失规则")
	var invalid := RULES.duplicate() as GameRules
	invalid.initial_satiety_units = 11
	_check(GameSession.create(invalid, valid) == null, "拒绝饱食度超出上限的配置")


func _test_entry_ui() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	var start := main.find_child("StartPreviewButton", true, false) as Button
	_check(start != null and start.disabled, "入口在选满三只猫前禁止创建")
	var button_names := ["nainiuButton", "sanhuaButton", "buouButton"]
	for button_name in button_names:
		var button := main.find_child(button_name, true, false) as Button
		_check(button != null, "入口存在可选角色按钮")
		if button != null:
			button.pressed.emit()
			_check(button.disabled, "已选角色不能重复选择")
	_check(not start.disabled, "选满三只猫后可建立预览")
	start.pressed.emit()
	var preview := main.find_child("SessionPreview", true, false) as VBoxContainer
	_check(preview.get_child_count() == 3, "入口展示三只猫的初始状态")
	if preview.get_child_count() == 3:
		var first := preview.get_child(0) as Label
		_check(first.text.begins_with("奶牛"), "入口展示真实选择顺序")
		_check(first.text.contains("饱食度 3/5"), "入口使用饱食度术语与确认数值")
	var reset := main.find_child("ResetButton", true, false) as Button
	reset.pressed.emit()
	_check(start.disabled and preview.get_child_count() == 0, "重新选择清理上次预览")
	main.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)
