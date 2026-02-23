extends Control

# 战斗棋盘（复用 BoardGrid 组件）
var battle_board: BoardGrid

# 血条/蓝条映射
var health_bars: Dictionary = {}  # UnitData -> HealthBar 实例
var mana_bars: Dictionary = {}    # UnitData -> HealthBar 实例（蓝色）

# UI 节点
@onready var wave_info_label: Label = $TopBar/HBox/WaveInfoLabel
@onready var speed_button: Button = $BottomBar/HBox/SpeedButton
@onready var board_area: Control = $BoardArea

var result_overlay: Control  # 战斗结束遮罩
var stats_panel: Control     # 伤害统计面板
var stats_toggle_button: Button  # 统计面板开关
var stats_visible: bool = false

var battle_speed: float = 1.0
var _board_positioned: bool = false

func _ready():
	wave_info_label.text = "Wave %d / %d" % [GameState.current_wave, GameState.max_waves]
	speed_button.text = "1x"
	speed_button.pressed.connect(_on_speed_toggle)

	# 实例化战斗棋盘
	var board_scene = preload("res://ui/BoardGrid.tscn")
	battle_board = board_scene.instantiate()
	battle_board.battle_mode = true  # P2-9: 战斗隐藏格子
	board_area.add_child(battle_board)

	# 创建结果遮罩（隐藏）
	_create_result_overlay()

	# 创建伤害统计面板（P1-8）
	_create_stats_panel()

	# 统计面板开关按钮
	stats_toggle_button = Button.new()
	stats_toggle_button.text = "统计"
	stats_toggle_button.custom_minimum_size = Vector2(60, 0)
	stats_toggle_button.pressed.connect(_on_stats_toggle)
	$BottomBar/HBox.add_child(stats_toggle_button)

	# 连接 BattleEngine 信号
	BattleEngine.battle_started.connect(_on_battle_started)
	BattleEngine.unit_moved.connect(_on_unit_moved)
	BattleEngine.unit_attacked.connect(_on_unit_attacked)
	BattleEngine.unit_damaged.connect(_on_unit_damaged)
	BattleEngine.unit_healed.connect(_on_unit_healed)
	BattleEngine.unit_died.connect(_on_unit_died)
	BattleEngine.battle_ended.connect(_on_battle_ended)
	BattleEngine.skill_used.connect(_on_skill_used)
	BattleEngine.tick_processed.connect(_on_tick_processed)

	# 获取双方阵容并开始战斗
	var player_army = GameState.get_player_army()
	var enemy_army = GameState.current_enemy_army

	if player_army.is_empty():
		# 没有单位，直接判负
		_show_result("DEFEAT", false)
		return

	# 延迟两帧开始战斗（等棋盘布局完成）
	await get_tree().process_frame
	await get_tree().process_frame
	BattleEngine.start_battle(player_army, enemy_army)

func _process(_delta):
	if not _board_positioned and board_area.size.x > 0:
		var board_size = battle_board.get_board_size()
		battle_board.position = (board_area.size - board_size) / 2
		_board_positioned = true

# ---- 信号处理 ----

func _on_battle_started(player_units: Array, enemy_units: Array):
	# 在棋盘上放置所有单位
	for unit in player_units:
		var pos = unit.position_on_board
		battle_board.place_unit(pos.x, pos.y, unit)
		_add_health_bar(unit, pos)
		_add_mana_bar(unit, pos)

	for unit in enemy_units:
		var pos = unit.position_on_board
		battle_board.place_unit(pos.x, pos.y, unit)
		_add_health_bar(unit, pos)
		_add_mana_bar(unit, pos)

func _on_unit_moved(unit: UnitData, from_pos: Vector2i, to_pos: Vector2i):
	# P2-10: 平滑移动动画（不重新创建视觉节点）
	var from_key = from_pos
	var to_key = to_pos

	# 更新棋盘数据（不触发视觉重建）
	battle_board.grid[from_pos.x][from_pos.y] = null
	battle_board.grid[to_pos.x][to_pos.y] = unit

	# 移动视觉节点引用并做动画
	if battle_board.unit_nodes.has(from_key):
		var visual = battle_board.unit_nodes[from_key]
		battle_board.unit_nodes.erase(from_key)
		battle_board.unit_nodes[to_key] = visual
		visual.name = "Unit_%d_%d" % [to_pos.x, to_pos.y]

		var target_rect = battle_board._get_cell_rect(to_pos.x, to_pos.y)
		var target_center = target_rect.position + target_rect.size / 2
		var tween = create_tween()
		tween.tween_property(visual, "position", target_center, 0.15)

	# 更新血条/蓝条位置（也做平滑动画）
	_animate_bar_position(unit, to_pos)

