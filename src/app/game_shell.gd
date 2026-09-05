extends Control
## 棋盘常驻的联机界面。状态只从RoomNetwork读取，动作通过服务器接口提交。
var _network: Node
var _state: Dictionary = {}
var _page: String = ""
var _content: Control
var _overlay: Control
var _toast: Label
var _connection: String = "未连接"
var _address: LineEdit
var _room_cards: Dictionary = {}
var _room_order: Label
var _ready_button: Button
var _start_button: Button
var _board: HomeBoardView
var _player_column: VBoxContainer
var _tile_title: Label
var _tile_picture: TextureRect
var _tile_hint: Label
var _debug_move: Button
var _story_demo: Button
var _net_status: Label
var _modal_key: String = ""
var _selected_tile: int = 1
var _local_peer_id: int = 0

func _ready() -> void:
	theme = HomeTheme.create()
	_network = get_node("/root/RoomNetwork")
	_network.snapshot_changed.connect(_on_snapshot)
	_network.connection_state_changed.connect(_on_connection)
	_network.command_failed.connect(_show_message)
	_build_root()
	_show_entry()
	for arg in OS.get_cmdline_user_args():
		if arg == "--single-cat-ui":
			_start_local()
		if arg.begins_with("--connect-port="):
			_network.connect_to_server("127.0.0.1", int(arg.get_slice("=", 1)))

func _build_root() -> void:
	var background := ColorRect.new()
	background.color = HomeTheme.PAPER
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_toast = HomeTheme.label("", 17)
	_toast.name = "ConnectionFeedback"
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_left = 28
	_toast.offset_right = -28
	_toast.offset_top = -31
	_toast.offset_bottom = -5
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Color("#9b6136"))
	add_child(_toast)

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _new_page(page_name: String) -> VBoxContainer:
	_page = page_name
	_clear_children(_content)
	_close_modal(true)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_bottom", 40)
	_content.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	return column

