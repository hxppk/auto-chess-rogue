extends Control

const MAX_UNITS_ON_BOARD: int = 5

@onready var gold_label: Label = $VLayout/TopBarPanel/TopBar/GoldLabel
@onready var wave_label: Label = $VLayout/TopBarPanel/TopBar/WaveLabel
@onready var health_label: Label = $VLayout/BottomBarPanel/BottomBar/TownArea/HealthLabel
@onready var ready_button: Button = $VLayout/BottomBarPanel/BottomBar/TownArea/ReadyButton

@onready var top_bar_panel: PanelContainer = $VLayout/TopBarPanel
@onready var shop_panel: PanelContainer = $VLayout/MainArea/ShopPanel
@onready var info_panel_container: PanelContainer = $VLayout/MainArea/InfoPanelContainer
@onready var bottom_bar_panel: PanelContainer = $VLayout/BottomBarPanel
@onready var shop_title: Label = $VLayout/MainArea/ShopPanel/ShopArea/ShopTitle
@onready var shop_list: VBoxContainer = $VLayout/MainArea/ShopPanel/ShopArea/ShopList
@onready var info_title: Label = $VLayout/MainArea/InfoPanelContainer/InfoPanel/InfoTitle
@onready var unit_info_panel: UnitInfoPanel = $VLayout/MainArea/InfoPanelContainer/InfoPanel/UnitInfoPanel
@onready var board_area: Control = $VLayout/MainArea/BoardArea
@onready var hint_label: Label = $VLayout/HintLabel

var board_grid: BoardGrid
var selected_shop_unit_id: String = ""
var shop_cards: Dictionary = {}  # unit_id -> UnitShopCard
var _board_positioned: bool = false

# Selected unit tracking
var selected_unit: UnitData = null
var selected_unit_pos: Vector2i = Vector2i(-1, -1)

# Sell confirmation dialog
var _sell_dialog: ConfirmationDialog

# Drag-and-drop state
enum DragSource { NONE, SHOP, BOARD }
var _drag_active: bool = false
var _drag_source: int = DragSource.NONE
var _drag_unit_data = null  # UnitData or unit dict
var _drag_unit_id: String = ""  # for shop drags
var _drag_from_pos: Vector2i = Vector2i(-1, -1)  # board source cell
var _drag_ghost: Sprite2D = null
var _drag_ghost_layer: CanvasLayer = null
# Board press tracking (to distinguish click vs drag on board)
var _board_press_active: bool = false
var _board_press_pos: Vector2 = Vector2.ZERO
var _board_press_cell: Vector2i = Vector2i(-1, -1)
const DRAG_THRESHOLD: float = 5.0

func _ready():
	_apply_styles()

	_update_gold(GameState.gold)
	_update_health(GameState.health)
	_update_wave(GameState.current_wave)

	GameState.gold_changed.connect(_update_gold)
	GameState.health_changed.connect(_update_health)
	GameState.wave_changed.connect(_update_wave)

	ready_button.pressed.connect(_on_ready_pressed)

	# Setup hint label style
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.add_theme_color_override("font_color", ThemeManager.COLOR_DANGER)
	hint_label.visible = false

	# Instantiate BoardGrid
	var board_scene = preload("res://ui/BoardGrid.tscn")
	board_grid = board_scene.instantiate()
	board_area.add_child(board_grid)
	board_grid.cell_clicked.connect(_on_board_cell_clicked)

	# Connect info panel signals
	unit_info_panel.upgrade_requested.connect(_on_upgrade_requested)
	unit_info_panel.sell_requested.connect(_on_sell_requested)

	# Create sell confirmation dialog
	_sell_dialog = ConfirmationDialog.new()
	_sell_dialog.title = "确认出售"
	_sell_dialog.ok_button_text = "确认"
	_sell_dialog.cancel_button_text = "取消"
	_sell_dialog.confirmed.connect(_on_sell_confirmed)
	add_child(_sell_dialog)

	# Populate shop
	_populate_shop()

	# Restore board layout from GameState (when returning from battle)
	_restore_board()

