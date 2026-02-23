extends Resource
class_name UnitData

# 基础属性
@export var id: String = ""
@export var unit_name: String = ""
@export var role: String = ""  # 近战坦克/近战输出/远程物理/远程魔法/远程治疗
@export var cost: int = 5
@export var rarity: String = "common"

# 战斗属性
@export var hp: int = 0
@export var max_hp: int = 0
@export var ad: int = 0       # 物理攻击
@export var ap: float = 0.0   # 魔法攻击百分比
@export var arm: int = 0      # 护甲
@export var mdf: int = 0      # 魔抗
@export var spd: float = 0.0  # 攻速(秒/次)
@export var arg: int = 1      # 攻击距离(格)

# MP 蓝量系统
var mp: int = 0
var max_mp: int = 100

# 升级相关
@export var level: int = 1
@export var max_level: int = 2
var upgrade_cost_multiplier: float = 1.5  # 升级费用=原价×倍率
var stat_multiplier: float = 1.3          # 属性提升倍率

# 技能相关
var skill_id: String = ""
var skill_attack_counter: int = 0  # 保留兼容（已改用 MP 触发）
var skill_cooldown_ticks: int = 0  # 保留兼容
var buffs: Array = []  # [{type, value, remaining_ticks}]

# 状态
var is_alive: bool = true
var position_on_board: Vector2i = Vector2i(-1, -1)
var team: int = 0  # 0=玩家, 1=敌方

func init_from_dict(data: Dictionary) -> void:
	id = data.get("id", "")
	unit_name = data.get("name", "")
	role = data.get("role", "")
	cost = data.get("cost", 5)
	rarity = data.get("rarity", "common")
	hp = data.get("hp", 0)
	max_hp = hp
	ad = data.get("ad", 0)
	ap = data.get("ap", 0.0)
	arm = data.get("arm", 0)
	mdf = data.get("mdf", 0)
	spd = data.get("spd", 0.0)
	arg = data.get("arg", 1)
	skill_id = data.get("skill", "")
	max_mp = data.get("max_mp", 100)
	mp = 0

func can_upgrade() -> bool:
	return level < max_level

func get_upgrade_cost() -> int:
	return int(cost * upgrade_cost_multiplier)

func upgrade() -> void:
	if not can_upgrade():
		return
	level += 1
	max_hp = int(max_hp * stat_multiplier)
	hp = max_hp
	ad = int(ad * stat_multiplier)
	arm = int(arm * stat_multiplier)
	mdf = int(mdf * stat_multiplier)

func take_damage(amount: int) -> int:
	var actual = mini(amount, hp)
	hp -= actual
	if hp <= 0:
		is_alive = false
	# 受击时获得 MP (+3)
	if is_alive and skill_id != "":
		mp = mini(mp + 3, max_mp)
	return actual

func heal(amount: int) -> int:
	var actual = mini(amount, max_hp - hp)
	hp += actual
	return actual

func gain_mp(amount: int) -> void:
	if skill_id != "":
		mp = mini(mp + amount, max_mp)

func get_sell_price() -> int:
	return int(cost * 0.8)

func is_ranged() -> bool:
	return arg > 1

func get_detection_range() -> int:
	# 索敌范围远大于攻击范围
	return maxi(arg + 3, arg * 2)

func get_effective_arm() -> int:
	var effective = arm
	for buff in buffs:
		if buff["type"] == "armor_break":
			effective += buff["value"]  # value is negative
		elif buff["type"] == "armor_buff":
			effective += buff["value"]
	return maxi(effective, 0)

func duplicate_unit() -> UnitData:
	var copy = UnitData.new()
	copy.id = id
	copy.unit_name = unit_name
	copy.role = role
	copy.cost = cost
	copy.rarity = rarity
	copy.hp = hp
	copy.max_hp = max_hp
	copy.ad = ad
	copy.ap = ap
	copy.arm = arm
	copy.mdf = mdf
	copy.spd = spd
	copy.arg = arg
	copy.level = level
	copy.team = team
	copy.skill_id = skill_id
	copy.mp = 0
	copy.max_mp = max_mp
	copy.is_alive = true
	return copy
