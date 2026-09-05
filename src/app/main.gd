extends Control
## 本地开局预览。界面收集选择，领域层校验并建立初始状态。

const DEFAULT_RULES: GameRules = preload("res://data/rules/default_rules.tres")
const INK := Color("#eee9d9")
const MUTED := Color("#afc2bb")
const ACCENT := Color("#cbe6aa")

var _selection_order: Array[StringName] = []
var _character_buttons: Dictionary = {}
var _order_label: Label
var _status_label: Label
var _preview_box: VBoxContainer
var _start_button: Button
var _session: GameSession


func _ready() -> void:
	_build_ui()
	_refresh_selection()


func _build_ui() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 18
	ui_theme.set_color("font_color", "Label", INK)
	ui_theme.set_color("font_color", "Button", INK)
	ui_theme.set_color("font_disabled_color", "Button", MUTED)
	ui_theme.set_stylebox("normal", "Button", _panel_style(Color("#28433f")))
	ui_theme.set_stylebox("hover", "Button", _panel_style(Color("#34564e")))
	ui_theme.set_stylebox("pressed", "Button", _panel_style(Color("#476447")))
	ui_theme.set_stylebox("disabled", "Button", _panel_style(Color("#20312e")))
	theme = ui_theme

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 38)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)

	var eyebrow := _label("三只猫 · 三位玩家 · 系统自动主持", 16)
	eyebrow.add_theme_color_override("font_color", ACCENT)
	column.add_child(eyebrow)
	column.add_child(_label("我们的家", 44))
	column.add_child(_label("从三兄弟的第一步开始。", 21))

	var scope := _label(
		"项目脚手架 / 本地预览\n当前可验证角色选择和初始状态。联网、棋盘行动与剧情尚未实现。", 16
	)
	scope.add_theme_color_override("font_color", MUTED)
	column.add_child(scope)
	column.add_child(HSeparator.new())
	column.add_child(_label("按玩家选择顺序，依次选择三只猫", 22))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	var relations := ["大哥", "二哥", "小弟"]
	for index in range(GameRules.CHARACTER_IDS.size()):
		var character_id := GameRules.CHARACTER_IDS[index]
		var button := Button.new()
		button.name = String(character_id) + "Button"
		button.text = GameRules.character_name(character_id) + "\n" + relations[index]
		button.custom_minimum_size = Vector2(180, 100)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_character.bind(character_id))
		row.add_child(button)
		_character_buttons[character_id] = button

	_order_label = _label("", 18)
	_order_label.name = "SelectionOrder"
	column.add_child(_order_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	column.add_child(actions)
	_start_button = Button.new()
	_start_button.name = "StartPreviewButton"
	_start_button.text = "建立本地预览"
	_start_button.custom_minimum_size = Vector2(190, 48)
	_start_button.pressed.connect(_create_preview)
	actions.add_child(_start_button)
	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重新选择"
	reset_button.custom_minimum_size = Vector2(150, 48)
	reset_button.pressed.connect(_reset_selection)
	actions.add_child(reset_button)

	_status_label = _label("", 16)
	_status_label.add_theme_color_override("font_color", ACCENT)
	column.add_child(_status_label)
	_preview_box = VBoxContainer.new()
	_preview_box.name = "SessionPreview"
	_preview_box.add_theme_constant_override("separation", 8)
	column.add_child(_preview_box)


func _select_character(character_id: StringName) -> void:
	if not GameRules.CHARACTER_IDS.has(character_id) or _selection_order.has(character_id):
		return
	_selection_order.append(character_id)
	_refresh_selection()


func _refresh_selection() -> void:
	var names := PackedStringArray()
	for character_id in _selection_order:
		names.append(GameRules.character_name(character_id))
	_order_label.text = "选择顺序：" + (" → ".join(names) if not names.is_empty() else "等待第一位玩家")
	for character_id in _character_buttons:
		var button: Button = _character_buttons[character_id]
		button.disabled = _selection_order.has(character_id)
	_start_button.disabled = _selection_order.size() != DEFAULT_RULES.player_count or _session != null


func _create_preview() -> void:
	_session = GameSession.create(DEFAULT_RULES, _selection_order)
	if _session == null:
		_status_label.text = GameSession.selection_error(DEFAULT_RULES, _selection_order)
		return
	_clear_preview()
	_status_label.text = "初始状态已建立。战斗出手顺序采用上面的玩家选择顺序。"
	var state := _session.snapshot()
	for player: Dictionary in state["players"]:
		var line := "%s  ·  等级 %d  ·  野性 %d/%d  ·  饱食度 %s/%s" % [
			GameRules.character_name(player["character_id"]),
			player["level"],
			player["wildness"],
			DEFAULT_RULES.level_wildness_requirements[player["level"] - 1],
			GameRules.satiety_text(player["satiety_units"]),
			GameRules.satiety_text(player["satiety_cap_units"]),
		]
		_preview_box.add_child(_label(line, 20))
	_refresh_selection()


func _reset_selection() -> void:
	_selection_order.clear()
	_session = null
	_status_label.text = ""
	_clear_preview()
	_refresh_selection()


func _clear_preview() -> void:
	for child in _preview_box.get_children():
		_preview_box.remove_child(child)
		child.queue_free()


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