func _header(title: String, subtitle: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 48
	row.add_child(HomeTheme.label("我们的家", 30))
	var center := HomeTheme.label(title, 20)
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(center)
	var right := HomeTheme.label(subtitle, 15)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_theme_color_override("font_color", HomeTheme.MUTED)
	row.add_child(right)
	return row

func _show_entry() -> void:
	var column := _new_page("entry")
	column.add_child(_header("", "三名玩家 · 系统主持"))
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	center.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 420
	left.add_theme_constant_override("separation", 22)
	row.add_child(left)
	left.add_child(HomeTheme.label("我们的家", 72))
	left.add_child(HomeTheme.label("三只猫，一起走过每一段故事。", 22))
	var solo := HomeTheme.button("本机试跑 · 单猫", "LocalDebugButton", _start_local)
	left.add_child(solo)
	_address = LineEdit.new()
	_address.name = "ServerAddress"
	_address.text = "127.0.0.1"
	_address.placeholder_text = "同伴的服务器地址"
	_address.custom_minimum_size.y = 44
	left.add_child(_address)
	left.add_child(HomeTheme.button("连接同伴的房间", "ConnectButton", func() -> void: _network.connect_to_server(_address.text.strip_edges(), 27840)))
	var note := HomeTheme.label("单猫入口用于接口调试；正式房间仍需三名玩家。", 15)
	note.add_theme_color_override("font_color", HomeTheme.MUTED)
	left.add_child(note)
	var portraits := HBoxContainer.new()
	portraits.custom_minimum_size = Vector2(440, 310)
	row.add_child(portraits)
	for character in ["sanhua", "buou", "nainiu"]:
		var portrait := HomeTheme.portrait(character, 136)
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		portraits.add_child(portrait)

func _start_local() -> void:
	_show_message("正在启动本地服务器…")
	_network.start_local_debug_server(27840)

func _on_connection(status: String) -> void:
	if status == "connected":
		_local_peer_id = _network.get_local_peer_id()
	_connection = {"starting_local_server":"正在启动本地服务器…","connecting":"正在连接…","connected":"已连接服务器","connection_failed":"连接失败","server_disconnected":"服务器已断开","disconnected":"已离开房间"}.get(status, status)
	if is_instance_valid(_net_status):
		_net_status.text = _connection
	if status.to_lower().contains("fail") or status.to_lower().contains("disconnect") or status.contains("失败") or status.contains("断"):
		_show_message("连接已中断，请返回入口后重试。")
		if is_instance_valid(_debug_move):
			_debug_move.disabled = true
		if is_instance_valid(_story_demo):
			_story_demo.disabled = true
		for node_name in ["sanhuaChooseButton","buouChooseButton","nainiuChooseButton","ReadyButton","EnterBoardButton","StoryReadButton"]:
			var button := find_child(node_name, true, false) as Button
			if button != null:
				button.disabled = true
		if _modal_key.begins_with("story:") and find_child("StoryDisconnectExitButton",true,false) == null:
			var panel := find_child("ModalPanel",true,false)
			if panel != null:
				panel.get_child(0).add_child(HomeTheme.button("连接中断 · 返回入口","StoryDisconnectExitButton",_leave))
	else:
		_show_message(_connection)

func _on_snapshot(value: Dictionary) -> void:
	_state = value.duplicate(true)
	if _state.is_empty() or String(_state.get("phase", "")).is_empty():
		return
	if _state.get("phase") == "lobby":
		if _page != "room":
			_build_room()
		_refresh_room()
	elif _state.get("phase") == "board":
		if _page != "board":
			_build_board()
		_refresh_board()
	var story: Dictionary = _state.get("story", {})
	if not story.is_empty():
		_show_story(story)
	elif _modal_key.begins_with("story:"):
		_close_modal(true)
	var reason := String(_state.get("waiting_reason", ""))
	if not reason.is_empty():
		_show_message(reason)

func _build_room() -> void:
	var column := _new_page("room")
	column.add_child(_header("同一局 · 选择你的猫", "已连接服务器"))
	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 24)
	column.add_child(cards)
	_room_cards.clear()
	for character: String in ["sanhua", "buou", "nainiu"]:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		var picture := HomeTheme.portrait(character, 220)
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(picture)
		box.add_child(HomeTheme.label(GameRules.character_name(character), 29))
		box.add_child(HomeTheme.label("等级 1  ·  野性 0/10  ·  饱食度 3/5", 17))
		var owner := HomeTheme.label("等待选择", 15)
		box.add_child(owner)
		var choose := HomeTheme.button("选择" + GameRules.character_name(character), character + "ChooseButton", func() -> void: _network.choose_character(StringName(character)))
		box.add_child(choose)
		_room_cards[character] = {"button": choose, "owner": owner}
	var footer := HBoxContainer.new()
	column.add_child(footer)
	_room_order = HomeTheme.label("", 18)
	footer.add_child(_room_order)
	_ready_button = HomeTheme.button("我准备好了", "ReadyButton", func() -> void: _network.set_ready(true))
	footer.add_child(_ready_button)
	_start_button = HomeTheme.button("进入棋盘", "EnterBoardButton", func() -> void: _network.request_start())
	footer.add_child(_start_button)
	footer.add_child(HomeTheme.button("离开", "LeaveRoomButton", _leave))

func _refresh_room() -> void:
	var local_id: int = _local_peer_id
	var members: Array = _state.get("players", [])
	var local: Dictionary = {}
	for character: String in _room_cards:
		var owner: Dictionary = {}
		for player: Dictionary in members:
			if player.get("peer_id") == local_id:
				local = player
			if String(player.get("character_id", "")) == character:
				owner = player
		var chosen_by_me := not owner.is_empty() and int(owner.get("peer_id", 0)) == local_id
		var controls: Dictionary = _room_cards[character]
		controls["button"].disabled = not owner.is_empty()
		controls["button"].text = "你的猫" if chosen_by_me else ("同伴已选择" if not owner.is_empty() else "选择" + GameRules.character_name(character))
		controls["owner"].text = ("已准备" if owner.get("ready", false) else "已选角色") if not owner.is_empty() else "等待选择"
	var names := PackedStringArray()
	for character in _state.get("selection_order", []):
		names.append(GameRules.character_name(StringName(str(character))))
	_room_order.text = ("单猫调试" if _is_debug() else "三人房间") + "  ·  " + (" → ".join(names) if not names.is_empty() else "等待选角")
	_ready_button.disabled = local.is_empty() or String(local.get("character_id", "")).is_empty() or local.get("ready", false)
	var needed := 1 if _is_debug() else 3
	var can_start := members.size() == needed
	for player: Dictionary in members:
		can_start = can_start and player.get("ready", false) and not String(player.get("character_id", "")).is_empty()
	_start_button.disabled = not can_start
	_start_button.text = "进入棋盘" if can_start else "等待准备"

