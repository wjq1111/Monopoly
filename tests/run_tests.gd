extends SceneTree
## 需求与预期见 tests/test_catalog.json；这里执行真实领域代码。

const RULES: GameRules = preload("res://data/rules/default_rules.tres")
const Report = preload("res://tests/test_report.gd")
var report := Report.new("domain")


func _initialize() -> void:
	call_deferred("_run")


func _order() -> Array[StringName]:
	return [&"nainiu", &"sanhua", &"buou"]


func _run() -> void:
	report.begin("TC-M0-001")
	var session := GameSession.create(RULES, _order())
	report.check(session != null, "合法三猫开局")
	if session != null:
		var players: Array = session.snapshot()["players"]
		report.check(players.size() == 3, "三名玩家各一只猫", players.size())
		for player: Dictionary in players:
			report.check(player["level"] == 1 and player["wildness"] == 0, "默认 1 级 0 野性", player)
			report.check(player["satiety_units"] == 6 and player["satiety_cap_units"] == 10, "饱食度 3/5，不重复加上限", player)

	report.begin("TC-M0-002")
	var ids: Array[StringName] = [&"sanhua", &"buou", &"nainiu"]
	for first in ids:
		for second in ids:
			for third in ids:
				if first == second or first == third or second == third:
					continue
				var order: Array[StringName] = [first, second, third]
				var ordered := GameSession.create(RULES, order)
				report.check(ordered != null, "合法排列可建立状态", order)
				if ordered != null:
					var state := ordered.snapshot()
					report.check(state["selection_order"] == order, "保存完整选择顺序", state)
					for index in range(3):
						report.check(state["players"][index]["character_id"] == order[index] and state["players"][index]["player_slot"] == index + 1, "角色与玩家席位对应", state["players"][index])

	report.begin("TC-M0-003")
	var none: Array[StringName] = []
	var missing: Array[StringName] = [&"sanhua", &"buou"]
	var excess: Array[StringName] = [&"sanhua", &"buou", &"nainiu", &"sanhua"]
	report.check(GameSession.create(RULES, none) == null, "拒绝空选择")
	report.check(GameSession.create(RULES, missing) == null, "拒绝少一名玩家")
	report.check(GameSession.create(RULES, excess) == null, "拒绝第四个席位")

	report.begin("TC-M0-004")
	var repeated: Array[StringName] = [&"sanhua", &"sanhua", &"nainiu"]
	var unknown: Array[StringName] = [&"sanhua", &"buou", &"dog"]
	report.check(GameSession.create(RULES, repeated) == null, "拒绝重复角色")
	report.check(GameSession.create(RULES, unknown) == null, "拒绝原三猫以外的角色")

	report.begin("TC-M0-005")
	var original := _order()
	var isolated := GameSession.create(RULES, original)
	report.check(isolated != null, "建立隔离检查会话")
	if isolated != null:
		var copy := isolated.snapshot()
		original[0] = &"buou"
		copy["selection_order"][0] = &"buou"
		copy["players"][0]["satiety_units"] = 0
		var after := isolated.snapshot()
		report.check(after["selection_order"][0] == &"nainiu", "调用方不能改已保存顺序", after)
		report.check(after["players"][0]["satiety_units"] == 6, "调用方不能改内部饱食度", after)

	report.begin("TC-M0-006")
	report.check(GameSession.create(null, _order()) == null, "缺失规则不能建立会话")
	for satiety in [0, -1, 11]:
		var invalid := RULES.duplicate() as GameRules
		invalid.initial_satiety_units = satiety
		report.check(GameSession.create(invalid, _order()) == null, "无效初始饱食度不能建立会话", satiety)

	report.begin("TC-M0-007")
	for pair in [[1, "0.5"], [3, "1.5"], [6, "3"], [10, "5"]]:
		report.check(GameRules.satiety_text(pair[0]) == pair[1], "内部半点单位正确转为显示值", {"units": pair[0], "display": GameRules.satiety_text(pair[0])})

	report.begin("TC-M0-008")
	var first_session := GameSession.create(RULES, _order())
	var next_order: Array[StringName] = [&"buou", &"nainiu", &"sanhua"]
	var second_session := GameSession.create(RULES, next_order)
	report.check(first_session != null and second_session != null, "两次独立创建有效")
	if first_session != null and second_session != null:
		var first_copy := first_session.snapshot()
		first_copy["players"][0]["wildness"] = 100
		var second_state := second_session.snapshot()
		report.check(second_state["selection_order"] == next_order, "新会话使用本次顺序", second_state)
		report.check(second_state["players"][0]["wildness"] == 0 and second_state["players"][0]["satiety_units"] == 6, "新会话保留默认数值", second_state)
	quit(report.finish())
