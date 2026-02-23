extends VBoxContainer
class_name UnitInfoPanel

signal upgrade_requested
signal sell_requested

# Node references (built in _ready)
var name_label: Label
var role_label: Label
var hp_label: Label
var hp_bar: HealthBar
var mp_label: Label
var mp_bar: HealthBar
var ad_label: Label
var ap_label: Label
var arm_label: Label
var mdf_label: Label
var spd_label: Label
var arg_label: Label
var skill_label: Label
var upgrade_button: Button
var sell_button: Button
var placeholder_label: Label

var _stats_container: VBoxContainer
var _buttons_container: VBoxContainer

var current_unit: UnitData = null

func _ready():
	_build_ui()
	show_empty()

func _build_ui():
	add_theme_constant_override("separation", 4)

	# -- Title area --
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", ThemeManager.COLOR_ACCENT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(name_label)

	role_label = Label.new()
	role_label.add_theme_font_size_override("font_size", 11)
	role_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_DIM)
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(role_label)

	# Separator
	var sep = HSeparator.new()
	add_child(sep)

	# -- Stats area --
	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 2)
	add_child(_stats_container)

	# HP row with mini bar
	var hp_row = VBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 1)
	_stats_container.add_child(hp_row)

	hp_label = _make_stat_label()
	hp_row.add_child(hp_label)

	hp_bar = HealthBar.new()
	hp_bar.custom_minimum_size = Vector2(0, 6)
	hp_row.add_child(hp_bar)

	# MP row with mini bar（蓝条）
	var mp_row = VBoxContainer.new()
	mp_row.name = "MPRow"
	mp_row.add_theme_constant_override("separation", 1)
	_stats_container.add_child(mp_row)

	mp_label = _make_stat_label()
	mp_row.add_child(mp_label)

	mp_bar = HealthBar.new()
	mp_row.add_child(mp_bar)
	# Override after _ready so defaults don't overwrite
	mp_bar.fixed_color = Color(0.3, 0.5, 0.9)
	mp_bar.bar_height = 4.0
	mp_bar.custom_minimum_size = Vector2(0, 4)

	ad_label = _make_stat_label()
	_stats_container.add_child(ad_label)

	ap_label = _make_stat_label()
	_stats_container.add_child(ap_label)

	arm_label = _make_stat_label()
	_stats_container.add_child(arm_label)

	mdf_label = _make_stat_label()
	_stats_container.add_child(mdf_label)

	spd_label = _make_stat_label()
	_stats_container.add_child(spd_label)

	arg_label = _make_stat_label()
	_stats_container.add_child(arg_label)

	# Skill label
	skill_label = _make_stat_label()
	skill_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	_stats_container.add_child(skill_label)

	# Separator before buttons
	var sep2 = HSeparator.new()
	add_child(sep2)

	# -- Buttons --
	_buttons_container = VBoxContainer.new()
	_buttons_container.add_theme_constant_override("separation", 4)
	add_child(_buttons_container)

	upgrade_button = Button.new()
	upgrade_button.text = "升级"
	upgrade_button.custom_minimum_size = Vector2(0, 32)
	_style_button(upgrade_button, ThemeManager.COLOR_INFO)
	upgrade_button.pressed.connect(func(): upgrade_requested.emit())
	_buttons_container.add_child(upgrade_button)

	sell_button = Button.new()
	sell_button.text = "出售"
	sell_button.custom_minimum_size = Vector2(0, 32)
	_style_button(sell_button, ThemeManager.COLOR_DANGER)
	sell_button.pressed.connect(func(): sell_requested.emit())
	_buttons_container.add_child(sell_button)

	# -- Placeholder label (shown when no unit selected) --
	placeholder_label = Label.new()
	placeholder_label.text = "选择单位\n查看属性"
	placeholder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	placeholder_label.add_theme_font_size_override("font_size", 12)
	placeholder_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_DIM)
	add_child(placeholder_label)