func _process(_delta: float) -> void:
	if not _board_positioned and board_area.size.x > 0 and board_area.size.y > 0:
		var board_size = board_grid.get_board_size()
		board_grid.position = (board_area.size - board_size) / 2
		_board_positioned = true

# ----------------------------------------------------------
# Shop population
# ----------------------------------------------------------
func _populate_shop():
	var units = DataManager.units_data.get("units", {})
	for unit_id in units:
		var data = units[unit_id]
		var card = UnitShopCard.new()
		shop_list.add_child(card)
		card.setup(data)
		card.card_clicked.connect(_on_shop_card_clicked)
		card.card_drag_started.connect(_on_shop_card_drag_started)
		shop_cards[unit_id] = card

# Restore board from GameState (when returning from battle)
func _restore_board():
	for pos in GameState.board_layout:
		var unit_data = GameState.board_layout[pos]
		if unit_data is UnitData:
			board_grid.place_unit(pos.x, pos.y, unit_data)

func _on_shop_card_clicked(unit_id: String) -> void:
	# Toggle selection
	if selected_shop_unit_id == unit_id:
		selected_shop_unit_id = ""
	else:
		selected_shop_unit_id = unit_id

	# Update card visuals
	for id in shop_cards:
		shop_cards[id].set_selected(id == selected_shop_unit_id)

	# P1-6: 选中商店卡片时显示属性
	if selected_shop_unit_id != "":
		var unit_dict = DataManager.get_unit_data(selected_shop_unit_id)
		if not unit_dict.is_empty():
			unit_info_panel.show_shop_preview(unit_dict)
	else:
		if selected_unit == null:
			unit_info_panel.show_empty()

# ----------------------------------------------------------
# Board interaction - purchase and place / select unit
# ----------------------------------------------------------
func _on_board_cell_clicked(col: int, row: int) -> void:
	# Ignore clicks during active drag
	if _drag_active:
		return

	var cell_occupied = board_grid.is_occupied(col, row)

	# If a shop unit is selected (via click), try to place it
	if selected_shop_unit_id != "":
		if col > 2:
			_show_hint("只能放在己方区域 (左侧)!")
			return
		if cell_occupied:
			_show_hint("该格子已有单位!")
			return

		if board_grid.get_unit_count() >= MAX_UNITS_ON_BOARD:
			_show_hint("棋盘已满 (最多 %d 个)!" % MAX_UNITS_ON_BOARD)
			return

		_purchase_and_place(selected_shop_unit_id, col, row)
		return

	# No shop unit selected -- track press for potential board drag
	if cell_occupied:
		_board_press_active = true
		_board_press_pos = get_viewport().get_mouse_position()
		_board_press_cell = Vector2i(col, row)
		# Also select the unit immediately for info panel
		var unit_data = board_grid.get_unit(col, row)
		if unit_data is UnitData:
			_select_unit(col, row, unit_data)
	else:
		_deselect_unit()

func _select_unit(col: int, row: int, unit_data: UnitData) -> void:
	selected_unit = unit_data
	selected_unit_pos = Vector2i(col, row)
	unit_info_panel.show_unit(unit_data)

func _deselect_unit() -> void:
	selected_unit = null
	selected_unit_pos = Vector2i(-1, -1)
	unit_info_panel.show_empty()

# ----------------------------------------------------------
# Upgrade logic
# ----------------------------------------------------------
func _on_upgrade_requested() -> void:
	if selected_unit == null:
		return
	if not selected_unit.can_upgrade():
		_show_hint("已满级!")
		return

	var cost = selected_unit.get_upgrade_cost()
	if not GameState.spend_gold(cost):
		_show_hint("金币不足!")
		return

	selected_unit.upgrade()
	unit_info_panel.show_unit(selected_unit)
	board_grid.refresh_unit_visual(selected_unit_pos.x, selected_unit_pos.y)

