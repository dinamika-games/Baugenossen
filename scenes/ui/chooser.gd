class_name Chooser
extends HBoxContainer
## Choose one of a few options with big ◀ and ▶ buttons around the current
## one, so that the hand cursor can choose as well as the mouse (a drop-down
## list opens a popup, which the hand can not reach).

signal changed(index: int)

var options: Array[String] = []
var index := 0
var _label: Label


static func create(labels: Array[String], selected: int, width := 360) -> Chooser:
    var chooser := Chooser.new()
    chooser.options = labels
    chooser.index = clampi(selected, 0, maxi(0, labels.size() - 1))
    chooser.add_theme_constant_override("separation", 8)
    chooser.add_child(Ui.button("◀", chooser.step.bind(-1), 64))
    chooser._label = Ui.label("", Ui.FONT_SIZE)
    chooser._label.custom_minimum_size.x = width
    chooser._label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    chooser.add_child(chooser._label)
    chooser.add_child(Ui.button("▶", chooser.step.bind(1), 64))
    chooser._show()
    return chooser


func step(direction: int) -> void:
    set_index(posmod(index + direction, options.size()))
    changed.emit(index)


func set_index(value: int) -> void:
    index = value
    _show()


func _show() -> void:
    _label.text = options[index] if not options.is_empty() else ""
