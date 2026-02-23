extends Node

# ---- 信号 ----
signal battle_started(player_units: Array, enemy_units: Array)
signal unit_moved(unit: UnitData, from_pos: Vector2i, to_pos: Vector2i)
signal unit_attacked(attacker: UnitData, target: UnitData, damage_info: Dictionary)
signal unit_damaged(unit: UnitData, amount: int, remaining_hp: int, damage_info: Dictionary)
signal unit_healed(unit: UnitData, amount: int, remaining_hp: int)
signal unit_died(unit: UnitData, position: Vector2i)
signal battle_ended(winner: String, stats: Dictionary)
signal tick_processed(tick_number: int)
signal skill_used(unit: UnitData, skill_id: String, targets: Array)

# ---- 状态 ----
var is_battling: bool = false
var speed_multiplier: float = 1.0
var tick_count: int = 0
var tick_interval: float = 0.1  # 每 tick 的基础时间间隔（秒）

# 棋盘尺寸（5列×7行，横版，向右进攻）
const BOARD_COLS: int = 5
const BOARD_ROWS: int = 7

# 战斗单位列表
var player_units: Array = []  # Array of UnitData
var enemy_units: Array = []
var all_units: Array = []

# 棋盘占用表 grid[col][row] = UnitData or null
var battle_grid: Array = []

# 每个单位的攻击计时器
var attack_timers: Dictionary = {}  # UnitData -> float (剩余时间)

# 战斗统计
var battle_stats: Dictionary = {}  # UnitData -> {damage_dealt, damage_taken, heals_done, kills}

var _timer_accumulator: float = 0.0

func _ready():
	set_process(false)

func start_battle(p_units: Array, e_units: Array) -> void:
	# 初始化棋盘
	_init_grid()

	player_units = p_units.duplicate()
	enemy_units = e_units.duplicate()
	all_units = player_units + enemy_units

	# 将单位放到棋盘上
	for unit in all_units:
		var pos = unit.position_on_board
		if _is_valid(pos.x, pos.y) and battle_grid[pos.x][pos.y] == null:
			battle_grid[pos.x][pos.y] = unit
			unit.is_alive = true
		else:
			# 找个空位
			_place_unit_auto(unit)

	# 初始化攻击计时器（首次攻击需要等一个完整的 SPD 周期）
	for unit in all_units:
		attack_timers[unit] = unit.spd
		# 初始化技能冷却
		unit.skill_attack_counter = 0
		unit.buffs.clear()
		var skill_data = SkillSystem.get_skill_data(unit.skill_id)
		if skill_data.has("cooldown_ticks"):
			unit.skill_cooldown_ticks = skill_data["cooldown_ticks"]
		else:
			unit.skill_cooldown_ticks = 0

	# 初始化战斗统计
	battle_stats.clear()
	for unit in all_units:
		battle_stats[unit] = {
			"damage_dealt": 0,
			"damage_taken": 0,
			"heals_done": 0,
			"kills": 0
		}

	tick_count = 0
	is_battling = true
	_timer_accumulator = 0.0

	battle_started.emit(player_units, enemy_units)
	set_process(true)

func stop_battle() -> void:
	is_battling = false
	set_process(false)

func set_speed(multiplier: float) -> void:
	speed_multiplier = multiplier

func _process(delta: float) -> void:
	if not is_battling:
		return

	_timer_accumulator += delta * speed_multiplier

	while _timer_accumulator >= tick_interval:
		_timer_accumulator -= tick_interval
		_process_tick()

		if not is_battling:
			break

func _process_tick() -> void:
	tick_count += 1

	# 处理 buff 递减
	SkillSystem.process_buffs(all_units)

	# Boss tick 冷却递减
	for unit in all_units:
		if unit.is_alive and unit.skill_cooldown_ticks > 0:
			var skill_data = SkillSystem.get_skill_data(unit.skill_id)
			if skill_data.has("cooldown_ticks"):
				unit.skill_cooldown_ticks -= 1

	# 处理每个存活单位
	for unit in all_units:
		if not unit.is_alive:
			continue

		# 减少攻击计时器
		attack_timers[unit] -= tick_interval

		if attack_timers[unit] <= 0:
			# 重置计时器
			attack_timers[unit] = unit.spd

			# 尝试执行动作
			_unit_action(unit)

	# 检查胜负
	_check_battle_end()

	tick_processed.emit(tick_count)