func _on_unit_attacked(attacker: UnitData, target: UnitData, damage_info: Dictionary):
	# 攻击动画：攻击者节点微微向目标方向移动后弹回
	var attacker_visual = _get_unit_visual(attacker)
	if attacker_visual:
		var dir = Vector2(
			target.position_on_board.x - attacker.position_on_board.x,
			target.position_on_board.y - attacker.position_on_board.y
		).normalized() * 10
		var original_pos = attacker_visual.position
		var tween = create_tween()
		tween.tween_property(attacker_visual, "position", original_pos + dir, 0.1)
		tween.tween_property(attacker_visual, "position", original_pos, 0.1)

func _on_unit_damaged(unit: UnitData, amount: int, remaining_hp: int, damage_info: Dictionary):
	# 闪红效果
	var visual = _get_unit_visual(unit)
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "modulate", Color(1, 0.3, 0.3), 0.1)
		tween.tween_property(visual, "modulate", Color(1, 1, 1), 0.2)

	# 更新血条
	if health_bars.has(unit):
		health_bars[unit].set_value(remaining_hp, unit.max_hp)

	# 伤害飘字（根据类型区分颜色）
	var color = Color(1, 1, 1)  # 默认白色（物理）
	var font_size = 18
	var text = str(amount)

	match damage_info.get("type", "physical"):
		"magic":
			color = Color(0.7, 0.4, 1.0)  # 紫色
		"mixed":
			color = Color(0.7, 0.4, 1.0)  # 紫色
		"skill":
			color = Color(1.0, 0.6, 0.2)  # 橙色

	if damage_info.get("is_crit", false):
		color = Color(1.0, 0.6, 0.1)  # 暴击橙色
		font_size = 24
		text = str(amount) + "!"

	_spawn_damage_text(unit.position_on_board, text, color, font_size)

func _on_unit_healed(unit: UnitData, amount: int, remaining_hp: int):
	# 闪绿效果
	var visual = _get_unit_visual(unit)
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "modulate", Color(0.3, 1, 0.3), 0.1)
		tween.tween_property(visual, "modulate", Color(1, 1, 1), 0.2)

	# 更新血条
	if health_bars.has(unit):
		health_bars[unit].set_value(remaining_hp, unit.max_hp)

	# 治疗飘字（绿色）
	_spawn_damage_text(unit.position_on_board, "+" + str(amount), Color(0.3, 1, 0.4))

func _on_unit_died(unit: UnitData, pos: Vector2i):
	# 淡出消失
	var visual = _get_unit_visual(unit)
	if visual:
		var tween = create_tween()
		tween.tween_property(visual, "modulate:a", 0.0, 0.5)
		tween.tween_callback(func():
			battle_board.remove_unit(pos.x, pos.y)
		)

	# 移除血条和蓝条
	if health_bars.has(unit):
		health_bars[unit].queue_free()
		health_bars.erase(unit)
	if mana_bars.has(unit):
		mana_bars[unit].queue_free()
		mana_bars.erase(unit)

func _on_battle_ended(winner: String, _stats: Dictionary):
	var won = (winner == "player")
	GameState.set_meta("battle_won", won)
	GameState.set_meta("battle_stats", _stats)
	var difficulty = GameState.get_meta("selected_difficulty", "normal")
	GameState.set_meta("battle_difficulty", difficulty)

	var text = "VICTORY!" if won else "DEFEAT"
	_show_result(text, won)

	# 显示最终统计
	_update_stats_panel()
	stats_panel.visible = true

	# 延迟 2.5 秒后跳转结算
	var timer = get_tree().create_timer(2.5)
	timer.timeout.connect(func():
		get_tree().change_scene_to_file("res://scenes/result/ResultScene.tscn")
	)

