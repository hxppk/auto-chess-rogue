extends Node2D
class_name BoardGrid

signal cell_clicked(col: int, row: int)
signal cell_hovered(col: int, row: int)
signal unit_placed(col: int, row: int, unit_data)
signal unit_removed(col: int, row: int)

const COLS: int = 5
const ROWS: int = 7
const CELL_SIZE: int = 100
const CELL_GAP: int = 2
const COLOR_LIGHT: Color = Color(0.55, 0.48, 0.38)
const COLOR_DARK: Color = Color(0.42, 0.36, 0.28)
const COLOR_HOVER: Color = Color(0.5, 0.75, 0.5, 0.4)
const COLOR_SELECTED: Color = Color(0.4, 0.65, 0.95, 0.5)
const COLOR_OCCUPIED: Color = Color(0.7, 0.55, 0.35, 0.3)
const COLOR_GRID_LINE: Color = Color(0.3, 0.25, 0.2, 0.4)
const COLOR_BOARD_BORDER: Color = Color(0.35, 0.28, 0.2, 0.8)
const COLOR_DROP_VALID: Color = Color(0.3, 0.9, 0.3, 0.4)

# 角色精灵映射 (role -> tile path) - 玩家单位
const ROLE_SPRITE_MAP: Dictionary = {
	"近战坦克": "res://assets/kenney_tiny-dungeon/Tiles/tile_0122.png",
	"近战输出": "res://assets/kenney_tiny-dungeon/Tiles/tile_0087.png",
	"远程物理": "res://assets/kenney_tiny-dungeon/Tiles/tile_0108.png",
	"远程魔法": "res://assets/kenney_tiny-dungeon/Tiles/tile_0084.png",
	"远程治疗": "res://assets/kenney_tiny-dungeon/Tiles/tile_0121.png",
}

# 敌方精灵映射 (enemy id -> tile path)
const ENEMY_SPRITE_MAP: Dictionary = {
	"wolf": "res://assets/kenney_tiny-dungeon/Tiles/tile_0110.png",
	"goblin": "res://assets/kenney_tiny-dungeon/Tiles/tile_0088.png",
	"goblin_archer": "res://assets/kenney_tiny-dungeon/Tiles/tile_0114.png",
	"ogre": "res://assets/kenney_tiny-dungeon/Tiles/tile_0112.png",
	"shadow_mage": "res://assets/kenney_tiny-dungeon/Tiles/tile_0099.png",
	"boss_redmane": "res://assets/kenney_tiny-dungeon/Tiles/tile_0120.png",
}

# 格子数据：grid[col][row] = unit_data or null
var grid: Array = []
var hovered_cell: Vector2i = Vector2i(-1, -1)
var selected_cell: Vector2i = Vector2i(-1, -1)
var drag_target_cell: Vector2i = Vector2i(-1, -1)

# 战斗模式：隐藏格子线
var battle_mode: bool = false

# 单位节点引用
var unit_nodes: Dictionary = {}  # Vector2i -> Node2D

# 选中特效节点
var _selection_highlight: Node2D = null

# 方向标签字体
var _side_label_font: Font = null
var _side_label_font_size: int = 14

func _ready():
	_side_label_font = ThemeDB.fallback_font
	_init_grid()

func _init_grid():
	grid.clear()
	for col in range(COLS):
		var column = []
		for row in range(ROWS):
			column.append(null)
		grid.append(column)

func _draw():
	var board_width = COLS * (CELL_SIZE + CELL_GAP) - CELL_GAP
	var board_height = ROWS * (CELL_SIZE + CELL_GAP) - CELL_GAP

	if not battle_mode:
		# 准备阶段：显示格子
		# 棋盘外围边框
		var board_rect = Rect2(-3, -3, board_width + 6, board_height + 6)
		draw_rect(board_rect, COLOR_BOARD_BORDER, false, 2.0)

		for col in range(COLS):
			for row in range(ROWS):
				var rect = _get_cell_rect(col, row)
				var base_color = COLOR_LIGHT if (col + row) % 2 == 0 else COLOR_DARK
				draw_rect(rect, base_color)
				if grid[col][row] != null:
					draw_rect(rect, COLOR_OCCUPIED)
				if Vector2i(col, row) == selected_cell:
					draw_rect(rect, COLOR_SELECTED)
				elif Vector2i(col, row) == drag_target_cell:
					draw_rect(rect, COLOR_DROP_VALID)
				elif Vector2i(col, row) == hovered_cell:
					draw_rect(rect, COLOR_HOVER)
				draw_rect(rect, COLOR_GRID_LINE, false, 1.0)

		# 中线分隔（col 2 和 col 3 之间）- 竖向虚线
		var mid_x = 3 * (CELL_SIZE + CELL_GAP) - 1
		var dash_len = 12.0
		var gap_len = 8.0
		var y = 0.0
		while y < board_height:
			var seg_end = minf(y + dash_len, board_height)
			draw_line(Vector2(mid_x, y), Vector2(mid_x, seg_end), Color(0.9, 0.8, 0.5, 0.35), 2.0)
			y += dash_len + gap_len

	# 方向标签（横版：我方在左，敌方在右）
	if _side_label_font:
		# 我方标签 - 棋盘左侧
		var ally_text = "我方 ▶"
		var ally_y = board_height / 2 + 5
		draw_string(_side_label_font, Vector2(-55, ally_y), ally_text, HORIZONTAL_ALIGNMENT_CENTER, -1, _side_label_font_size, Color(0.4, 0.7, 0.9, 0.7))
		# 敌方标签 - 棋盘右侧
		var enemy_text = "◀ 敌方"
		draw_string(_side_label_font, Vector2(board_width + 8, ally_y), enemy_text, HORIZONTAL_ALIGNMENT_CENTER, -1, _side_label_font_size, Color(0.9, 0.4, 0.35, 0.7))