func _build_board() -> void:
	var column := _new_page("board")
	var header := _header("棋盘", "单猫调试" if _is_debug() else "三人同局")
	header.add_child(HomeTheme.button("返回入口", "LeaveBoardButton", _leave))
	column.add_child(header)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	column.add_child(body)
	_player_column = VBoxContainer.new()
	_player_column.name = "PlayerStatusColumn"
	_player_column.custom_minimum_size.x = 176
	body.add_child(_player_column)
	_board = HomeBoardView.new()
	_board.name = "BoardView"
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.tile_selected.connect(_on_tile_selected)
	body.add_child(_board)
	var detail := PanelContainer.new()
	detail.name = "TileDetail"
	detail.custom_minimum_size.x = 214
	body.add_child(detail)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 176
	detail.add_child(box)
	_tile_title = HomeTheme.label("", 25)
	box.add_child(_tile_title)
	_tile_picture = TextureRect.new()
	_tile_picture.name = "TileIllustration"
	_tile_picture.custom_minimum_size = Vector2(160, 152)
	_tile_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tile_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(_tile_picture)
	_tile_hint = HomeTheme.label("", 16)
	box.add_child(_tile_hint)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	_story_demo = HomeTheme.button("看一段故事", "StoryDemoButton", func() -> void: _network.request_story_demo())
	_story_demo.visible = _is_debug()
	box.add_child(_story_demo)
	_debug_move = HomeTheme.button("调试 · 移到这里", "DebugMoveButton", func() -> void: _network.request_debug_move(_selected_tile))
	_debug_move.visible = _is_debug()
	box.add_child(_debug_move)
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	_net_status = HomeTheme.label(_connection, 14)
	_net_status.add_theme_color_override("font_color", HomeTheme.MUTED)
	bottom.add_child(_net_status)
	bottom.add_child(HomeTheme.button("小猫仓库", "WarehouseButton", _show_warehouse))
	bottom.add_child(HomeTheme.button("我的猫", "MyCatButton", _show_cat))
	bottom.add_child(HomeTheme.button("设置", "SettingsButton", _show_settings))
	_on_tile_selected(_selected_tile)

func _refresh_board() -> void:
	var members: Array = _state.get("players", [])
	_board.set_players(members)
	_clear_children(_player_column)
	for player: Dictionary in members:
		var character := String(player.get("character_id", ""))
		if character.is_empty():
			continue
		var panel := PanelContainer.new()
		_player_column.add_child(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		var row := HBoxContainer.new()
		box.add_child(row)
		row.add_child(HomeTheme.portrait(character, 48))
		row.add_child(HomeTheme.label(GameRules.character_name(character), 22))
		box.add_child(HomeTheme.label("饱食度 %s/%s" % [GameRules.satiety_text(int(player.get("satiety_units", 6))), GameRules.satiety_text(int(player.get("satiety_cap_units", 10)))], 17))
		box.add_child(HomeTheme.label("等级 %d  ·  野性 %d/10" % [int(player.get("level", 1)), int(player.get("wildness", 0))], 15))
		if not player.get("connected", true):
			box.add_child(HomeTheme.label("暂时离线", 15))
	if _is_debug():
		var hint := HomeTheme.label("单猫调试\n正式房间需要3名玩家", 14)
		hint.add_theme_color_override("font_color", HomeTheme.MUTED)
		_player_column.add_child(hint)
	_debug_move.disabled = not _state.get("story", {}).is_empty() or not String(_state.get("waiting_reason", "")).is_empty()
	_story_demo.disabled = _debug_move.disabled
	_net_status.text = ("单猫调试" if _is_debug() else "联机房间") + " · 状态已同步 #%s" % _state.get("revision", 0)

func _on_tile_selected(tile_id: int) -> void:
	_selected_tile = tile_id
	if is_instance_valid(_board):
		_board.select_tile(tile_id)
	if not is_instance_valid(_tile_title):
		return
	_tile_title.text = "%02d  %s" % [tile_id, HomeBoardView.tile_name(tile_id)]
	_tile_picture.texture = HomeTheme.texture("res://assets/art/tiles/tile_%02d_v001.png" % tile_id)
	var hints := {1:"三兄弟最初的落脚处。",9:"草丛里，藏着新的线索。",20:"小可的医院，四季营业。",24:"森林公园的入口。"}
	_tile_hint.text = hints.get(tile_id, "点击棋盘中的小图，查看这个地方。")
	if _tile_picture.texture == null:
		_tile_picture.visible = false
	else:
		_tile_picture.visible = true

func _is_debug() -> bool:
	return _state.get("mode", "") == "single_cat_debug"

func _leave() -> void:
	_network.disconnect_from_server()
	_state.clear()
	_local_peer_id = 0
	_selected_tile = 1
	_show_entry()
	_show_message("已离开房间。")

func _modal(title: String, key: String, wide: bool = false, can_close: bool = true) -> VBoxContainer:
	_clear_children(_overlay)
	_modal_key = key
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.21, 0.16, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 70 if wide else 245)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 55 if wide else 105)
	_overlay.add_child(margin)
	var panel := PanelContainer.new()
	panel.name = "ModalPanel"
	margin.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	heading.add_child(HomeTheme.label(title, 27))
	if can_close:
		heading.add_child(HomeTheme.button("回棋盘", "ClosePanelButton", _close_modal))
	return column

