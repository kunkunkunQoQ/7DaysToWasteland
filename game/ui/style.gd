class_name WastelandUIStyle
extends RefCounted

const INK := Color("#0f191a")
const PANEL := Color("#1c2c2b")
const BORDER := Color("#495954")
const TEXT := Color("#f2ead6")
const MUTED := Color("#b6c6b9")
const FAINT := Color("#91a39a")
const GOLD := Color("#f7bd82")
const MINT := Color("#99c9ba")
const RED := Color("#ef918e")
const FONT := preload("res://assets/fusion-pixel-12px-zh-hans.ttf")
static var shared_theme: Theme

static func flat(fill: Color, edge: Color, width: int = 1, inset: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(width)
	box.content_margin_left = inset
	box.content_margin_right = inset
	box.content_margin_top = inset
	box.content_margin_bottom = inset
	return box

static func theme() -> Theme:
	if shared_theme != null:
		return shared_theme
	var ui_theme := Theme.new()
	ui_theme.default_font = FONT
	ui_theme.default_font_size = 18
	ui_theme.set_color("font_color", "Label", TEXT)
	for type in ["Button","OptionButton","CheckButton","CheckBox","LineEdit","SpinBox","TabContainer","Tree","ItemList"]:
		for state in ["font_color","font_hover_color","font_focus_color","font_pressed_color","font_selected_color"]:
			ui_theme.set_color(state, type, TEXT)
		ui_theme.set_color("font_disabled_color", type, FAINT)
	for type in ["Button","OptionButton"]:
		ui_theme.set_stylebox("normal", type, flat(Color("#263431"), BORDER, 1, 11))
		ui_theme.set_stylebox("hover", type, flat(Color("#384c44"), MINT, 1, 11))
		ui_theme.set_stylebox("pressed", type, flat(Color("#55503c"), GOLD, 1, 11))
		ui_theme.set_stylebox("disabled", type, flat(Color("#1b2524"), Color("#32403c"), 1, 11))
		ui_theme.set_stylebox("focus", type, flat(Color.TRANSPARENT, GOLD, 1, 11))
	for type in ["LineEdit","ItemList","Tree"]:
		ui_theme.set_stylebox("normal", type, flat(INK, BORDER, 1, 9))
		ui_theme.set_stylebox("focus", type, flat(Color.TRANSPARENT, GOLD, 1, 9))
	ui_theme.set_color("font_placeholder_color", "LineEdit", FAINT)
	ui_theme.set_color("caret_color", "LineEdit", GOLD)
	ui_theme.set_color("selection_color", "LineEdit", Color("#704a49"))
	ui_theme.set_stylebox("panel", "PanelContainer", flat(Color("#152322f4"), Color("#68756a"), 1, 20))
	ui_theme.set_stylebox("panel", "TabContainer", flat(PANEL, BORDER, 1, 14))
	ui_theme.set_stylebox("tab_selected", "TabContainer", flat(Color("#553b46"), GOLD, 1, 10))
	ui_theme.set_stylebox("tab_unselected", "TabContainer", flat(Color("#272030"), BORDER, 1, 10))
	ui_theme.set_stylebox("tab_hovered", "TabContainer", flat(Color("#36283b"), GOLD.darkened(0.3), 1, 10))
	ui_theme.set_stylebox("panel", "PopupMenu", flat(PANEL, BORDER, 1, 6))
	ui_theme.set_stylebox("hover", "PopupMenu", flat(Color("#513746"), Color.TRANSPARENT, 0, 7))
	ui_theme.set_color("font_color", "PopupMenu", TEXT)
	ui_theme.set_color("font_hover_color", "PopupMenu", GOLD)
	ui_theme.set_constant("v_separation", "PopupMenu", 12)
	ui_theme.set_stylebox("scroll", "VScrollBar", flat(INK, BORDER, 1, 3))
	ui_theme.set_stylebox("grabber", "VScrollBar", flat(Color("#665268"), Color.TRANSPARENT, 0, 3))
	ui_theme.set_stylebox("grabber_highlight", "VScrollBar", flat(Color("#846a81"), Color.TRANSPARENT, 0, 3))
	ui_theme.set_stylebox("background", "ProgressBar", flat(INK, BORDER, 1, 0))
	ui_theme.set_stylebox("fill", "ProgressBar", flat(GOLD, GOLD, 0, 0))
	ui_theme.set_constant("separation", "VBoxContainer", 9)
	ui_theme.set_constant("separation", "HBoxContainer", 10)
	shared_theme = ui_theme
	return shared_theme

static func label(text: String, scale: int = 18, tint: Color = TEXT, wrap: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_color_override("font_color", tint)
	node.add_theme_font_size_override("font_size", scale)
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func button(text: String, action: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 42.0
	if primary:
		node.add_theme_color_override("font_color", GOLD)
		node.add_theme_stylebox_override("normal", flat(Color("#3c4132"), Color("#ac8b62"), 1, 11))
	node.pressed.connect(action)
	return node

static func column(parent: Control, spacing: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	parent.add_child(box)
	return box

static func line(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	return row

static func fill(parent: BoxContainer) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

static func rule(parent: Control, color: Color = BORDER) -> void:
	var rect := ColorRect.new()
	rect.custom_minimum_size.y = 1
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

static func scroller(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column