func _on_skill_used(unit: UnitData, skill_id: String, targets: Array):
	var skill_data = SkillSystem.get_skill_data(skill_id)
	var skill_name = skill_data.get("name", "")

	# 技能名飘字（金色）
	_spawn_damage_text(unit.position_on_board, skill_name, Color(1.0, 0.85, 0.2), 20)

	# 根据技能类型播放不同特效
	match skill_id:
		"shattered_earth":
			_play_flash_effect(unit.position_on_board, Color(1.0, 0.9, 0.3, 0.6))  # 黄色闪光
		"charged_shot":
			_play_flash_effect(unit.position_on_board, Color(1.0, 1.0, 1.0, 0.6))  # 白色闪光
			for target in targets:
				_play_flash_effect(target.position_on_board, Color(1.0, 1.0, 1.0, 0.4))
		"quick_heal":
			for target in targets:
				_play_flash_effect(target.position_on_board, Color(0.3, 1.0, 0.5, 0.5))  # 绿色光圈
		"iron_charge":
			_play_flash_effect(unit.position_on_board, Color(1.0, 0.2, 0.2, 0.6))  # 红色闪光
			_play_screen_shake()

func _on_tick_processed(_tick_number: int):
	# 每 tick 更新所有蓝条
	for unit in mana_bars:
		if unit is UnitData and unit.is_alive:
			mana_bars[unit].set_value(unit.mp, unit.max_mp)

	# 每 tick 更新技能标签高亮（蓝条满时金色发光）
	for unit in mana_bars:
		if unit is UnitData and unit.is_alive:
			var visual = _get_unit_visual(unit)
			if visual:
				var skill_label = visual.get_node_or_null("SkillLabel")
				if skill_label:
					if unit.mp >= unit.max_mp:
						skill_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
						skill_label.modulate = Color(1.2, 1.1, 0.8)
					else:
						skill_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
						skill_label.modulate = Color(1, 1, 1)

	# 定期更新统计面板（每 10 tick）
	if _tick_number % 10 == 0 and stats_visible:
		_update_stats_panel()

# ---- 辅助方法 ----

func _on_speed_toggle():
	if battle_speed == 1.0:
		battle_speed = 2.0
		speed_button.text = "2x"
	else:
		battle_speed = 1.0
		speed_button.text = "1x"
	BattleEngine.set_speed(battle_speed)

func _on_stats_toggle():
	stats_visible = not stats_visible
	stats_panel.visible = stats_visible
	if stats_visible:
		_update_stats_panel()

func _get_unit_visual(unit: UnitData) -> Node2D:
	var pos = unit.position_on_board
	var key = Vector2i(pos.x, pos.y)
	if battle_board.unit_nodes.has(key):
		return battle_board.unit_nodes[key]
	return null

func _add_health_bar(unit: UnitData, pos: Vector2i):
	var hb = HealthBar.new()
	hb.setup(60.0, 6.0, Color(0.85, 0.2, 0.2))
	var cell_rect = battle_board._get_cell_rect(pos.x, pos.y)
	hb.position = cell_rect.position + Vector2(cell_rect.size.x / 2 - 30, -8)
	hb.set_value(unit.hp, unit.max_hp)
	battle_board.add_child(hb)
	health_bars[unit] = hb

func _add_mana_bar(unit: UnitData, pos: Vector2i):
	# 只对有技能的单位显示蓝条
	if unit.skill_id == "":
		return
	var mb = HealthBar.new()
	mb.setup(60.0, 4.0, Color(0.3, 0.5, 0.9))
	var cell_rect = battle_board._get_cell_rect(pos.x, pos.y)
	mb.position = cell_rect.position + Vector2(cell_rect.size.x / 2 - 30, -1)
	mb.set_value(unit.mp, unit.max_mp)
	battle_board.add_child(mb)
	mana_bars[unit] = mb

func _animate_bar_position(unit: UnitData, to_pos: Vector2i):
	var cell_rect = battle_board._get_cell_rect(to_pos.x, to_pos.y)
	var hp_target = cell_rect.position + Vector2(cell_rect.size.x / 2 - 30, -8)
	var mp_target = cell_rect.position + Vector2(cell_rect.size.x / 2 - 30, -1)

	if health_bars.has(unit):
		var tween = create_tween()
		tween.tween_property(health_bars[unit], "position", hp_target, 0.15)
	if mana_bars.has(unit):
		var tween = create_tween()
		tween.tween_property(mana_bars[unit], "position", mp_target, 0.15)

func _spawn_damage_text(board_pos: Vector2i, text: String, color: Color, font_size: int = 18):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var cell_rect = battle_board._get_cell_rect(board_pos.x, board_pos.y)
	label.position = cell_rect.position + Vector2(cell_rect.size.x / 2 - 20, cell_rect.size.y / 2 - 10)
	battle_board.add_child(label)

	# 飘字动画：向上飘 + 渐隐
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)