func _unit_action(unit: UnitData) -> void:
	var enemies = _get_enemies(unit)
	if enemies.is_empty():
		return

	var target = _find_nearest_enemy(unit, enemies)
	if target == null:
		return

	var dist = _manhattan_distance(unit.position_on_board, target.position_on_board)

	# 检查技能是否就绪（MP 满 100）
	if SkillSystem.has_skill(unit) and SkillSystem.is_skill_ready(unit):
		_do_skill(unit)
		return

	# 牧师特殊：治疗最低血量友方
	if unit.role == "远程治疗":
		_do_heal(unit)
		# 攻击/治疗后获得 MP
		unit.gain_mp(5)
		return

	# 在攻击范围内 → 攻击
	if dist <= unit.arg:
		_do_attack(unit, target)
		# 攻击后获得 MP (+5)
		unit.gain_mp(5)
	else:
		# 索敌范围 > 攻击范围：在索敌范围内则移动
		var detection = unit.get_detection_range()
		if dist <= detection:
			_move_toward(unit, target.position_on_board)
		# 超出索敌范围：不行动

func _do_skill(unit: UnitData) -> void:
	var allies = _get_allies(unit)
	var enemies = _get_enemies(unit)
	var skill = SkillSystem.get_skill_data(unit.skill_id)
	var results = SkillSystem.execute_skill(unit, allies, enemies, battle_grid)

	if results.is_empty():
		# 技能没有找到有效目标，执行普攻
		if unit.role == "远程治疗":
			_do_heal(unit)
		else:
			var target = _find_nearest_enemy(unit, enemies)
			if target and _manhattan_distance(unit.position_on_board, target.position_on_board) <= unit.arg:
				_do_attack(unit, target)
		unit.skill_attack_counter += 1
		return

	var skill_targets: Array = []

	for result in results:
		var target = result["target"]
		skill_targets.append(target)

		if result.get("type", "") == "heal":
			var actual = target.heal(result["amount"])
			if actual > 0:
				var heal_info = {"amount": actual, "type": "heal", "is_crit": false, "damage": 0, "skill_name": skill.get("name", "")}
				unit_attacked.emit(unit, target, heal_info)
				unit_healed.emit(target, actual, target.hp)
				_update_stat(unit, "heals_done", actual)
		else:
			var damage = result.get("damage", 0)
			var damage_info = {
				"damage": damage,
				"is_crit": false,
				"type": "skill",
				"skill_name": skill.get("name", "")
			}
			unit_attacked.emit(unit, target, damage_info)
			var actual = target.take_damage(damage)
			unit_damaged.emit(target, actual, target.hp, damage_info)
			_update_stat(unit, "damage_dealt", actual)
			_update_stat(target, "damage_taken", actual)

			if not target.is_alive:
				_update_stat(unit, "kills", 1)
				_handle_death(target)

		# 应用 buff/effect
		var effect = result.get("effect", "none")
		if effect != "none" and effect != "knockback":
			SkillSystem.apply_buff(target, effect, result.get("effect_value", 0), result.get("effect_duration_ticks", 0))

		# 击退效果
		if result.get("effect", "") == "knockback" and target.is_alive:
			var kb_dist = result.get("effect_value", 2)
			var old_pos = target.position_on_board
			var new_pos = SkillSystem.apply_knockback(target, unit.position_on_board, kb_dist, battle_grid, BOARD_COLS, BOARD_ROWS)
			if new_pos != old_pos:
				unit_moved.emit(target, old_pos, new_pos)

	# 发射技能使用信号
	skill_used.emit(unit, unit.skill_id, skill_targets)

	# 释放技能后 MP 归零
	unit.mp = 0
	# Boss 用 tick 冷却
	if skill.has("cooldown_ticks"):
		unit.skill_cooldown_ticks = skill["cooldown_ticks"]

func _do_attack(attacker: UnitData, target: UnitData) -> void:
	# 物理伤害 - 使用 effective ARM（考虑 buff）
	var effective_arm = target.get_effective_arm()
	var phys_result = DamageCalc.calc_physical_damage(attacker.ad, effective_arm)
	var total_damage = phys_result["damage"]
	var is_crit = phys_result["is_crit"]
	var damage_type = "physical"

	# 如果有 AP，额外造成魔法伤害
	if attacker.ap > 0 and attacker.role != "远程治疗":
		var magic_value = attacker.ad * attacker.ap
		var magic_result = DamageCalc.calc_magic_damage(magic_value, target.mdf)
		total_damage += magic_result["damage"]
		if magic_result["is_crit"]:
			is_crit = true
		damage_type = "mixed" if phys_result["damage"] > 0 else "magic"

	var damage_info = {
		"damage": total_damage,
		"is_crit": is_crit,
		"type": damage_type
	}

	unit_attacked.emit(attacker, target, damage_info)

	# 应用伤害
	var actual = target.take_damage(total_damage)
	unit_damaged.emit(target, actual, target.hp, damage_info)

	# 统计
	_update_stat(attacker, "damage_dealt", actual)
	_update_stat(target, "damage_taken", actual)

	# 死亡检查
	if not target.is_alive:
		_update_stat(attacker, "kills", 1)
		_handle_death(target)

