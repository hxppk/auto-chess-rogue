extends Node

# ============================================================
# ThemeManager - Global UI theme for pixel-adventure style
# ============================================================

# -- Color palette --
const COLOR_BG_DARK       := Color(0.18, 0.15, 0.12)
const COLOR_PANEL_BG      := Color(0.28, 0.24, 0.20)
const COLOR_PANEL_BORDER  := Color(0.45, 0.38, 0.30)
const COLOR_BTN_NORMAL    := Color(0.35, 0.55, 0.35)
const COLOR_BTN_HOVER     := Color(0.45, 0.65, 0.45)
const COLOR_BTN_PRESSED   := Color(0.25, 0.45, 0.25)
const COLOR_BTN_DISABLED  := Color(0.4, 0.4, 0.4)
const COLOR_ACCENT        := Color(0.9, 0.75, 0.3)       # gold
const COLOR_DANGER        := Color(0.85, 0.3, 0.3)       # red
const COLOR_HEAL          := Color(0.3, 0.85, 0.4)       # green
const COLOR_INFO          := Color(0.4, 0.7, 0.95)       # blue
const COLOR_TEXT           := Color(0.95, 0.92, 0.85)     # warm white
const COLOR_TEXT_DIM       := Color(0.7, 0.65, 0.55)      # dim beige

var game_theme: Theme

func _ready() -> void:
	game_theme = _build_theme()
	# Apply the theme to the root viewport so every Control inherits it
	get_tree().root.theme = game_theme

# ----------------------------------------------------------
# Theme construction
# ----------------------------------------------------------
func _build_theme() -> Theme:
	var t := Theme.new()

	# -- Default font sizes --
	t.set_default_font_size(14)

	# -- Label --
	t.set_color("font_color", "Label", COLOR_TEXT)
	t.set_font_size("font_size", "Label", 14)

	# -- Button --
	t.set_stylebox("normal",   "Button", _make_button_box(COLOR_BTN_NORMAL))
	t.set_stylebox("hover",    "Button", _make_button_box(COLOR_BTN_HOVER))
	t.set_stylebox("pressed",  "Button", _make_button_box(COLOR_BTN_PRESSED))
	t.set_stylebox("disabled", "Button", _make_button_box(COLOR_BTN_DISABLED))
	t.set_color("font_color",          "Button", COLOR_TEXT)
	t.set_color("font_hover_color",    "Button", Color.WHITE)
	t.set_color("font_pressed_color",  "Button", COLOR_TEXT_DIM)
	t.set_color("font_disabled_color", "Button", Color(0.6, 0.6, 0.6))
	t.set_font_size("font_size", "Button", 14)

	# -- Panel --
	t.set_stylebox("panel", "Panel", _make_panel_box())

	# -- PanelContainer --
	t.set_stylebox("panel", "PanelContainer", _make_panel_box())

	# -- HBoxContainer / VBoxContainer separations --
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 6)

	return t

# ----------------------------------------------------------
# StyleBox helpers
# ----------------------------------------------------------
func _make_panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL_BG
	sb.border_color = COLOR_PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	return sb

func _make_button_box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = color.lightened(0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.content_margin_left   = 12
	sb.content_margin_right  = 12
	sb.content_margin_top    = 6
	sb.content_margin_bottom = 6
	return sb

func _make_flat_box(color: Color, border: Color = Color.TRANSPARENT, border_width: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	if border_width > 0:
		sb.border_color = border
		sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb

# ----------------------------------------------------------
# Convenience: create styled PanelContainer wrapping content
# ----------------------------------------------------------
func make_styled_panel(bg: Color = COLOR_PANEL_BG, border: Color = COLOR_PANEL_BORDER, border_width: int = 2) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)
	return pc

# ----------------------------------------------------------
# Public helpers other scripts can use
# ----------------------------------------------------------
func apply_theme(node: Control) -> void:
	node.theme = game_theme

func get_accent_color() -> Color:
	return COLOR_ACCENT

func get_danger_color() -> Color:
	return COLOR_DANGER

func get_heal_color() -> Color:
	return COLOR_HEAL

func get_info_color() -> Color:
	return COLOR_INFO
