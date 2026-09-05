class_name HomeBoardView
extends Control
## 原棋盘格位展示，选格与状态更新分开；此层不决定合法行走路线。
signal tile_selected(tile_id: int)

const TILES := [
	[1,7,1,"烂尾楼"],[2,7,2,"草丛"],[3,7,3,"土路"],[4,7,4,"游乐场"],
	[5,6,4,"公园钓鱼点"],[6,5,4,"池塘入水口"],[7,4,4,"白沙池"],[8,4,5,"邪恶鹅大哥"],
	[9,4,6,"公园草丛"],[10,7,5,"10路公交车站"],[11,7,6,"广场"],[12,7,7,"下水道"],
	[13,6,7,"健身房"],[14,5,7,"餐馆"],[15,4,7,"幸福小区"],[16,3,7,"16路公交车站"],
	[17,2,7,"墓地"],[18,1,7,"废品处理厂"],[19,1,6,"小溪"],[20,1,5,"宠物医院"],
	[21,1,4,"公告栏"],[22,1,3,"海莉"],[23,1,2,"23路公交车站"],[24,1,1,"公园入口"],
	[25,2,1,"流浪猫聚集地"],[26,3,1,"丧彪"],[27,4,1,"树林"],[28,5,1,"养殖场"],[29,6,1,"草丛"],
]
var selected_id: int = 1
var players: Array = []
var _rectangles: Dictionary = {}
var _pictures: Dictionary = {}
var _hovered: int = 0
var _token_views: Dictionary = {}
var _token_material: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var mask := Shader.new()
	mask.code = "shader_type canvas_item; void fragment() { vec4 pixel=texture(TEXTURE,(UV-vec2(0.5))*1.15+vec2(0.5)); float edge=1.0-smoothstep(0.48,0.5,length(UV-vec2(0.5))); COLOR=vec4(pixel.rgb,pixel.a*edge); }"
	_token_material = ShaderMaterial.new()
	_token_material.shader = mask
	custom_minimum_size = Vector2(420, 420)
	resized.connect(queue_redraw)
	mouse_exited.connect(func() -> void: _hovered = 0; queue_redraw())
	for tile: Array in TILES:
		var picture := HomeTheme.texture("res://assets/art/tiles/tile_%02d_v001.png" % tile[0])
		if picture != null:
			_pictures[tile[0]] = picture

func set_players(value: Array) -> void:
	players = value.duplicate(true)
	queue_redraw()

func select_tile(value: int) -> void:
	selected_id = value
	queue_redraw()

func tile_rect(tile_id: int) -> Rect2:
	return _rectangles.get(tile_id, Rect2())

static func tile_name(tile_id: int) -> String:
	for tile: Array in TILES:
		if tile[0] == tile_id:
			return tile[3]
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		var id := _tile_at(event.position)
		if event is InputEventMouseMotion and _hovered != id:
			_hovered = id
			tooltip_text = "%02d · %s" % [id, tile_name(id)] if id > 0 else ""
			queue_redraw()
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and id > 0:
			selected_id = id
			tile_selected.emit(id)
			queue_redraw()
			accept_event()

func _tile_at(point: Vector2) -> int:
	for tile_id: int in _rectangles:
		if _rectangles[tile_id].has_point(point):
			return tile_id
	return 0

func _draw() -> void:
	_rectangles.clear()
	var side := minf(size.x - 8, size.y - 8)
	var origin := (size - Vector2.ONE * side) * 0.5
	var step := side / 7.0
	var font := ThemeDB.fallback_font
	var land := Rect2(origin + Vector2(step * 1.1, step * 1.1), Vector2(step * 4.8, step * 4.8))
	var base := HomeTheme.panel(Color("#e4ead7"), 70, 0)
	draw_style_box(base, land)
	# 环境占位采用轻量地形；每格独立图片可逐步替换。
	draw_circle(origin + Vector2(step * 2.4, step * 4.6), step * 1.1, Color("#d2dfbd"))
	draw_circle(origin + Vector2(step * 4.8, step * 5.1), step * 0.72, Color("#bbd9cf"))
	draw_circle(origin + Vector2(step * 5.0, step * 5.0), step * 0.57, Color("#cce5db"))
	draw_string(font, origin + Vector2(step * 1.6, step * 2.05), "我们的家", HORIZONTAL_ALIGNMENT_CENTER, step * 3.7, 37, HomeTheme.INK)
	draw_string(font, origin + Vector2(step * 1.6, step * 2.48), "三只猫的小天地", HORIZONTAL_ALIGNMENT_CENTER, step * 3.7, 16, HomeTheme.MUTED)
	for tile: Array in TILES:
		var id: int = tile[0]
		var cell := Rect2(origin + Vector2((tile[2] - 1) * step, (tile[1] - 1) * step), Vector2.ONE * (step - 4))
		_rectangles[id] = cell
		var style := HomeTheme.panel(Color("#faf8ef"), 10, 0)
		if id == selected_id:
			style.border_color = HomeTheme.LEAF
			style.set_border_width_all(3)
			style.bg_color = Color("#e8efda")
		elif id == _hovered:
			style.bg_color = Color("#e5ebd7")
		draw_style_box(style, cell)
		var image_rect := Rect2(cell.position + Vector2(5, 5), Vector2(cell.size.x - 10, cell.size.y - 24))
		if _pictures.has(id):
			var picture_side := minf(image_rect.size.x, image_rect.size.y)
			var picture_rect := Rect2(image_rect.get_center() - Vector2.ONE * picture_side * 0.5, Vector2.ONE * picture_side)
			draw_texture_rect(_pictures[id], picture_rect, false)
		else:
			_draw_placeholder(id, image_rect)
		draw_string(font, cell.position + Vector2(6, cell.size.y - 5), "%02d" % id, HORIZONTAL_ALIGNMENT_LEFT, 26, 12, HomeTheme.MUTED)
		# 仅选中/悬停格显示地名，棋盘常驻文字保持简短。
		if id == selected_id or id == _hovered:
			var title: String = tile[3]
			if title.length() > 5:
				title = title.substr(0, 4) + "…"
			draw_string(font, cell.position + Vector2(27, cell.size.y - 5), title, HORIZONTAL_ALIGNMENT_CENTER, cell.size.x - 31, 12, HomeTheme.INK)
	_draw_tokens(step)

