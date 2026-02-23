extends PanelContainer
class_name UnitShopCard

signal card_clicked(unit_id: String)
signal card_drag_started(unit_id: String)

var unit_id: String = ""
var unit_cost: int = 0
var is_selected: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _is_pressing: bool = false
const DRAG_THRESHOLD: float = 5.0

# Role color mapping
const ROLE_COLORS = {
	"近战坦克": Color(0.3, 0.5, 0.9),
	"近战输出": Color(0.9, 0.3, 0.3),
	"远程物理": Color(0.2, 0.8, 0.3),
	"远程魔法": Color(0.7, 0.3, 0.9),
	"远程治疗": Color(0.9, 0.9, 0.3),
}

var _normal_style: StyleBoxFlat
var _selected_style: StyleBoxFlat

func _init():
	custom_minimum_size = Vector2(230, 90)

func setup(data: Dictionary) -> void:
	unit_id = data.get("id", "")
	unit_cost = data.get("cost", 5)
	var unit_name = data.get("name", "???")
	var role = data.get("role", "")

	# Build styles
	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = Color(0.25, 0.22, 0.18)
	_normal_style.border_color = Color(0.4, 0.35, 0.28)
	_normal_style.set_border_width_all(2)
	_normal_style.set_corner_radius_all(4)
	_normal_style.set_content_margin_all(6)

	_selected_style = StyleBoxFlat.new()
	_selected_style.bg_color = Color(0.30, 0.27, 0.22)
	_selected_style.border_color = Color(0.9, 0.75, 0.3)
	_selected_style.set_border_width_all(3)
	_selected_style.set_corner_radius_all(4)
	_selected_style.set_content_margin_all(5)

	add_theme_stylebox_override("panel", _normal_style)

	# HBoxContainer
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	# Color icon representing role
	var color_icon = ColorRect.new()
	color_icon.custom_minimum_size = Vector2(48, 48)
	color_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	color_icon.color = ROLE_COLORS.get(role, Color(0.7, 0.7, 0.7))
	hbox.add_child(color_icon)

	# VBoxContainer for text
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	# Unit name label
	var name_label = Label.new()
	name_label.text = unit_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	vbox.add_child(name_label)

	# Role label (small, dim)
	var role_label = Label.new()
	role_label.text = role
	role_label.add_theme_font_size_override("font_size", 13)
	role_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	vbox.add_child(role_label)

	# Cost label (gold color)
	var cost_label = Label.new()
	cost_label.text = str(unit_cost) + " 金"
	cost_label.add_theme_font_size_override("font_size", 14)
	cost_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	vbox.add_child(cost_label)

func set_selected(selected: bool) -> void:
	is_selected = selected
	if _selected_style and _normal_style:
		add_theme_stylebox_override("panel", _selected_style if selected else _normal_style)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_pressing = true
			_press_position = event.global_position
		else:
			if _is_pressing:
				_is_pressing = false
				# 释放时没有超过阈值 = 普通点击
				if _press_position.distance_to(event.global_position) < DRAG_THRESHOLD:
					card_clicked.emit(unit_id)
	elif event is InputEventMouseMotion and _is_pressing:
		if _press_position.distance_to(event.global_position) >= DRAG_THRESHOLD:
			_is_pressing = false
			card_drag_started.emit(unit_id)
