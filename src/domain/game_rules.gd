class_name GameRules
extends Resource
## 已确认的开局规则。饱食度以半点为一个整数单位，避免 0.5 运算误差。

const SATIETY_UNITS_PER_POINT: int = 2
const CHARACTER_IDS: Array[StringName] = [&"sanhua", &"buou", &"nainiu"]
const CHARACTER_NAMES: Dictionary = {
	&"sanhua": "三花",
	&"buou": "布偶",
	&"nainiu": "奶牛",
}

@export var player_count: int = 3
@export var initial_level: int = 1
@export var initial_wildness: int = 0
@export var initial_satiety_units: int = 6
@export var initial_satiety_cap_units: int = 10
@export var level_wildness_requirements: PackedInt32Array = PackedInt32Array([10, 20, 30, 40])


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if player_count != CHARACTER_IDS.size():
		errors.append("开局必须有三名玩家。")
	if initial_level != 1:
		errors.append("默认开局等级必须为 1。")
	if initial_wildness != 0:
		errors.append("默认开局当前级野性必须为 0。")
	if initial_satiety_units <= 0 or initial_satiety_units > initial_satiety_cap_units:
		errors.append("初始饱食度必须大于 0，且不超过上限。")
	if level_wildness_requirements != PackedInt32Array([10, 20, 30, 40]):
		errors.append("各级升级野性要求必须为 10、20、30、40。")
	return errors


static func character_name(character_id: StringName) -> String:
	return str(CHARACTER_NAMES.get(character_id, "未知角色"))


static func satiety_text(units: int) -> String:
	if units % SATIETY_UNITS_PER_POINT == 0:
		return str(units >> 1)
	return "%.1f" % (float(units) / float(SATIETY_UNITS_PER_POINT))