func _do_heal(healer: UnitData) -> void:
	var allies = _get_allies(healer)
	var lowest: UnitData = null
	var lowest_ratio: float = 1.0

	for ally in allies:
		if not ally.is_alive:
			continue
		var ratio = float(ally.hp) / float(ally.max_hp)
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			lowest = ally

	if lowest == null or lowest_ratio >= 1.0:
		return  # 无人需要治疗

	var heal_amount = int(healer.ad * (1.0 + healer.ap))
	var actual = lowest.heal(heal_amount)

	if actual > 0:
		var heal_info = {"amount": actual, "type": "heal", "is_crit": false, "damage": 0}
		unit_attacked.emit(healer, lowest, heal_info)
		unit_healed.emit(lowest, actual, lowest.hp)
		_update_stat(healer, "heals_done", actual)

func _move_toward(unit: UnitData, target_pos: Vector2i) -> void:
	var from = unit.position_on_board
	var best_pos = from
	var best_dist = _manhattan_distance(from, target_pos)

	# 尝试四个方向
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for dir in directions:
		var new_pos = from + dir
		if _is_valid(new_pos.x, new_pos.y) and battle_grid[new_pos.x][new_pos.y] == null:
			var d = _manhattan_distance(new_pos, target_pos)
			if d < best_dist:
				best_dist = d
				best_pos = new_pos

	if best_pos != from:
		battle_grid[from.x][from.y] = null
		battle_grid[best_pos.x][best_pos.y] = unit
		var old_pos = unit.position_on_board
		unit.position_on_board = best_pos
		unit_moved.emit(unit, old_pos, best_pos)

func _handle_death(unit: UnitData) -> void:
	var pos = unit.position_on_board
	battle_grid[pos.x][pos.y] = null
	unit_died.emit(unit, pos)

func _check_battle_end() -> void:
	var player_alive = false
	var enemy_alive = false
	for u in player_units:
		if u.is_alive:
			player_alive = true
			break
	for u in enemy_units:
		if u.is_alive:
			enemy_alive = true
			break

	if not enemy_alive:
		is_battling = false
		set_process(false)
		battle_ended.emit("player", battle_stats)
	elif not player_alive:
		is_battling = false
		set_process(false)
		battle_ended.emit("enemy", battle_stats)

func _update_stat(unit: UnitData, stat_key: String, value: int) -> void:
	if battle_stats.has(unit):
		battle_stats[unit][stat_key] += value

# ---- 辅助函数 ----
func _get_enemies(unit: UnitData) -> Array:
	if unit.team == 0:
		return enemy_units.filter(func(u): return u.is_alive)
	else:
		return player_units.filter(func(u): return u.is_alive)

func _get_allies(unit: UnitData) -> Array:
	if unit.team == 0:
		return player_units.filter(func(u): return u.is_alive)
	else:
		return enemy_units.filter(func(u): return u.is_alive)

func _find_nearest_enemy(unit: UnitData, enemies: Array) -> UnitData:
	var nearest: UnitData = null
	var min_dist: int = 999
	for e in enemies:
		var d = _manhattan_distance(unit.position_on_board, e.position_on_board)
		if d < min_dist:
			min_dist = d
			nearest = e
	return nearest

func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _is_valid(col: int, row: int) -> bool:
	return col >= 0 and col < BOARD_COLS and row >= 0 and row < BOARD_ROWS

func _init_grid() -> void:
	battle_grid.clear()
	for col in range(BOARD_COLS):
		var column = []
		for row in range(BOARD_ROWS):
			column.append(null)
		battle_grid.append(column)

func _place_unit_auto(unit: UnitData) -> void:
	# 横版：玩家在左侧 cols 0-2，敌人在右侧 cols 3-4
	var start_col = 0 if unit.team == 0 else 3
	var end_col = 3 if unit.team == 0 else BOARD_COLS
	for col in range(start_col, end_col):
		for row in range(BOARD_ROWS):
			if battle_grid[col][row] == null:
				battle_grid[col][row] = unit
				unit.position_on_board = Vector2i(col, row)
				return
