extends Control
class_name HealthBar

const BG_COLOR: Color = Color(0.2, 0.2, 0.2, 0.8)
const BORDER_COLOR: Color = Color(0.1, 0.1, 0.1, 1.0)

var bar_width: float = 60.0
var bar_height: float = 8.0
var fixed_color: Color = Color(-1, -1, -1)  # negative r = use ratio color

var current_value: float = 100.0
var max_value: float = 100.0

func _ready():
	custom_minimum_size = Vector2(bar_width, bar_height)
	size = Vector2(bar_width, bar_height)

func _draw():
	# 背景条
	draw_rect(Rect2(0, 0, bar_width, bar_height), BG_COLOR)

	# 当前值条
	if max_value > 0:
		var ratio = clampf(current_value / max_value, 0.0, 1.0)
		var bar_color = fixed_color if fixed_color.r >= 0 else _get_color_by_ratio(ratio)
		draw_rect(Rect2(0, 0, bar_width * ratio, bar_height), bar_color)

	# 边框
	draw_rect(Rect2(0, 0, bar_width, bar_height), BORDER_COLOR, false, 1.0)

func set_value(current: float, max_val: float):
	current_value = current
	max_value = max_val
	queue_redraw()

func setup(w: float, h: float, color: Color = Color(-1, -1, -1)):
	bar_width = w
	bar_height = h
	fixed_color = color
	custom_minimum_size = Vector2(bar_width, bar_height)
	size = Vector2(bar_width, bar_height)

func _get_color_by_ratio(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.2, 0.8, 0.2)   # 绿色
	elif ratio > 0.3:
		return Color(0.9, 0.8, 0.1)   # 黄色
	else:
		return Color(0.9, 0.2, 0.2)   # 红色