func _close_modal(force: bool = false) -> void:
	if _modal_key.begins_with("story:") and not force:
		return
	_clear_children(_overlay)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_key = ""

func _show_warehouse() -> void:
	var box := _modal("小猫仓库", "warehouse")
	box.add_child(HomeTheme.label("库存和物品", 20))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	for item in ["猫草", "猫罐头", "猫条", "毛毯", "猫薄荷", "废纸壳", "鸡胸肉", "鲢鳙"]:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(panel)
		var label := HomeTheme.label(item + "\n—", 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(label)
	box.add_child(HomeTheme.label("接口预览 · 尚未接入补给结算", 15))

func _show_cat() -> void:
	var box := _modal("我的猫", "cat")
	var local: Dictionary = {}
	for player: Dictionary in _state.get("players", []):
		if player.get("peer_id") == _local_peer_id:
			local = player
	if local.is_empty():
		box.add_child(HomeTheme.label("角色状态尚未收到。", 22))
		return
	var character := String(local.get("character_id", ""))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	row.add_child(HomeTheme.portrait(character, 240))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var identity := HomeTheme.label(GameRules.character_name(character), 36)
	identity.name = "CatIdentity"
	info.add_child(identity)
	info.add_child(HomeTheme.label("等级 %d · 野性 %d/10" % [local.get("level",1),local.get("wildness",0)], 22))
	info.add_child(HomeTheme.label("饱食度 %s/%s" % [GameRules.satiety_text(local.get("satiety_units",6)),GameRules.satiety_text(local.get("satiety_cap_units",10))],22))
	info.add_child(HomeTheme.label("成长与技能 · 后续接入", 16))

func _show_settings() -> void:
	var box := _modal("显示设置", "settings")
	box.add_child(HomeTheme.label("保持画面比例，窗口变化时自动适配。", 20))
	box.add_child(HomeTheme.button("切换全屏 / 窗口", "FullscreenButton", func() -> void:
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	))
	box.add_child(HomeTheme.label("最小窗口 1280 × 720", 17))

func _show_story(story: Dictionary) -> void:
	var id := String(story.get("id", ""))
	var read_ids: Array = story.get("read_peer_ids", [])
	var key := "story:" + id + ":" + str(read_ids)
	if _modal_key == key:
		return
	var box := _modal(String(story.get("title", "共同的故事")), key, true, false)
	var grid := GridContainer.new()
	grid.name = "ComicGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	var lines: Array = story.get("lines", [])
	for i in range(lines.size()):
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(panel)
		var row := HBoxContainer.new()
		panel.add_child(row)
		var art := TextureRect.new()
		art.custom_minimum_size.x = 145
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = HomeTheme.texture("res://assets/art/tiles/tile_%02d_v001.png" % (1 if i < 2 else 24))
		row.add_child(art)
		var caption := HomeTheme.label("%02d\n%s" % [i+1, String(lines[i])], 19)
		caption.custom_minimum_size.x = 210
		row.add_child(caption)
	var footer := HBoxContainer.new()
	box.add_child(footer)
	var names := PackedStringArray()
	for player: Dictionary in _state.get("players", []):
		var name := GameRules.character_name(StringName(str(player.get("character_id", ""))))
		names.append(name + (" · 已看完" if read_ids.has(player.get("peer_id")) else " · 阅读中"))
	footer.add_child(HomeTheme.label("    ".join(names), 16))
	var read_button := HomeTheme.button("我看完了", "StoryReadButton", func() -> void: _network.mark_story_read(id))
	read_button.disabled = read_ids.has(_network.get_local_peer_id()) or not String(_state.get("waiting_reason","")).is_empty()
	footer.add_child(read_button)

func _show_message(message: String) -> void:
	if is_instance_valid(_toast):
		_toast.text = message

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_modal()
		get_viewport().set_input_as_handled()