# ----------------------------------------------------------
# Sell logic
# ----------------------------------------------------------
func _on_sell_requested() -> void:
	if selected_unit == null:
		return
	var sell_price = selected_unit.get_sell_price()
	_sell_dialog.dialog_text = "确认出售 %s？\n将获得 %d 金币" % [selected_unit.unit_name, sell_price]
	_sell_dialog.popup_centered(Vector2i(260, 120))

func _on_sell_confirmed() -> void:
	if selected_unit == null:
		return
	var sell_price = selected_unit.get_sell_price()
	GameState.add_gold(sell_price)

	var pos = selected_unit_pos
	board_grid.remove_unit(pos.x, pos.y)
	GameState.board_layout.erase(pos)

	# Remove from player_units if present
	var idx = GameState.player_units.find(selected_unit)
	if idx >= 0:
		GameState.player_units.remove_at(idx)

	_deselect_unit()

# ----------------------------------------------------------
# Hint message display
# ----------------------------------------------------------
func _show_hint(text: String) -> void:
	hint_label.text = text
	hint_label.visible = true
	# Auto-hide after 1.5 seconds
	var timer = get_tree().create_timer(1.5)
	timer.timeout.connect(func(): hint_label.visible = false)

# ----------------------------------------------------------
# Visual styling applied at runtime via ThemeManager colors
# ----------------------------------------------------------
func _apply_styles():
	# TopBar: darker panel
	_style_panel(top_bar_panel, Color(0.15, 0.12, 0.10), ThemeManager.COLOR_PANEL_BORDER)

	# BottomBar: same as top
	_style_panel(bottom_bar_panel, Color(0.15, 0.12, 0.10), ThemeManager.COLOR_PANEL_BORDER)

	# ShopArea panel
	_style_panel(shop_panel, ThemeManager.COLOR_PANEL_BG, ThemeManager.COLOR_PANEL_BORDER)

	# InfoPanel
	_style_panel(info_panel_container, ThemeManager.COLOR_PANEL_BG, ThemeManager.COLOR_PANEL_BORDER)

	# Gold label: gold accent color
	gold_label.add_theme_color_override("font_color", ThemeManager.COLOR_ACCENT)
	gold_label.add_theme_font_size_override("font_size", 18)

	# Wave label
	wave_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT)
	wave_label.add_theme_font_size_override("font_size", 18)

	# Health label: red-ish
	health_label.add_theme_color_override("font_color", ThemeManager.COLOR_DANGER)
	health_label.add_theme_font_size_override("font_size", 18)

	# Section titles
	shop_title.add_theme_font_size_override("font_size", 20)
	shop_title.add_theme_color_override("font_color", ThemeManager.COLOR_ACCENT)

	info_title.add_theme_font_size_override("font_size", 20)
	info_title.add_theme_color_override("font_color", ThemeManager.COLOR_ACCENT)

func _style_panel(panel: PanelContainer, bg: Color, border: Color):
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)

# ----------------------------------------------------------
# State updates
# ----------------------------------------------------------
func _update_gold(value: int):
	gold_label.text = "Gold: " + str(value)

func _update_health(value: int):
	health_label.text = "HP: " + str(value)

func _update_wave(value: int):
	wave_label.text = "Wave " + str(value) + " / " + str(GameState.max_waves)

# ----------------------------------------------------------
# Purchase helper (shared by click-to-place and drag-to-place)
# ----------------------------------------------------------
func _purchase_and_place(uid: String, col: int, row: int) -> bool:
	var unit_dict = DataManager.get_unit_data(uid)
	if unit_dict.is_empty():
		return false

	var cost = unit_dict.get("cost", 5)
	if not GameState.spend_gold(cost):
		_show_hint("金币不足!")
		return false

	var unit_data = UnitData.new()
	unit_data.init_from_dict(unit_dict)
	unit_data.position_on_board = Vector2i(col, row)
	unit_data.team = 0

	board_grid.place_unit(col, row, unit_data)
	GameState.board_layout[Vector2i(col, row)] = unit_data

	# Deselect shop card after purchase
	selected_shop_unit_id = ""
	for id in shop_cards:
		shop_cards[id].set_selected(false)

	# Select the newly placed unit
	_select_unit(col, row, unit_data)
	return true

