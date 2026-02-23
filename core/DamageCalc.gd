extends Node
class_name DamageCalc

const CRIT_CHANCE: float = 0.25
const CRIT_MULTIPLIER: float = 1.25

static func calc_physical_damage(attacker_ad: int, defender_arm: int) -> Dictionary:
	var base_damage = attacker_ad * 100.0 / (100.0 + defender_arm)
	var is_crit = randf() < CRIT_CHANCE
	var final_damage = int(base_damage * CRIT_MULTIPLIER) if is_crit else int(base_damage)
	return {"damage": final_damage, "is_crit": is_crit, "type": "physical"}

static func calc_magic_damage(skill_value: float, defender_mdf: int) -> Dictionary:
	var base_damage = skill_value * 100.0 / (100.0 + defender_mdf)
	var is_crit = randf() < CRIT_CHANCE
	var final_damage = int(base_damage * CRIT_MULTIPLIER) if is_crit else int(base_damage)
	return {"damage": final_damage, "is_crit": is_crit, "type": "magic"}

static func calc_heal(heal_value: float) -> Dictionary:
	return {"amount": int(heal_value), "type": "heal"}
