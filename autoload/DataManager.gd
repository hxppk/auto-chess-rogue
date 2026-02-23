extends Node

var units_data: Dictionary = {}
var enemies_data: Dictionary = {}
var waves_data: Dictionary = {}
var skills_data: Dictionary = {}

func _ready():
	load_all_data()

func load_all_data():
	units_data = load_json("res://data/units.json")
	enemies_data = load_json("res://data/enemies.json")
	waves_data = load_json("res://data/waves.json")
	skills_data = load_json("res://data/skills.json")
	SkillSystem.load_skills(skills_data)

func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Data file not found: " + path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("JSON parse error in " + path + ": " + json.get_error_message())
		return {}
	return json.data if json.data is Dictionary else {}

func get_unit_data(unit_id: String) -> Dictionary:
	if units_data.has("units") and units_data["units"].has(unit_id):
		return units_data["units"][unit_id]
	return {}

func get_wave_data(wave_number: int, difficulty: String) -> Dictionary:
	var key = "wave_" + str(wave_number)
	if waves_data.has(key) and waves_data[key].has(difficulty):
		return waves_data[key][difficulty]
	return {}

func get_enemy_data(enemy_id: String) -> Dictionary:
	if enemies_data.has("enemies") and enemies_data["enemies"].has(enemy_id):
		return enemies_data["enemies"][enemy_id]
	return {}

func generate_enemy_army(wave: int, difficulty: String) -> Array:
	var wave_data = get_wave_data(wave, difficulty)
	if wave_data.is_empty():
		push_warning("No wave data for wave %d %s" % [wave, difficulty])
		return []

	var army: Array = []
	var enemies_config = wave_data.get("enemies", [])

	for enemy_config in enemies_config:
		var enemy_id = enemy_config.get("id", "")
		var enemy_base = get_enemy_data(enemy_id)
		if enemy_base.is_empty():
			continue

		var unit = UnitData.new()
		unit.init_from_dict(enemy_base)
		unit.team = 1  # Enemy

		# Set board position from waves.json config
		var pos = enemy_config.get("position", [0, 0])
		unit.position_on_board = Vector2i(pos[0], pos[1])

		army.append(unit)

	return army