func _get_cell_rect(col: int, row: int) -> Rect2:
	var x = col * (CELL_SIZE + CELL_GAP)
	var y = row * (CELL_SIZE + CELL_GAP)
	return Rect2(x, y, CELL_SIZE, CELL_SIZE)

func _get_cell_from_position(pos: Vector2) -> Vector2i:
	var col = int(pos.x / (CELL_SIZE + CELL_GAP))
	var row = int(pos.y / (CELL_SIZE + CELL_GAP))
	if col >= 0 and col < COLS and row >= 0 and row < ROWS:
		var rect = _get_cell_rect(col, row)
		if rect.has_point(pos):
			return Vector2i(col, row)
	return Vector2i(-1, -1)

func _input(event):
	if event is InputEventMouseMotion:
		var local_pos = to_local(event.position)
		var cell = _get_cell_from_position(local_pos)
		if cell != hovered_cell:
			hovered_cell = cell
			cell_hovered.emit(cell.x, cell.y)
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos = to_local(event.position)
			var cell = _get_cell_from_position(local_pos)
			if cell.x >= 0:
				selected_cell = cell
				cell_clicked.emit(cell.x, cell.y)
				_update_selection_highlight()
				queue_redraw()

func get_board_size() -> Vector2:
	return Vector2(
		COLS * (CELL_SIZE + CELL_GAP) - CELL_GAP,
		ROWS * (CELL_SIZE + CELL_GAP) - CELL_GAP
	)

# 公共接口
func place_unit(col: int, row: int, unit_data) -> bool:
	if not _is_valid_cell(col, row):
		return false
	if grid[col][row] != null:
		return false
	grid[col][row] = unit_data
	_create_unit_visual(col, row, unit_data)
	unit_placed.emit(col, row, unit_data)
	queue_redraw()
	return true

func remove_unit(col: int, row: int):
	if not _is_valid_cell(col, row):
		return null
	var unit = grid[col][row]
	grid[col][row] = null
	_remove_unit_visual(col, row)
	if unit:
		unit_removed.emit(col, row)
	queue_redraw()
	return unit

func get_unit(col: int, row: int):
	if not _is_valid_cell(col, row):
		return null
	return grid[col][row]

func is_occupied(col: int, row: int) -> bool:
	if not _is_valid_cell(col, row):
		return true
	return grid[col][row] != null

func get_all_units() -> Array:
	var units = []
	for col in range(COLS):
		for row in range(ROWS):
			if grid[col][row] != null:
				units.append({"col": col, "row": row, "unit": grid[col][row]})
	return units

func clear_board():
	for col in range(COLS):
		for row in range(ROWS):
			if grid[col][row] != null:
				remove_unit(col, row)

func get_unit_count() -> int:
	var count = 0
	for col in range(COLS):
		for row in range(ROWS):
			if grid[col][row] != null:
				count += 1
	return count

func _is_valid_cell(col: int, row: int) -> bool:
	return col >= 0 and col < COLS and row >= 0 and row < ROWS

func _get_unit_id(unit_data) -> String:
	if unit_data is UnitData:
		return unit_data.id
	elif unit_data is Dictionary:
		return unit_data.get("id", "")
	return ""

func _get_unit_team(unit_data) -> int:
	if unit_data is UnitData:
		return unit_data.team
	elif unit_data is Dictionary:
		return unit_data.get("team", 0)
	return 0

