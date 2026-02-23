extends Node
class_name SkillSystem

static var skills_data: Dictionary = {}

static func load_skills(data: Dictionary) -> void:
	if data.has("skills"):
		skills_data = data["skills"]

static func has_skill(unit: UnitData) -> bool:
	return unit.skill_id != "" and skills_data.has(unit.skill_id)

static func is_skill_ready(unit: UnitData) -> bool:
	if not has_skill(unit):
		return false
	var skill = skills_data[unit.skill_id]
	# Boss 用 tick 冷却
	if skill.has("cooldown_ticks"):
		return unit.skill_cooldown_ticks <= 0
	# 普通单位用 MP 触发（满 100 释放）
	return unit.mp >= unit.max_mp

static func get_skill_data(skill_id: String) -> Dictionary:
	return skills_data.get(skill_id, {})

static func execute_skill(unit: UnitData, allies: Array, enemies: Array, battle_grid: Array) -> Array:
	if not has_skill(unit):
		return []
	var skill = skills_data[unit.skill_id]
	var results: Array = []

	match skill.get("damage_type", "physical"):
		"heal":
			results = _execute_heal_skill(unit, skill, allies)
		"physical":
			results = _execute_damage_skill(unit, skill, enemies, battle_grid)

	return results

static func _execute_heal_skill(unit: UnitData, skill: Dictionary, allies: Array) -> Array:
	var results: Array = []
	# 找到血量最低的友方
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
		return results

	var heal_mult = skill.get("heal_multiplier", 2.0)
	var heal_amount = int(unit.ad * (1.0 + unit.ap) * heal_mult)
	results.append({
		"target": lowest,
		"amount": heal_amount,
		"type": "heal",
		"effect": skill.get("effect", "none"),
		"effect_value": skill.get("effect_value", 0),
		"effect_duration_ticks": skill.get("effect_duration_ticks", 0)
	})
	return results

static func _execute_damage_skill(unit: UnitData, skill: Dictionary, enemies: Array, battle_grid: Array) -> Array:
	var results: Array = []
	var targets = get_aoe_targets(unit, skill, enemies, battle_grid)
	var dmg_mult = skill.get("damage_multiplier", 1.5)

	for target in targets:
		var effective_arm = target.get_effective_arm()
		var base_damage = unit.ad * dmg_mult
		var final_damage = int(base_damage * 100.0 / (100.0 + effective_arm))
		results.append({
			"target": target,
			"damage": final_damage,
			"type": "skill",
			"effect": skill.get("effect", "none"),
			"effect_value": skill.get("effect_value", 0),
			"effect_duration_ticks": skill.get("effect_duration_ticks", 0)
		})
	return results

static func get_aoe_targets(unit: UnitData, skill: Dictionary, enemies: Array, _battle_grid: Array) -> Array:
	var shape = skill.get("aoe_shape", "front_cone")
	var aoe_range = skill.get("aoe_range", 2)
	var targets: Array = []
	var unit_pos = unit.position_on_board

	match shape:
		"front_cone":
			# 前方扇形：曼哈顿距离 <= aoe_range 的前方敌人
			# 横版：玩家(team=0)前方是 x 更大(右)；敌方(team=1)前方是 x 更小(左)
			for enemy in enemies:
				if not enemy.is_alive:
					continue
				var dist = absi(enemy.position_on_board.x - unit_pos.x) + absi(enemy.position_on_board.y - unit_pos.y)
				if dist > aoe_range:
					continue
				if unit.team == 0 and enemy.position_on_board.x >= unit_pos.x:
					targets.append(enemy)
				elif unit.team == 1 and enemy.position_on_board.x <= unit_pos.x:
					targets.append(enemy)
				elif dist <= 1:
					targets.append(enemy)

		"line":
			# 直线穿透：同行(同 row)的前方敌人
			for enemy in enemies:
				if not enemy.is_alive:
					continue
				if absi(enemy.position_on_board.y - unit_pos.y) <= 1:
					# 只打前方（玩家向右，敌人向左）
					if unit.team == 0 and enemy.position_on_board.x >= unit_pos.x:
						targets.append(enemy)
					elif unit.team == 1 and enemy.position_on_board.x <= unit_pos.x:
						targets.append(enemy)

	return targets

static func apply_buff(target: UnitData, buff_type: String, value: int, duration_ticks: int) -> void:
	if buff_type == "none":
		return
	var buff_value = value
	if buff_type == "armor_break":
		buff_value = -absi(value)  # armor_break 是负值
	target.buffs.append({
		"type": buff_type,
		"value": buff_value,
		"remaining_ticks": duration_ticks
	})

static func process_buffs(all_units: Array) -> void:
	for unit in all_units:
		if not unit.is_alive:
			continue
		var i = unit.buffs.size() - 1
		while i >= 0:
			unit.buffs[i]["remaining_ticks"] -= 1
			if unit.buffs[i]["remaining_ticks"] <= 0:
				unit.buffs.remove_at(i)
			i -= 1

static func apply_knockback(target: UnitData, away_from: Vector2i, distance: int, battle_grid: Array, board_cols: int, board_rows: int) -> Vector2i:
	var dir = Vector2i(0, 0)
	var diff = target.position_on_board - away_from
	if diff.x != 0:
		dir.x = 1 if diff.x > 0 else -1
	if diff.y != 0:
		dir.y = 1 if diff.y > 0 else -1
	# 如果方向是(0,0)，默认向后推（横版：玩家向左推，敌人向右推）
	if dir == Vector2i(0, 0):
		dir = Vector2i(-1, 0) if target.team == 0 else Vector2i(1, 0)

	var old_pos = target.position_on_board
	var new_pos = old_pos
	for _i in range(distance):
		var next_pos = new_pos + dir
		if next_pos.x < 0 or next_pos.x >= board_cols or next_pos.y < 0 or next_pos.y >= board_rows:
			break
		if battle_grid[next_pos.x][next_pos.y] != null:
			break
		new_pos = next_pos

	if new_pos != old_pos:
		battle_grid[old_pos.x][old_pos.y] = null
		battle_grid[new_pos.x][new_pos.y] = target
		target.position_on_board = new_pos

	return new_pos
