extends VBoxContainer

signal submitted(words: String)
signal dismissed

const Style := preload("res://game/ui/style.gd")
const HISTORY_LIMIT := 40
var editing := false
var lines: PackedStringArray = []
var preview := Label.new()
var log_view := RichTextLabel.new()
var editor := LineEdit.new()
var row := HBoxContainer.new()
var timeout := Timer.new()

func _ready() -> void:
	theme = Style.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.03
	anchor_right = 0.63
	anchor_top = 0.26
	anchor_bottom = 0.26
	grow_vertical = Control.GROW_DIRECTION_END
	preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview.add_theme_stylebox_override("normal", Style.flat(Style.INK, Style.BORDER, 1, 6))
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview)
	log_view.custom_minimum_size.y = 100
	log_view.scroll_following = true
	log_view.add_theme_stylebox_override("normal", Style.flat(Style.INK, Style.BORDER, 1, 6))
	log_view.add_theme_font_size_override("normal_font_size", 16)
	add_child(log_view)
	add_child(row)
	editor.placeholder_text = "输入消息"
	editor.max_length = WastelandSession.CHAT_LENGTH
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(editor)
	row.add_child(Style.button("发送", _submit))
	row.add_child(Style.button("关闭", dismissed.emit))
	editor.text_submitted.connect(func(_words: String): _submit())
	timeout.one_shot = true
	timeout.timeout.connect(preview.hide)
	add_child(timeout)
	reset()

func reset() -> void:
	lines.clear()
	log_view.clear()
	preview.text = ""
	preview.hide()
	timeout.stop()
	close_input()

func open_input() -> void:
	editing = true
	preview.hide()
	log_view.show()
	row.show()
	editor.grab_focus()
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		editor.edit()

func close_input() -> void:
	editing = false
	editor.clear()
	editor.release_focus()
	row.hide()
	log_view.hide()
	preview.visible = not timeout.is_stopped()

func receive(sender: String, words: String) -> void:
	var line := "%s　%s" % [sender, words]
	lines.append(line)
	if lines.size() > HISTORY_LIMIT:
		lines.remove_at(0)
	log_view.text = "\n".join(lines)
	log_view.scroll_to_line(log_view.get_line_count() - 1)
	preview.text = line
	preview.visible = not editing
	timeout.start(6.0)

func _submit() -> void:
	var words := editor.text.strip_edges()
	if words.is_empty():
		editor.grab_focus()
		return
	submitted.emit(words)
	dismissed.emit()