func _draw_placeholder(id: int, rect: Rect2) -> void:
	var center := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.32
	var forest := [2,3,5,6,7,9,19,24,27,28,29].has(id)
	if [5,6,19].has(id):
		draw_ellipse_shape(center, Vector2(r * 1.45, r * 0.65), Color("#92bdb8"))
		draw_arc(center, r * 0.7, 0, PI, 16, Color("#e7f1df"), 2, true)
	elif [10,16,23].has(id):
		draw_style_box(HomeTheme.panel(Color("#d6b67d"), 7, 0), Rect2(center - Vector2(r, r * 0.65), Vector2(r * 2, r * 1.3)))
		draw_rect(Rect2(center - Vector2(r * 0.7, r * 0.42), Vector2(r * 1.4, r * 0.55)), Color("#edf1e2"))
		draw_circle(center + Vector2(-r * 0.58, r * 0.7), r * 0.18, HomeTheme.INK)
		draw_circle(center + Vector2(r * 0.58, r * 0.7), r * 0.18, HomeTheme.INK)
	elif forest:
		draw_line(center + Vector2(0, r), center - Vector2(0, r * 0.6), Color("#ad8b60"), 5, true)
		for offset in [Vector2(-0.65, -0.1), Vector2(0.55, 0), Vector2(0, -0.6)]:
			draw_circle(center + offset * r, r * 0.65, Color("#98b875") if id % 2 == 0 else Color("#b5c58b"))
	elif [8,22,25,26].has(id):
		draw_circle(center, r, Color("#d9c99c"))
		draw_circle(center + Vector2(-r * 0.32, -r * 0.1), 2, HomeTheme.INK)
		draw_circle(center + Vector2(r * 0.32, -r * 0.1), 2, HomeTheme.INK)
	else:
		var color := Color("#d8c3a0")
		draw_rect(Rect2(center - Vector2(r * 0.8, r * 0.4), Vector2(r * 1.6, r * 1.35)), color)
		draw_colored_polygon(PackedVector2Array([center + Vector2(-r, -r * 0.35), center + Vector2(0, -r * 1.2), center + Vector2(r, -r * 0.35)]), Color("#a8ae84"))
		draw_rect(Rect2(center + Vector2(-r * 0.17, r * 0.25), Vector2(r * 0.35, r * 0.68)), Color("#b39c73"))
		if id == 20:
			draw_line(center - Vector2(r * 0.4, 0), center + Vector2(r * 0.4, 0), Color("#789577"), 5)
			draw_line(center - Vector2(0, r * 0.4), center + Vector2(0, r * 0.4), Color("#789577"), 5)

func draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(32):
		var angle := TAU * i / 32.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)

func _draw_tokens(step: float) -> void:
	for view: TextureRect in _token_views.values():
		view.visible = false
	var grouped: Dictionary = {}
	for player: Dictionary in players:
		if String(player.get("character_id", "")).is_empty():
			continue
		var tile_id: int = int(player.get("tile_id", 1))
		if not grouped.has(tile_id):
			grouped[tile_id] = []
		grouped[tile_id].append(player)
	for tile_id: int in grouped:
		if not _rectangles.has(tile_id):
			continue
		var row: Array = grouped[tile_id]
		var rect: Rect2 = _rectangles[tile_id]
		var radius := minf(24, step * 0.29)
		for i in range(row.size()):
			var player: Dictionary = row[i]
			var texture := HomeTheme.cat_texture(String(player["character_id"]))
			var center := rect.get_center() + Vector2((i - (row.size() - 1) * 0.5) * radius * 1.32, -5)
			draw_circle(center, radius + 3, Color("#fcf5df"))
			draw_arc(center, radius + 3, 0, TAU, 40, HomeTheme.INK, 2, true)
			if texture != null:
				var character := String(player["character_id"])
				if not _token_views.has(character):
					var portrait := HomeTheme.portrait(character, 0)
					portrait.name = character + "BoardToken"
					portrait.material = _token_material
					add_child(portrait)
					_token_views[character] = portrait
				var view: TextureRect = _token_views[character]
				view.position = center - Vector2.ONE * radius
				view.size = Vector2.ONE * radius * 2
				view.visible = true