# ----------------------------------------------------------
# Drag-and-drop
# ----------------------------------------------------------
func _input(event: InputEvent) -> void:
	# ESC cancels active drag
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _drag_active:
			_cancel_drag()
			get_viewport().set_input_as_handled()
			return

	# Detect board press -> drag transition
	if event is InputEventMouseMotion and _board_press_active and not _drag_active:
		if _board_press_pos.distance_to(event.position) >= DRAG_THRESHOLD:
			_board_press_active = false
			_start_board_drag(_board_press_cell)

	# During active drag: update ghost and highlight
	if event is InputEventMouseMotion and _drag_active:
		_update_drag(event.position)

	# Mouse release during drag: execute drop
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_board_press_active = false
		if _drag_active:
			_end_drag(event.position)
			get_viewport().set_input_as_handled()

func _on_shop_card_drag_started(uid: String) -> void:
	# Validate affordability
	var unit_dict = DataManager.get_unit_data(uid)
	if unit_dict.is_empty():
		return
	var cost = unit_dict.get("cost", 5)
	if GameState.gold < cost:
		_show_hint("金币不足!")
		return
	if board_grid.get_unit_count() >= MAX_UNITS_ON_BOARD:
		_show_hint("棋盘已满 (最多 %d 个)!" % MAX_UNITS_ON_BOARD)
		return

	_drag_active = true
	_drag_source = DragSource.SHOP
	_drag_unit_id = uid
	_drag_unit_data = unit_dict
	_drag_from_pos = Vector2i(-1, -1)

	# Deselect any shop card selection
	selected_shop_unit_id = ""
	for id in shop_cards:
		shop_cards[id].set_selected(false)

	_create_drag_ghost(uid, unit_dict)

func _start_board_drag(cell: Vector2i) -> void:
	var unit_data = board_grid.get_unit(cell.x, cell.y)
	if unit_data == null:
		return

	_drag_active = true
	_drag_source = DragSource.BOARD
	_drag_unit_data = unit_data
	_drag_unit_id = _get_unit_id_from_data(unit_data)
	_drag_from_pos = cell

	board_grid.hide_unit_visual(cell.x, cell.y)
	_create_drag_ghost_from_unit(unit_data)

func _create_drag_ghost(uid: String, unit_dict: Dictionary) -> void:
	_drag_ghost_layer = CanvasLayer.new()
	_drag_ghost_layer.layer = 100
	add_child(_drag_ghost_layer)

	_drag_ghost = Sprite2D.new()
	var role = unit_dict.get("role", "")
	if BoardGrid.ROLE_SPRITE_MAP.has(role):
		var tex = load(BoardGrid.ROLE_SPRITE_MAP[role])
		if tex:
			_drag_ghost.texture = tex
	_drag_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drag_ghost.scale = Vector2(4, 4)
	_drag_ghost.modulate = Color(1, 1, 1, 0.7)
	_drag_ghost.position = get_viewport().get_mouse_position()
	_drag_ghost_layer.add_child(_drag_ghost)

func _create_drag_ghost_from_unit(unit_data) -> void:
	_drag_ghost_layer = CanvasLayer.new()
	_drag_ghost_layer.layer = 100
	add_child(_drag_ghost_layer)

	_drag_ghost = Sprite2D.new()
	var role = ""
	if unit_data is UnitData:
		role = unit_data.role
	elif unit_data is Dictionary:
		role = unit_data.get("role", "")
	if BoardGrid.ROLE_SPRITE_MAP.has(role):
		var tex = load(BoardGrid.ROLE_SPRITE_MAP[role])
		if tex:
			_drag_ghost.texture = tex
	_drag_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drag_ghost.scale = Vector2(4, 4)
	_drag_ghost.modulate = Color(1, 1, 1, 0.7)
	_drag_ghost.position = get_viewport().get_mouse_position()
	_drag_ghost_layer.add_child(_drag_ghost)