func _get_sprite_path(unit_data) -> String:
	var team = _get_unit_team(unit_data)
	if team == 1:
		# 敌方：优先按 id 查找敌方精灵
		var uid = _get_unit_id(unit_data)
		if ENEMY_SPRITE_MAP.has(uid):
			return ENEMY_SPRITE_MAP[uid]
	# 玩家或敌方 fallback：按 role 查找
	var role = _get_unit_role(unit_data)
	if ROLE_SPRITE_MAP.has(role):
		return ROLE_SPRITE_MAP[role]
	return ""

func _create_unit_visual(col: int, row: int, unit_data):
	var unit_visual = Node2D.new()
	unit_visual.name = "Unit_%d_%d" % [col, row]
	var rect = _get_cell_rect(col, row)
	unit_visual.position = rect.position + rect.size / 2

	# 深色底框做"卡片"效果
	var card_bg = ColorRect.new()
	var card_size = Vector2(CELL_SIZE * 0.8, CELL_SIZE * 0.8)
	card_bg.size = card_size
	card_bg.position = -card_size / 2
	card_bg.color = Color(0.15, 0.12, 0.1, 0.6)
	unit_visual.add_child(card_bg)

	# 尝试加载精灵（敌方用 ENEMY_SPRITE_MAP，玩家用 ROLE_SPRITE_MAP）
	var sprite_path = _get_sprite_path(unit_data)
	var sprite_loaded = false

	if sprite_path != "":
		var tex = load(sprite_path)
		if tex:
			var sprite = Sprite2D.new()
			sprite.texture = tex
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2(4, 4)  # 16px -> 64px 适合 100px 格子
			sprite.position = Vector2(0, -4)  # 稍微上移给名称留空间
			unit_visual.add_child(sprite)
			sprite_loaded = true

	# 如果精灵加载失败，使用改进的 ColorRect
	if not sprite_loaded:
		var color = _get_role_color(unit_data)
		var fallback = ColorRect.new()
		var fb_size = Vector2(75, 75)
		fallback.size = fb_size
		fallback.position = -fb_size / 2 + Vector2(0, -4)
		fallback.color = color
		unit_visual.add_child(fallback)

	# 单位名称标签 - 白色居中
	var label = Label.new()
	if unit_data is UnitData:
		label.text = unit_data.unit_name
	elif unit_data is Dictionary:
		label.text = unit_data.get("name", "?")
	else:
		label.text = "?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	# 居中定位：使用足够宽度并居中
	label.custom_minimum_size = Vector2(CELL_SIZE, 0)
	label.size = Vector2(CELL_SIZE, 16)
	label.position = Vector2(-CELL_SIZE * 0.5, CELL_SIZE * 0.22)
	unit_visual.add_child(label)

	# 等级标签（右下角小字）
	var unit_level = 1
	if unit_data is UnitData:
		unit_level = unit_data.level
	elif unit_data is Dictionary:
		unit_level = unit_data.get("level", 1)

	var level_label = Label.new()
	level_label.text = "Lv." + str(unit_level)
	level_label.add_theme_font_size_override("font_size", 11)
	level_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))  # 金色
	level_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	level_label.add_theme_constant_override("shadow_offset_x", 1)
	level_label.add_theme_constant_override("shadow_offset_y", 1)
	level_label.position = Vector2(CELL_SIZE * 0.15, -CELL_SIZE * 0.4)
	unit_visual.add_child(level_label)

	# 技能名称标签（P1-5）
	var skill_id_str = ""
	if unit_data is UnitData:
		skill_id_str = unit_data.skill_id
	elif unit_data is Dictionary:
		skill_id_str = unit_data.get("skill", "")
	if skill_id_str != "":
		var skill_data = SkillSystem.get_skill_data(skill_id_str)
		var skill_name_text = skill_data.get("name", "")
		if skill_name_text != "":
			var skill_label = Label.new()
			skill_label.name = "SkillLabel"
			skill_label.text = skill_name_text
			skill_label.add_theme_font_size_override("font_size", 9)
			skill_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
			skill_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
			skill_label.add_theme_constant_override("shadow_offset_x", 1)
			skill_label.add_theme_constant_override("shadow_offset_y", 1)
			skill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			skill_label.custom_minimum_size = Vector2(CELL_SIZE, 0)
			skill_label.size = Vector2(CELL_SIZE, 12)
			skill_label.position = Vector2(-CELL_SIZE * 0.5, CELL_SIZE * 0.35)
			unit_visual.add_child(skill_label)

	add_child(unit_visual)
	unit_nodes[Vector2i(col, row)] = unit_visual

func refresh_unit_visual(col: int, row: int):
	var key = Vector2i(col, row)
	if not unit_nodes.has(key):
		return
	var unit_data = grid[col][row]
	if unit_data == null:
		return
	# Remove old visual and recreate
	unit_nodes[key].queue_free()
	unit_nodes.erase(key)
	# Defer creation so the old node is freed first
	_create_unit_visual.call_deferred(col, row, unit_data)

