extends Control

@onready var result_label: Label = $CenterContent/ResultLabel
@onready var gold_reward_label: Label = $CenterContent/GoldRewardLabel
@onready var health_label: Label = $CenterContent/HealthLabel
@onready var mvp_container: VBoxContainer = $CenterContent/MVPContainer
@onready var mvp_name_label: Label = $CenterContent/MVPContainer/MVPNameLabel
@onready var mvp_damage_label: Label = $CenterContent/MVPContainer/MVPDamageLabel
@onready var continue_button: Button = $CenterContent/ContinueButton

func _ready():
	var won: bool = GameState.get_meta("battle_won", false)
	var difficulty: String = GameState.get_meta("battle_difficulty", "normal")

	if won:
		_handle_victory(difficulty)
	else:
		_handle_defeat()

	# 显示 MVP
	_show_mvp()

	continue_button.pressed.connect(_on_continue_pressed)

func _handle_victory(difficulty: String):
	result_label.text = "VICTORY!"
	var reward = 5
	if difficulty == "hard":
		reward = 15
	elif difficulty == "boss":
		reward = 20

	GameState.add_gold(reward)
	gold_reward_label.text = "Gold +" + str(reward)
	health_label.text = "HP: " + str(GameState.health)

	# Restore all units to full HP after victory
	for pos in GameState.board_layout:
		var unit = GameState.board_layout[pos]
		if unit is UnitData:
			unit.hp = unit.max_hp
			unit.is_alive = true

func _handle_defeat():
	result_label.text = "DEFEAT"
	# Manually reduce health without triggering auto scene change
	GameState.health -= 1
	GameState.health_changed.emit(GameState.health)
	gold_reward_label.text = "Gold +0"
	health_label.text = "HP: " + str(GameState.health)

func _show_mvp():
	var stats: Dictionary = GameState.get_meta("battle_stats", {})
	if stats.is_empty():
		mvp_container.visible = false
		return

	# 找到伤害最高的玩家单位
	var mvp_unit: UnitData = null
	var max_damage: int = 0

	for unit in stats:
		if unit is UnitData and unit.team == 0:
			var dmg = stats[unit].get("damage_dealt", 0)
			if dmg > max_damage:
				max_damage = dmg
				mvp_unit = unit

	if mvp_unit == null or max_damage == 0:
		mvp_container.visible = false
		return

	mvp_container.visible = true
	mvp_name_label.text = "MVP: " + mvp_unit.unit_name
	mvp_damage_label.text = "Total Damage: " + str(max_damage)

	# 高亮样式
	mvp_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	mvp_name_label.add_theme_font_size_override("font_size", 24)
	mvp_damage_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))

func _on_continue_pressed():
	# Check if game over due to health
	if GameState.health <= 0:
		get_tree().change_scene_to_file("res://scenes/game_over/GameOverScene.tscn")
		return

	# Check if boss was defeated (game won)
	var won: bool = GameState.get_meta("battle_won", false)
	if won and GameState.is_boss_wave():
		GameState.set_meta("game_won", true)
		get_tree().change_scene_to_file("res://scenes/game_over/GameOverScene.tscn")
		return

	# Advance wave and return to preparation
	if won:
		GameState.advance_wave()
	GameState.clear_battle_data()
	get_tree().change_scene_to_file("res://scenes/preparation/PreparationScene.tscn")