func _update_drag(mouse_pos: Vector2) -> void:
	if _drag_ghost:
		_drag_ghost.position = mouse_pos

	# Update drag highlight on board
	var cell = board_grid.get_cell_from_global(mouse_pos)
	if cell.x >= 0:
		board_grid.set_drag_highlight(cell)
	else:
		board_grid.clear_drag_highlight()

func _end_drag(mouse_pos: Vector2) -> void:
	var target_cell = board_grid.get_cell_from_global(mouse_pos)

	if target_cell.x < 0:
		# Dropped outside board
		_cancel_drag()
		return

	if _drag_source == DragSource.SHOP:
		# Shop -> board: must be empty cell on player side
		if target_cell.x > 2:
			_show_hint("只能放在己方区域 (左侧)!")
			_cancel_drag()
			return
		if board_grid.is_occupied(target_cell.x, target_cell.y):
			_show_hint("该格子已有单位!")
			_cancel_drag()
			return
		var shop_uid = _drag_unit_id
		_cleanup_drag()
		_purchase_and_place(shop_uid, target_cell.x, target_cell.y)

	elif _drag_source == DragSource.BOARD:
		if target_cell == _drag_from_pos:
			# Dropped on same cell - cancel
			_cancel_drag()
			return

		# 限制移动到己方区域
		if target_cell.x > 2:
			_show_hint("只能放在己方区域 (左侧)!")
			_cancel_drag()
			return

		var from_pos = _drag_from_pos
		var dragged_unit = _drag_unit_data

		if board_grid.is_occupied(target_cell.x, target_cell.y):
			# Swap two units
			board_grid.show_unit_visual(from_pos.x, from_pos.y)
			var other_unit = board_grid.get_unit(target_cell.x, target_cell.y)
			board_grid.swap_units(from_pos.x, from_pos.y, target_cell.x, target_cell.y)
			# Sync GameState
			_sync_position(dragged_unit, target_cell)
			_sync_position(other_unit, from_pos)
			GameState.board_layout.erase(from_pos)
			GameState.board_layout.erase(target_cell)
			GameState.board_layout[target_cell] = dragged_unit
			GameState.board_layout[from_pos] = other_unit
			_cleanup_drag()
			# Update selection to follow dragged unit
			_select_unit(target_cell.x, target_cell.y, dragged_unit)
		else:
			# Move to empty cell
			board_grid.show_unit_visual(from_pos.x, from_pos.y)
			board_grid.move_unit(from_pos.x, from_pos.y, target_cell.x, target_cell.y)
			# Sync GameState
			_sync_position(dragged_unit, target_cell)
			GameState.board_layout.erase(from_pos)
			GameState.board_layout[target_cell] = dragged_unit
			_cleanup_drag()
			# Update selection to follow dragged unit
			_select_unit(target_cell.x, target_cell.y, dragged_unit)

func _cancel_drag() -> void:
	if _drag_source == DragSource.BOARD and _drag_from_pos.x >= 0:
		board_grid.show_unit_visual(_drag_from_pos.x, _drag_from_pos.y)
	_cleanup_drag()

func _cleanup_drag() -> void:
	_drag_active = false
	_drag_source = DragSource.NONE
	_drag_unit_data = null
	_drag_unit_id = ""
	_drag_from_pos = Vector2i(-1, -1)
	_board_press_active = false
	board_grid.clear_drag_highlight()
	if _drag_ghost_layer and is_instance_valid(_drag_ghost_layer):
		_drag_ghost_layer.queue_free()
		_drag_ghost_layer = null
	_drag_ghost = null

func _sync_position(unit_data, pos: Vector2i) -> void:
	if unit_data is UnitData:
		unit_data.position_on_board = pos

func _get_unit_id_from_data(unit_data) -> String:
	if unit_data is UnitData:
		return unit_data.id
	elif unit_data is Dictionary:
		return unit_data.get("id", "")
	return ""

func _on_ready_pressed():
	get_tree().change_scene_to_file("res://scenes/level_select/LevelSelectScene.tscn")