func show_unit(unit: UnitData):
	current_unit = unit
	placeholder_label.visible = false
	name_label.visible = true
	role_label.visible = true
	_stats_container.visible = true
	_buttons_container.visible = true
	_set_separators_visible(true)

	name_label.text = "%s Lv.%d" % [unit.unit_name, unit.level]
	role_label.text = unit.role

	hp_label.text = "HP:  %d / %d" % [unit.hp, unit.max_hp]
	hp_bar.set_value(unit.hp, unit.max_hp)

	# MP 显示
	var mp_row = _stats_container.get_node_or_null("MPRow")
	if unit.skill_id != "":
		if mp_row:
			mp_row.visible = true
		mp_label.text = "MP:  %d / %d" % [unit.mp, unit.max_mp]
		mp_bar.set_value(unit.mp, unit.max_mp)
	else:
		if mp_row:
			mp_row.visible = false

	ad_label.text = "AD:  %d" % unit.ad
	ap_label.text = "AP:  %s%%" % str(unit.ap)
	arm_label.text = "ARM: %d" % unit.arm
	mdf_label.text = "MDF: %d" % unit.mdf
	spd_label.text = "SPD: %ss" % str(unit.spd)
	arg_label.text = "ARG: %d格" % unit.arg

	# Skill display
	if unit.skill_id != "":
		var skill_data = SkillSystem.get_skill_data(unit.skill_id)
		var s_name = skill_data.get("name", unit.skill_id)
		var s_desc = skill_data.get("description", "")
		skill_label.text = "技能: %s" % s_name
		skill_label.tooltip_text = s_desc
		skill_label.visible = true
	else:
		skill_label.text = ""
		skill_label.visible = false

	# Upgrade button
	if unit.can_upgrade():
		var cost = unit.get_upgrade_cost()
		upgrade_button.text = "升级 (%d金)" % cost
		upgrade_button.disabled = false
	else:
		upgrade_button.text = "已满级"
		upgrade_button.disabled = true

	# Sell button
	var sell_price = unit.get_sell_price()
	sell_button.text = "出售 (+%d金)" % sell_price

func show_shop_preview(data: Dictionary):
	"""显示商店单位预览（P1-6）"""
	current_unit = null
	placeholder_label.visible = false
	name_label.visible = true
	role_label.visible = true
	_stats_container.visible = true
	_buttons_container.visible = false  # 不显示升级/出售按钮
	_set_separators_visible(true)

	name_label.text = data.get("name", "???")
	role_label.text = data.get("role", "")

	var hp_val = data.get("hp", 0)
	hp_label.text = "HP:  %d" % hp_val
	hp_bar.set_value(hp_val, hp_val)

	# MP
	var mp_row = _stats_container.get_node_or_null("MPRow")
	var skill_id_str = data.get("skill", "")
	if skill_id_str != "":
		if mp_row:
			mp_row.visible = true
		mp_label.text = "MP:  0 / 100"
		mp_bar.set_value(0, 100)
	else:
		if mp_row:
			mp_row.visible = false

	ad_label.text = "AD:  %d" % data.get("ad", 0)
	ap_label.text = "AP:  %s%%" % str(data.get("ap", 0.0))
	arm_label.text = "ARM: %d" % data.get("arm", 0)
	mdf_label.text = "MDF: %d" % data.get("mdf", 0)
	spd_label.text = "SPD: %ss" % str(data.get("spd", 0.0))
	arg_label.text = "ARG: %d格" % data.get("arg", 1)

	# Skill
	if skill_id_str != "":
		var skill_data = SkillSystem.get_skill_data(skill_id_str)
		var s_name = skill_data.get("name", skill_id_str)
		var s_desc = skill_data.get("description", "")
		skill_label.text = "技能: %s" % s_name
		skill_label.tooltip_text = s_desc
		skill_label.visible = true
	else:
		skill_label.text = ""
		skill_label.visible = false

func show_empty():
	current_unit = null
	placeholder_label.visible = true
	name_label.visible = false
	role_label.visible = false
	_stats_container.visible = false
	_buttons_container.visible = false
	_set_separators_visible(false)

func _set_separators_visible(vis: bool):
	for child in get_children():
		if child is HSeparator:
			child.visible = vis

func _make_stat_label() -> Label:
	var label = Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT)
	return label

func _style_button(btn: Button, color: Color):
	var normal_sb = StyleBoxFlat.new()
	normal_sb.bg_color = color.darkened(0.2)
	normal_sb.border_color = color
	normal_sb.set_border_width_all(1)
	normal_sb.set_corner_radius_all(3)
	normal_sb.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", normal_sb)

	var hover_sb = StyleBoxFlat.new()
	hover_sb.bg_color = color
	hover_sb.border_color = color.lightened(0.2)
	hover_sb.set_border_width_all(1)
	hover_sb.set_corner_radius_all(3)
	hover_sb.set_content_margin_all(4)
	btn.add_theme_stylebox_override("hover", hover_sb)

	var pressed_sb = StyleBoxFlat.new()
	pressed_sb.bg_color = color.darkened(0.4)
	pressed_sb.border_color = color.darkened(0.1)
	pressed_sb.set_border_width_all(1)
	pressed_sb.set_corner_radius_all(3)
	pressed_sb.set_content_margin_all(4)
	btn.add_theme_stylebox_override("pressed", pressed_sb)

	var disabled_sb = StyleBoxFlat.new()
	disabled_sb.bg_color = ThemeManager.COLOR_BTN_DISABLED
	disabled_sb.border_color = ThemeManager.COLOR_BTN_DISABLED.lightened(0.1)
	disabled_sb.set_border_width_all(1)
	disabled_sb.set_corner_radius_all(3)
	disabled_sb.set_content_margin_all(4)
	btn.add_theme_stylebox_override("disabled", disabled_sb)