func _remove_unit_visual(col: int, row: int):
	var key = Vector2i(col, row)
	if unit_nodes.has(key):
		unit_nodes[key].queue_free()
		unit_nodes.erase(key)
	# 清除选中高亮如果移除的是选中单位
	if selected_cell == key:
		_clear_selection_highlight()

func _get_unit_role(unit_data) -> String:
	if unit_data is UnitData:
		return unit_data.role
	elif unit_data is Dictionary:
		return unit_data.get("role", "")
	return ""

func _get_role_color(unit_data) -> Color:
	var role = _get_unit_role(unit_data)
	match role:
		"近战坦克": return Color(0.3, 0.5, 0.9)    # 蓝色
		"近战输出": return Color(0.9, 0.3, 0.3)    # 红色
		"远程物理": return Color(0.2, 0.8, 0.3)    # 绿色
		"远程魔法": return Color(0.7, 0.3, 0.9)    # 紫色
		"远程治疗": return Color(0.9, 0.9, 0.3)    # 黄色
		_: return Color(0.7, 0.7, 0.7)             # 灰色

# ---- 拖拽相关公共接口 ----
func get_cell_from_global(global_pos: Vector2) -> Vector2i:
	var local_pos = to_local(global_pos)
	return _get_cell_from_position(local_pos)

func move_unit(from_col: int, from_row: int, to_col: int, to_row: int) -> bool:
	if not _is_valid_cell(from_col, from_row) or not _is_valid_cell(to_col, to_row):
		return false
	if grid[from_col][from_row] == null or grid[to_col][to_row] != null:
		return false
	var unit_data = grid[from_col][from_row]
	grid[from_col][from_row] = null
	grid[to_col][to_row] = unit_data
	_remove_unit_visual(from_col, from_row)
	_create_unit_visual(to_col, to_row, unit_data)
	queue_redraw()
	return true

func swap_units(col_a: int, row_a: int, col_b: int, row_b: int) -> bool:
	if not _is_valid_cell(col_a, row_a) or not _is_valid_cell(col_b, row_b):
		return false
	if grid[col_a][row_a] == null or grid[col_b][row_b] == null:
		return false
	var unit_a = grid[col_a][row_a]
	var unit_b = grid[col_b][row_b]
	grid[col_a][row_a] = unit_b
	grid[col_b][row_b] = unit_a
	_remove_unit_visual(col_a, row_a)
	_remove_unit_visual(col_b, row_b)
	_create_unit_visual(col_a, row_a, unit_b)
	_create_unit_visual(col_b, row_b, unit_a)
	queue_redraw()
	return true

func hide_unit_visual(col: int, row: int) -> void:
	var key = Vector2i(col, row)
	if unit_nodes.has(key):
		unit_nodes[key].visible = false

func show_unit_visual(col: int, row: int) -> void:
	var key = Vector2i(col, row)
	if unit_nodes.has(key):
		unit_nodes[key].visible = true

func set_drag_highlight(cell: Vector2i) -> void:
	if drag_target_cell != cell:
		drag_target_cell = cell
		queue_redraw()

func clear_drag_highlight() -> void:
	if drag_target_cell != Vector2i(-1, -1):
		drag_target_cell = Vector2i(-1, -1)
		queue_redraw()

# ---- 选中高亮特效 ----
func _update_selection_highlight():
	_clear_selection_highlight()
	if selected_cell.x < 0 or not unit_nodes.has(selected_cell):
		return
	# 在选中单位周围添加蓝色描边矩形
	_selection_highlight = Node2D.new()
	_selection_highlight.name = "SelectionHighlight"
	var highlight_draw = _SelectionRect.new()
	highlight_draw.cell_size = CELL_SIZE
	_selection_highlight.add_child(highlight_draw)
	var unit_node = unit_nodes[selected_cell]
	unit_node.add_child(_selection_highlight)

func _clear_selection_highlight():
	if _selection_highlight and is_instance_valid(_selection_highlight):
		_selection_highlight.queue_free()
		_selection_highlight = null

# 内部类：选中单位的蓝色描边矩形
class _SelectionRect extends Node2D:
	var cell_size: int = 100

	func _draw():
		var half = cell_size * 0.45
		var rect = Rect2(-half, -half, half * 2, half * 2)
		# 外层发光（半透明蓝色，稍大）
		var glow_rect = rect.grow(2)
		draw_rect(glow_rect, Color(0.4, 0.65, 0.95, 0.25))
		# 蓝色描边
		draw_rect(rect, Color(0.4, 0.7, 1.0, 0.8), false, 2.0)
