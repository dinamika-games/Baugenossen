class_name Ui
extends RefCounted
## Build the interface in code, with large targets that work with the mouse,
## the keyboard and the dwell of the hand (DESIGN.md, 7). Every text is a
## translation key, translated where shown.

## The gap between the buttons of a dialogue: wide, so that the hand cursor
## never takes the neighbour of the button it aims at.
const BUTTON_GAP := 48
const FONT_SIZE := 20
const TITLE_SIZE := 40
const BUTTON_HEIGHT := 52
const PAPER := Color("f4ead6")
const INK := Color("3b2a1c")
const ACCENT := Color("c7682b")
const OK_COLOUR := Color("2f7a3a")
const BAD_COLOUR := Color("b03a2e")


static func make_theme(high_contrast := false) -> Theme:
    var theme := Theme.new()
    theme.default_font_size = FONT_SIZE
    var ink := Color.BLACK if high_contrast else INK
    var paper := Color.WHITE if high_contrast else PAPER
    theme.set_color("font_color", "Label", ink)
    for kind in ["Button", "CheckBox", "OptionButton"]:
        theme.set_color("font_color", kind, ink)
        theme.set_color("font_hover_color", kind, ink)
        theme.set_color("font_pressed_color", kind, ink)
        theme.set_color("font_focus_color", kind, ink)
        theme.set_color("font_disabled_color", kind, Color(ink, 0.4))
    var normal := _box(paper.darkened(0.08), ink, 2 if not high_contrast else 3)
    var hover := _box(paper.darkened(0.16), ink, 2 if not high_contrast else 3)
    var pressed := _box(Color("e8c39a"), ink, 3)
    var focus := _box(Color(0, 0, 0, 0), ACCENT, 4)
    for kind in ["Button", "OptionButton"]:
        theme.set_stylebox("normal", kind, normal)
        theme.set_stylebox("hover", kind, hover)
        theme.set_stylebox("pressed", kind, pressed)
        theme.set_stylebox("disabled", kind, _box(paper.darkened(0.04), Color(ink, 0.3), 2))
        theme.set_stylebox("focus", kind, focus)
    theme.set_stylebox("panel", "PanelContainer", _box(paper, ink, 2))
    theme.set_stylebox("panel", "Panel", _box(paper, ink, 2))
    theme.set_color("font_color", "LineEdit", ink)
    theme.set_color("font_placeholder_color", "LineEdit", Color(ink, 0.55))
    theme.set_stylebox("normal", "LineEdit", _box(Color.WHITE, ink, 2))
    return theme


static func _box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = fill
    box.border_color = border
    box.set_border_width_all(width)
    box.set_corner_radius_all(8)
    box.content_margin_left = 12
    box.content_margin_right = 12
    box.content_margin_top = 6
    box.content_margin_bottom = 6
    return box


static func label(text: String, size := FONT_SIZE, wrap := false) -> Label:
    var result := Label.new()
    result.text = text
    result.add_theme_font_size_override("font_size", size)
    if wrap:
        result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return result


static func button(text: String, action: Callable, minimum_width := 220) -> Button:
    var result := Button.new()
    result.text = text
    result.custom_minimum_size = Vector2(minimum_width, BUTTON_HEIGHT)
    result.pressed.connect(action)
    result.pressed.connect(_click.bind(result))
    return result


static func _click(_button: Button) -> void:
    var tree := Engine.get_main_loop() as SceneTree
    var sounds := tree.root.get_node_or_null("Sounds") if tree != null else null
    if sounds != null:
        sounds.play("click")


static func vbox(separation := 12) -> VBoxContainer:
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", separation)
    return box


static func hbox(separation := 12) -> HBoxContainer:
    var box := HBoxContainer.new()
    box.add_theme_constant_override("separation", separation)
    return box


static func panel(child: Control) -> PanelContainer:
    var result := PanelContainer.new()
    result.add_child(child)
    return result


## A full-screen paper background with a column, which never scrolls: every
## screen fits on one screen (see tests/godot/test_screens.gd); behind the
## column, the player sees themselves dimly
## in the camera picture, so that they see where their hand is (see
## [CameraView]; in the menus only the hands count, so no skeleton).
static func screen(root: Control, high_contrast := false, mirror := true) -> VBoxContainer:
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.theme = make_theme(high_contrast)
    var background := ColorRect.new()
    background.color = Color.WHITE if high_contrast else PAPER
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(background)
    if mirror:
        var camera := CameraView.new()
        camera.cover = true
        camera.picture_alpha = 0.3
        camera.show_skeleton = false
        camera.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        root.add_child(camera)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 32)
    root.add_child(margin)
    var column := vbox(14)
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    margin.add_child(column)
    return column
