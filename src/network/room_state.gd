extends RefCounted
## 独立服务器的房间状态。正式数值来自默认规则；调试操作不结算故事奖励。

const Rules = preload("res://data/rules/default_rules.tres")
const CHARACTER_IDS: Array[String] = ["sanhua", "buou", "nainiu"]
const STORY_LINES: Array[String] = [
	"你们回到曾经居住的烂尾楼。",
	"施工人员把三兄弟赶了出来。",
	"你们来到公园入口，寻找新的落脚处。",
	"三兄弟在森林公园的小洞里躲雨，暂时安顿下来。",
]

var _single_cat: bool = false
var _revision: int = 0
var _phase: String = "lobby"
var _players: Dictionary = {}
var _selection_peers: Array[int] = []
var _story: Dictionary = {}
var _story_serial: int = 0
var _finished_story_ids: Dictionary = {}


func _init(single_cat: bool = false) -> void:
	_single_cat = single_cat


func capacity() -> int:
	return 1 if _single_cat else 3


func join(peer_id: int) -> String:
	if peer_id <= 1 or _players.has(peer_id):
		return "玩家身份无效。"
	if _phase != "lobby":
		return "本局已经进入棋盘；重连恢复尚未实现。"
	if _players.size() >= capacity():
		return "房间人数已满。"
	_players[peer_id] = {
		"peer_id": peer_id, "character_id": "", "ready": false, "connected": true,
		"level": Rules.initial_level, "wildness": Rules.initial_wildness,
		"satiety_units": Rules.initial_satiety_units,
		"satiety_cap_units": Rules.initial_satiety_cap_units, "tile_id": 1,
	}
	_revision += 1
	return ""


func leave(peer_id: int) -> bool:
	if not _players.has(peer_id):
		return false
	if _phase == "lobby":
		_players.erase(peer_id)
		_selection_peers.erase(peer_id)
	else:
		_players[peer_id]["connected"] = false
	_revision += 1
	return true


func get_snapshot() -> Dictionary:
	var players: Array[Dictionary] = []
	for player: Dictionary in _players.values():
		players.append(player.duplicate(true))
	var selection_order: Array[String] = []
	for peer_id in _selection_peers:
		if _players.has(peer_id):
			selection_order.append(_players[peer_id]["character_id"])
	return {
		"revision": _revision, "phase": _phase,
		"mode": "single_cat_debug" if _single_cat else "three_players",
		"players": players, "selection_order": selection_order,
		"story": _story.duplicate(true), "month": {}, "waiting_reason": _waiting_reason(),
	}


func apply_command(peer_id: int, action: String, payload: Dictionary) -> Dictionary:
	if not _players.has(peer_id) or not _players[peer_id]["connected"]:
		return _error("该连接不是本局可操作玩家。")
	match action:
		"choose_character":
			return _choose(peer_id, payload)
		"set_ready":
			return _ready_player(peer_id, payload)
		"request_start":
			return _start()
		"debug_move":
			return _debug_move(peer_id, payload)
		"story_demo":
			return _story_demo()
		"story_read":
			return _story_read(peer_id, payload)
	return _error("未知的房间操作。")


func _choose(peer_id: int, payload: Dictionary) -> Dictionary:
	if _phase != "lobby":
		return _error("进入棋盘后不能更换角色。")
	var requested: Variant = payload.get("character_id", "")
	if typeof(requested) != TYPE_STRING and typeof(requested) != TYPE_STRING_NAME:
		return _error("角色编号无效。")
	var character_id := String(requested)
	if not CHARACTER_IDS.has(character_id):
		return _error("请选择三花、布偶或奶牛。")
	for other_id: int in _players:
		if other_id != peer_id and _players[other_id]["character_id"] == character_id:
			return _error("这只猫已被其他玩家选择。")
	if _players[peer_id]["character_id"] == character_id:
		return _unchanged()
	_players[peer_id]["character_id"] = character_id
	_players[peer_id]["ready"] = false
	if not _selection_peers.has(peer_id):
		_selection_peers.append(peer_id)
	return _changed()


func _ready_player(peer_id: int, payload: Dictionary) -> Dictionary:
	if _phase != "lobby":
		return _error("当前已不在选角房间。")
	if typeof(payload.get("ready")) != TYPE_BOOL:
		return _error("准备状态必须为真或假。")
	if _players[peer_id]["character_id"].is_empty():
		return _error("请先选择一只猫。")
	if _players[peer_id]["ready"] == payload["ready"]:
		return _unchanged()
	_players[peer_id]["ready"] = payload["ready"]
	return _changed()


func _start() -> Dictionary:
	if _phase != "lobby":
		return _error("本局已经进入棋盘。")
	if _players.size() != capacity():
		return _error("正常联机需要三名玩家全部加入。" if not _single_cat else "单猫调试需要一名玩家。")
	for player: Dictionary in _players.values():
		if not player["connected"] or player["character_id"].is_empty() or not player["ready"]:
			return _error("请等待所有玩家选角并准备。")
	_phase = "board"
	return _changed()


func _debug_move(peer_id: int, payload: Dictionary) -> Dictionary:
	var error := _debug_error()
	if not error.is_empty():
		return _error(error)
	if not _story.is_empty():
		return _error("先完成当前共同剧情，再进行调试移动。")
	var tile: Variant = payload.get("tile_id")
	if typeof(tile) != TYPE_INT or tile < 1 or tile > 29:
		return _error("调试格子编号必须为 1–29。")
	if _players[peer_id]["tile_id"] == tile:
		return _unchanged()
	_players[peer_id]["tile_id"] = tile
	return _changed()


func _story_demo() -> Dictionary:
	var error := _debug_error()
	if not error.is_empty():
		return _error(error)
	if not _story.is_empty():
		return _error("当前剧情尚未看完。")
	_story_serial += 1
	# 摘要依据：原稿第6页，返回烂尾楼与公园入口；仅演示共同呈现，不发奖励。
	_story = {
		"id": "story-demo-%d" % _story_serial, "title": "新的落脚处 · 剧情预览",
		"lines": STORY_LINES.duplicate(), "read_peer_ids": [],
	}
	return _changed()


func _story_read(peer_id: int, payload: Dictionary) -> Dictionary:
	var requested: Variant = payload.get("story_id", "")
	if typeof(requested) != TYPE_STRING or requested.is_empty():
		return _error("剧情编号无效。")
	if _finished_story_ids.has(requested):
		return _unchanged()
	if _story.is_empty() or _story["id"] != requested:
		return _error("这段剧情已不属于当前观看流程。")
	if not _waiting_reason().is_empty():
		return _error("有玩家断线，当前剧情保持等待；恢复规则尚待确定。")
	if _story["read_peer_ids"].has(peer_id):
		return _unchanged()
	_story["read_peer_ids"].append(peer_id)
	if _story["read_peer_ids"].size() == _players.size():
		_finished_story_ids[requested] = true
		_story = {}
	return _changed()


func _debug_error() -> String:
	if not _single_cat:
		return "该操作仅在显式开启的单猫调试模式中可用。"
	if _phase != "board":
		return "先选角、准备并进入棋盘。"
	return _waiting_reason()


func _waiting_reason() -> String:
	for player: Dictionary in _players.values():
		if not player["connected"]:
			return "有玩家断线，本局保持等待；重新连接与恢复尚未实现。"
	return ""


func _changed() -> Dictionary:
	_revision += 1
	return {"changed": true, "error": ""}


func _unchanged() -> Dictionary:
	return {"changed": false, "error": ""}


func _error(message: String) -> Dictionary:
	return {"changed": false, "error": message}
