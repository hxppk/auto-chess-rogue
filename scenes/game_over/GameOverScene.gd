extends Control

@onready var title_label: Label = $CenterContent/TitleLabel
@onready var stats_label: Label = $CenterContent/StatsLabel
@onready var restart_button: Button = $CenterContent/RestartButton

func _ready():
	var game_won: bool = GameState.get_meta("game_won", false)

	if game_won:
		title_label.text = "VICTORY!"
		stats_label.text = "Boss defeated!\nWaves cleared: " + str(GameState.current_wave) + "\nHP remaining: " + str(GameState.health)
	else:
		title_label.text = "GAME OVER"
		stats_label.text = "You have fallen...\nWaves survived: " + str(GameState.current_wave - 1) + "\nHP: 0"

	restart_button.pressed.connect(_on_restart_pressed)

func _on_restart_pressed():
	GameState.reset_game()
	GameState.remove_meta("game_won")
	GameState.remove_meta("battle_won")
	GameState.remove_meta("selected_difficulty")
	GameState.remove_meta("battle_difficulty")
	get_tree().change_scene_to_file("res://scenes/preparation/PreparationScene.tscn")
