extends Node

signal gold_changed(new_value)
signal health_changed(new_value)
signal wave_changed(new_value)

var gold: int = 15
var health: int = 5
var current_wave: int = 1
var max_waves: int = 5
var player_units: Array = []  # 玩家拥有的单位
var board_layout: Dictionary = {}  # {Vector2i: unit_data} 棋盘布局
var current_enemy_army: Array = []
var current_difficulty: String = ""

func _ready():
	pass

func add_gold(amount: int):
	gold += amount
	gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false

func take_damage(amount: int = 1):
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		get_tree().change_scene_to_file("res://scenes/game_over/GameOverScene.tscn")

func advance_wave():
	current_wave += 1
	wave_changed.emit(current_wave)

func is_boss_wave() -> bool:
	return current_wave == max_waves

func prepare_battle(difficulty: String) -> void:
	current_difficulty = difficulty
	current_enemy_army = DataManager.generate_enemy_army(current_wave, difficulty)

func get_player_army() -> Array:
	# Deep copy player units so battle damage doesn't affect original data
	var army: Array = []
	for pos in board_layout:
		var unit = board_layout[pos]
		if unit is UnitData:
			var copy = unit.duplicate_unit()
			copy.position_on_board = pos
			copy.team = 0
			army.append(copy)
	return army

func clear_battle_data() -> void:
	current_enemy_army.clear()

func reset_game():
	gold = 15
	health = 5
	current_wave = 1
	player_units.clear()
	board_layout.clear()
	current_enemy_army.clear()
	current_difficulty = ""
