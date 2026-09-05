class_name GameSession
extends RefCounted
## 只建立开局状态；不推进月份、不掷骰、不处理联机。

var _players: Array[Dictionary] = []
var _selection_order: Array[StringName] = []


static func selection_error(rules: GameRules, selection_order: Array[StringName]) -> String:
	if rules == null:
		return "缺少开局规则。"
	var errors := rules.validation_errors()
	if not errors.is_empty():
		return errors[0]
	if selection_order.size() != rules.player_count:
		return "请按顺序选择三只猫。"
	var seen: Array[StringName] = []
	for character_id in selection_order:
		if not GameRules.CHARACTER_IDS.has(character_id):
			return "选择中包含未知角色。"
		if seen.has(character_id):
			return "每只猫只能被一名玩家选择。"
		seen.append(character_id)
	return ""


static func create(rules: GameRules, selection_order: Array[StringName]) -> GameSession:
	if not selection_error(rules, selection_order).is_empty():
		return null
	var session := GameSession.new()
	session._selection_order = selection_order.duplicate()
	for index in range(selection_order.size()):
		session._players.append({
			"player_slot": index + 1,
			"character_id": selection_order[index],
			"level": rules.initial_level,
			"wildness": rules.initial_wildness,
			"satiety_units": rules.initial_satiety_units,
			"satiety_cap_units": rules.initial_satiety_cap_units,
		})
	return session


func snapshot() -> Dictionary:
	# 返回副本，防止 UI 或调用方直接改写游戏状态。
	return {
		"selection_order": _selection_order.duplicate(),
		"players": _players.duplicate(true),
	}