func _play_flash_effect(board_pos: Vector2i, color: Color):
	var cell_rect = battle_board._get_cell_rect(board_pos.x, board_pos.y)
	var flash = ColorRect.new()
	flash.color = color
	flash.position = cell_rect.position
	flash.size = cell_rect.size
	battle_board.add_child(flash)

	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.4)
	tween.tween_callback(flash.queue_free)

func _play_screen_shake():
	var original_pos = battle_board.position
	var tween = create_tween()
	tween.tween_property(battle_board, "position", original_pos + Vector2(5, 0), 0.05)
	tween.tween_property(battle_board, "position", original_pos + Vector2(-5, 0), 0.05)
	tween.tween_property(battle_board, "position", original_pos + Vector2(3, 0), 0.05)
	tween.tween_property(battle_board, "position", original_pos + Vector2(-3, 0), 0.05)
	tween.tween_property(battle_board, "position", original_pos, 0.05)

func _create_result_overlay():
	result_overlay = ColorRect.new()
	result_overlay.color = Color(0, 0, 0, 0.6)
	result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_overlay.visible = false
	result_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result_overlay)

	var result_label = Label.new()
	result_label.name = "ResultText"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_label.add_theme_font_size_override("font_size", 48)
	result_overlay.add_child(result_label)

func _show_result(text: String, is_victory: bool):
	result_overlay.visible = true
	var result_label = result_overlay.get_node("ResultText")
	result_label.text = text
	var color = Color(0.3, 1, 0.4) if is_victory else Color(1, 0.3, 0.3)
	result_label.add_theme_color_override("font_color", color)

# ---- 伤害统计面板（P1-8）----

func _create_stats_panel():
	stats_panel = PanelContainer.new()
	stats_panel.visible = false
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 固定大小和位置（右侧悬浮）
	stats_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	stats_panel.offset_left = -280
	stats_panel.offset_right = -10
	stats_panel.offset_top = -200
	stats_panel.offset_bottom = 200

	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.06, 0.85)
	sb.border_color = Color(0.5, 0.4, 0.3, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	stats_panel.add_theme_stylebox_override("panel", sb)

	var scroll = ScrollContainer.new()
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.name = "StatsContent"
	vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(vbox)

	# 标题
	var title = Label.new()
	title.text = "-- 战斗统计 --"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	vbox.add_child(title)

	add_child(stats_panel)

func _update_stats_panel():
	if not stats_panel:
		return
	var scroll = stats_panel.get_child(0)
	if not scroll:
		return
	var vbox = scroll.get_node_or_null("StatsContent")
	if not vbox:
		return

	# 清除旧的统计行（保留标题）
	while vbox.get_child_count() > 1:
		var child = vbox.get_child(1)
		vbox.remove_child(child)
		child.queue_free()

	var stats = BattleEngine.battle_stats
	if stats.is_empty():
		return

	# 表头
	var header = Label.new()
	header.text = "名称       伤害   承伤   治疗   击杀"
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	vbox.add_child(header)

	# 分隔线
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# 玩家单位
	var player_label = Label.new()
	player_label.text = "[ 我方 ]"
	player_label.add_theme_font_size_override("font_size", 11)
	player_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9))
	vbox.add_child(player_label)

	for unit in stats:
		if not (unit is UnitData) or unit.team != 0:
			continue
		var s = stats[unit]
		var alive_mark = "" if unit.is_alive else " [x]"
		var row = Label.new()
		row.text = "%s%s  %d  %d  %d  %d" % [
			unit.unit_name, alive_mark,
			s.get("damage_dealt", 0),
			s.get("damage_taken", 0),
			s.get("heals_done", 0),
			s.get("kills", 0)
		]
		row.add_theme_font_size_override("font_size", 11)
		if not unit.is_alive:
			row.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		vbox.add_child(row)

	# 敌方单位
	var enemy_label = Label.new()
	enemy_label.text = "[ 敌方 ]"
	enemy_label.add_theme_font_size_override("font_size", 11)
	enemy_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.35))
	vbox.add_child(enemy_label)

	for unit in stats:
		if not (unit is UnitData) or unit.team != 1:
			continue
		var s = stats[unit]
		var alive_mark = "" if unit.is_alive else " [x]"
		var row = Label.new()
		row.text = "%s%s  %d  %d  %d  %d" % [
			unit.unit_name, alive_mark,
			s.get("damage_dealt", 0),
			s.get("damage_taken", 0),
			s.get("heals_done", 0),
			s.get("kills", 0)
		]
		row.add_theme_font_size_override("font_size", 11)
		if not unit.is_alive:
			row.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		vbox.add_child(row)
