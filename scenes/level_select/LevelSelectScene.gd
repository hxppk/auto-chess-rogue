extends Control

@onready var title_label: Label = $TitleLabel
@onready var cards_container: HBoxContainer = $CardsContainer
@onready var normal_panel: Panel = $CardsContainer/NormalPanel
@onready var hard_panel: Panel = $CardsContainer/HardPanel
@onready var normal_button: Button = $CardsContainer/NormalPanel/NormalContent/NormalButton
@onready var hard_button: Button = $CardsContainer/HardPanel/HardContent/HardButton
@onready var normal_desc: Label = $CardsContainer/NormalPanel/NormalContent/NormalDesc
@onready var hard_desc: Label = $CardsContainer/HardPanel/HardContent/HardDesc

func _ready():
	title_label.text = "Select Challenge - Wave " + str(GameState.current_wave)

	if GameState.is_boss_wave():
		_setup_boss_wave()
	else:
		_setup_normal_wave()

func _setup_normal_wave():
	var normal_data = DataManager.get_wave_data(GameState.current_wave, "normal")
	var hard_data = DataManager.get_wave_data(GameState.current_wave, "hard")

	normal_desc.text = normal_data.get("description", "Normal enemies await.")
	hard_desc.text = hard_data.get("description", "Stronger enemies, greater reward!")

	normal_button.text = "Normal (+5 Gold)"
	hard_button.text = "Hard (+15 Gold)"

	normal_button.pressed.connect(_on_normal_selected)
	hard_button.pressed.connect(_on_hard_selected)

	normal_panel.visible = true
	hard_panel.visible = true

func _setup_boss_wave():
	var boss_data = DataManager.get_wave_data(GameState.current_wave, "boss")

	normal_desc.text = boss_data.get("description", "The Boss awaits!")
	normal_button.text = "Fight Boss"
	normal_button.pressed.connect(_on_boss_selected)

	normal_panel.visible = true
	hard_panel.visible = false

func _on_normal_selected():
	_start_battle("normal")

func _on_hard_selected():
	_start_battle("hard")

func _on_boss_selected():
	_start_battle("boss")

func _start_battle(difficulty: String):
	GameState.set_meta("selected_difficulty", difficulty)
	GameState.prepare_battle(difficulty)
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene.tscn")
