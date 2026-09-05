class_name HomeTheme
extends RefCounted
## 共用色板与控件。布局比例不写入图片。
const INK := Color("#334e42")
const MUTED := Color("#77866f")
const PAPER := Color("#f5f0e2")
const LEAF := Color("#718a54")
const LINE := Color("#c5cfb8")

static func panel(fill: Color = Color("#fffaf0"), radius: int = 14, padding: int = 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.border_color = LINE
	style.set_border_width_all(1)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

static func create() -> Theme:
	var result := Theme.new()
	result.default_font_size = 18
	result.set_color("font_color", "Label", INK)
	for control in ["Button", "CheckButton", "LineEdit"]:
		result.set_color("font_color", control, INK)
		result.set_color("font_hover_color", control, INK)
		result.set_color("font_pressed_color", control, INK)
		result.set_color("font_disabled_color", control, Color("#99a58e"))
	result.set_stylebox("normal", "Button", panel())
	result.set_stylebox("hover", "Button", panel(Color("#e4ebd8")))
	result.set_stylebox("pressed", "Button", panel(Color("#d0dfbc")))
	result.set_stylebox("disabled", "Button", panel(Color("#e9eadf")))
	var focus := panel(Color(0, 0, 0, 0))
	focus.border_color = Color("#b88b42")
	focus.set_border_width_all(3)
	result.set_stylebox("focus", "Button", focus)
	result.set_stylebox("normal", "LineEdit", panel())
	result.set_stylebox("panel", "PanelContainer", panel())
	result.set_constant("separation", "VBoxContainer", 12)
	result.set_constant("separation", "HBoxContainer", 12)
	return result

static func label(value: String, points: int = 18) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", points)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func button(value: String, node_name: String, action: Callable) -> Button:
	var result := Button.new()
	result.name = node_name
	result.text = value
	result.custom_minimum_size.y = 44
	result.pressed.connect(action)
	return result

static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

static func cat_texture(character: String) -> Texture2D:
	var token := texture("res://assets/art/cats/%s_token_v001.png" % character)
	if token != null:
		return token
	var references := {
		"sanhua": "res://assets/art/cats/sanhua_reference.png",
		"buou": "res://assets/art/cats/buou_reference.png",
		"nainiu": "res://assets/art/cats/nainiu_reference.png",
	}
	return texture(references.get(character, ""))

static func portrait(character: String, points: int = 64) -> TextureRect:
	var result := TextureRect.new()
	result.texture = cat_texture(character)
	result.custom_minimum_size = Vector2(points, points)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result
